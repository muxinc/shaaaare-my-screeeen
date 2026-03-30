import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

@MainActor
class ScreenRecorder: NSObject, ObservableObject {
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var recordingSession: RecordingSession?
    private var cameraCapture: CameraCapture?
    private var outputURL: URL?
    private var streamFailure: Error?

    func prepareCapture(
        display: SCDisplay?,
        window: SCWindow?,
        captureSystemAudio: Bool
    ) async throws {
        let filter = try await makeContentFilter(display: display, window: window)
        let config = makeStreamConfiguration(
            display: display,
            window: window,
            captureSystemAudio: captureSystemAudio
        )

        let warmup = CaptureWarmup(filter: filter, configuration: config, captureSystemAudio: captureSystemAudio)
        try await warmup.run()
    }

    func startRecording(
        display: SCDisplay?,
        window: SCWindow?,
        camera: AVCaptureDevice?,
        captureSystemAudio: Bool,
        captureMicrophone: Bool,
        outputURL: URL
    ) async throws {
        self.outputURL = outputURL
        self.streamFailure = nil

        let filter = try await makeContentFilter(display: display, window: window)
        let config = makeStreamConfiguration(
            display: display,
            window: window,
            captureSystemAudio: captureSystemAudio
        )

        let videoWidth = config.width
        let videoHeight = config.height

        let session = RecordingSession(
            outputURL: outputURL,
            width: videoWidth,
            height: videoHeight,
            captureSystemAudio: captureSystemAudio,
            captureMicrophone: captureMicrophone
        )
        try session.start()
        self.recordingSession = session

        if let camera {
            let camCapture = CameraCapture(device: camera) { [weak session] sampleBuffer in
                session?.appendCameraBuffer(sampleBuffer)
            }
            try camCapture.start()
            self.cameraCapture = camCapture
        }

        let output = StreamOutput(recordingSession: session)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        if captureSystemAudio {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        }

        try await stream.startCapture()
        self.stream = stream
        self.streamOutput = output
    }

    func stopRecording() async throws -> URL {
        if let stream {
            try await stream.stopCapture()
            self.stream = nil
        }
        streamOutput = nil

        cameraCapture?.stop()
        cameraCapture = nil

        guard let session = recordingSession else {
            throw RecordingError.noActiveRecording
        }

        if let streamFailure {
            throw RecordingError.capturePreparationFailed(detailedNSError(streamFailure))
        }

        let url = try await session.stop()
        recordingSession = nil
        return url
    }

    private func makeContentFilter(display: SCDisplay?, window: SCWindow?) async throws -> SCContentFilter {
        if let window {
            return SCContentFilter(desktopIndependentWindow: window)
        }

        if let display {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let excludedApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            return SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
        }

        throw RecordingError.noSourceSelected
    }

    private static let maxWidth = 3840
    private static let maxHeight = 2160

    private func makeStreamConfiguration(
        display: SCDisplay?,
        window: SCWindow?,
        captureSystemAudio: Bool
    ) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        var rawWidth = 1920
        var rawHeight = 1080

        if let display {
            rawWidth = Int(display.width) * 2
            rawHeight = Int(display.height) * 2
        } else if let window {
            rawWidth = Int(window.frame.width) * 2
            rawHeight = Int(window.frame.height) * 2
        }

        // Clamp to 4K UHD
        let scale = min(
            Double(Self.maxWidth) / Double(rawWidth),
            Double(Self.maxHeight) / Double(rawHeight),
            1.0
        )
        // Round DOWN to multiples of 16.  Hardware video encoders (H.264 & HEVC)
        // allocate internal buffers at 16-pixel-aligned dimensions.  Non-aligned
        // sizes like 2114 cause kCMSampleBufferError_ArrayTooSmall (-12737).
        config.width = Int(Double(rawWidth) * scale) & ~15
        config.height = Int(Double(rawHeight) * scale) & ~15

        appLog("[ScreenRecorder] Resolution: raw=\(rawWidth)x\(rawHeight), aligned=\(config.width)x\(config.height)")
        if scale < 1.0 {
            appLog("[ScreenRecorder] Clamped resolution (scale=\(scale))")
        }

        config.showsCursor = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 5
        config.capturesAudio = captureSystemAudio
        config.sampleRate = 48000
        config.channelCount = 2
        return config
    }
}

enum RecordingError: LocalizedError {
    case noSourceSelected
    case noActiveRecording
    case capturePreparationFailed(String)
    case writingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSourceSelected: return "No display or window selected"
        case .noActiveRecording: return "No active recording to stop"
        case .capturePreparationFailed(let msg): return "Capture preparation failed: \(msg)"
        case .writingFailed(let msg): return "Recording failed: \(msg)"
        }
    }
}

extension ScreenRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        appLog("[ScreenRecorder] Stream stopped with error: \(detailedNSError(error))")
        Task { @MainActor in
            self.streamFailure = error
        }
    }
}

private class StreamOutput: NSObject, SCStreamOutput {
    let recordingSession: RecordingSession
    private var screenFrameCount = 0
    private var audioFrameCount = 0

    init(recordingSession: RecordingSession) {
        self.recordingSession = recordingSession
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            // Only forward frames with new screen content.
            // SCK delivers .idle frames at 60fps when nothing changes on screen;
            // these carry no pixel buffer and cause "Failed to render frame" spam.
            // The fill timer handles keeping the video alive between complete frames.
            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[String: Any]],
                  let attachments = attachmentsArray.first,
                  let statusRawValue = attachments[SCStreamFrameInfo.status.rawValue] as? Int,
                  statusRawValue == SCFrameStatus.complete.rawValue else {
                return
            }
            screenFrameCount += 1
            if screenFrameCount <= 3 {
                appLog("[StreamOutput] Screen frame #\(screenFrameCount) delivered")
            }
            recordingSession.appendScreenBuffer(sampleBuffer)
        case .audio:
            audioFrameCount += 1
            if audioFrameCount <= 3 {
                appLog("[StreamOutput] Audio buffer #\(audioFrameCount) delivered")
            }
            recordingSession.appendSystemAudioBuffer(sampleBuffer)
        case .microphone:
            recordingSession.appendMicAudioBuffer(sampleBuffer)
        @unknown default:
            break
        }
    }
}

private final class CaptureWarmup: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream!
    private let captureSystemAudio: Bool
    private let outputQueue = DispatchQueue(label: "com.mux.capture-warmup")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(filter: SCContentFilter, configuration: SCStreamConfiguration, captureSystemAudio: Bool) {
        self.captureSystemAudio = captureSystemAudio
        super.init()
        self.stream = SCStream(filter: filter, configuration: configuration, delegate: self)
    }

    func run() async throws {
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        if captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            Task {
                do {
                    try await self.stream.startCapture()
                } catch {
                    self.finish(with: .failure(RecordingError.capturePreparationFailed(detailedNSError(error))))
                    return
                }

                try? await Task.sleep(for: .seconds(30))
                self.finish(
                    with: .failure(
                        RecordingError.capturePreparationFailed(
                            "Timed out waiting for the first screen frame"
                        )
                    )
                )
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        finish(with: .success(()))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        finish(with: .failure(RecordingError.capturePreparationFailed(detailedNSError(error))))
    }

    private func finish(with result: Result<Void, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()

        // Must await stream stop before resuming so the old stream is fully
        // torn down before the real recording stream starts.
        Task {
            try? await stream.stopCapture()
            switch result {
            case .success:
                continuation.resume()
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}

private func detailedNSError(_ error: Error) -> String {
    let nsError = error as NSError
    var parts = ["\(nsError.domain) (\(nsError.code))", nsError.localizedDescription]

    if let reason = nsError.localizedFailureReason, !reason.isEmpty {
        parts.append("reason=\(reason)")
    }

    if let suggestion = nsError.localizedRecoverySuggestion, !suggestion.isEmpty {
        parts.append("suggestion=\(suggestion)")
    }

    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
        parts.append("underlying=\(underlying.domain) (\(underlying.code)): \(underlying.localizedDescription)")
    }

    return parts.joined(separator: " | ")
}
