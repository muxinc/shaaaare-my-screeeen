@preconcurrency import AVFoundation
import CoreMedia
import CoreImage
import VideoToolbox

class RecordingSession: @unchecked Sendable {
    private let outputURL: URL
    private let width: Int
    private let height: Int
    private let captureSystemAudio: Bool
    private let captureMicrophone: Bool

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var hasStartedSession = false
    private var sessionStartTime: CMTime?
    private let writingQueue = DispatchQueue(label: "com.mux.recording-session")
    private var frameCount = 0
    private var audioBufferCount = 0
    private var micBufferCount = 0
    private var audioDropCount = 0
    private var writerFailed = false
    private var lastAudioPTS: CMTime = .invalid

    private var micSession: AVCaptureSession?
    private var micOutput: AVCaptureAudioDataOutput?
    private var micDelegate: MicDelegate?

    // Camera compositing state
    private let ciContext = CIContext()
    private var lastCameraBuffer: CMSampleBuffer?
    private let cameraLock = NSLock()
    private let cameraSize: CGFloat = 180

    // Fill timer: re-composites camera onto last screen frame when no new
    // screen frames arrive (window capture only delivers on content change)
    private var lastScreenPixelBuffer: CVPixelBuffer?
    private var lastWrittenTimestamp: CMTime = .invalid
    private var fillTimer: DispatchSourceTimer?

    init(outputURL: URL, width: Int, height: Int, captureSystemAudio: Bool, captureMicrophone: Bool) {
        self.outputURL = outputURL
        self.width = width
        self.height = height
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophone = captureMicrophone
    }

    func start() throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 6,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        writer.add(vInput)
        self.videoInput = vInput

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        self.pixelBufferAdaptor = adaptor

        // Single audio track for all audio sources (system + mic).
        // Multiple audio tracks in MOV cause compatibility issues with some
        // services (e.g. Mux only picks up the first track). Both sources
        // write to the same input with timestamp ordering enforced.
        if captureSystemAudio || captureMicrophone {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            writer.add(aInput)
            self.audioInput = aInput
        }

        appLog("[Recording] Writer configured: \(width)x\(height), systemAudio=\(captureSystemAudio), mic=\(captureMicrophone), output: \(outputURL.lastPathComponent)")

        guard writer.startWriting() else {
            throw RecordingError.writingFailed(writer.error?.localizedDescription ?? "Unknown error")
        }

        self.assetWriter = writer
        appLog("[Recording] Writer started successfully")

        if captureMicrophone {
            startMicrophone()
        }
    }

    func appendScreenBuffer(_ sampleBuffer: CMSampleBuffer) {
        writingQueue.async { [weak self] in
            self?._appendScreenBuffer(sampleBuffer)
        }
    }

    private func _appendScreenBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let writer = assetWriter else { return }

        if writer.status == .failed && !writerFailed {
            writerFailed = true
            appLog("[Recording] *** WRITER FAILED: \(describe(writer.error) ?? "unknown") ***")
            return
        }
        guard writer.status == .writing else { return }
        guard let videoInput, videoInput.isReadyForMoreMediaData else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !hasStartedSession {
            writer.startSession(atSourceTime: timestamp)
            sessionStartTime = timestamp
            hasStartedSession = true
            appLog("[Recording] Session started at \(timestamp.seconds)s")
        }

        frameCount += 1
        if frameCount <= 5 || frameCount % 60 == 0 {
            appLog("[Recording] Frame #\(frameCount) at \(timestamp.seconds)s, writer status: \(writer.status.rawValue)")
        }

        if frameCount <= 5 {
            // Log the format of the first few raw screen frames for debugging.
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
                let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)
                appLog("[Recording] Screen buffer format: type=\(mediaType), dims=\(dims.width)x\(dims.height)")
            }
        }

        guard let adaptor = pixelBufferAdaptor else {
            appLog("[Recording] Missing pixel buffer adaptor")
            return
        }

        // Store the raw screen pixel buffer for the fill timer to reuse
        if let screenPB = CMSampleBufferGetImageBuffer(sampleBuffer) {
            lastScreenPixelBuffer = screenPB
        }

        guard let renderedFrame = renderFrame(screenBuffer: sampleBuffer) else {
            appLog("[Recording] Failed to render frame #\(frameCount)")
            return
        }

        // Ensure monotonically increasing timestamps (fill frames may have advanced the clock)
        var writeTimestamp = timestamp
        if lastWrittenTimestamp.isValid && CMTimeCompare(writeTimestamp, lastWrittenTimestamp) <= 0 {
            writeTimestamp = CMTimeAdd(lastWrittenTimestamp, CMTime(value: 1, timescale: 600))
        }

        let ok = adaptor.append(renderedFrame, withPresentationTime: writeTimestamp)
        if ok {
            lastWrittenTimestamp = writeTimestamp
        } else {
            appLog("[Recording] Failed to append rendered frame #\(frameCount), writer status: \(writer.status.rawValue), error: \(describe(writer.error) ?? "none")")
        }
    }

    func appendCameraBuffer(_ sampleBuffer: CMSampleBuffer) {
        cameraLock.lock()
        let wasEmpty = lastCameraBuffer == nil
        lastCameraBuffer = sampleBuffer
        cameraLock.unlock()

        // Start fill timer when first camera buffer arrives so the camera
        // overlay stays smooth even when screen frames are infrequent
        if wasEmpty {
            writingQueue.async { [weak self] in
                self?.startFillTimer()
            }
        }
    }

    func appendSystemAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        writingQueue.async { [weak self] in
            self?._appendAudioBuffer(sampleBuffer, source: "system")
        }
    }

    func appendMicAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        writingQueue.async { [weak self] in
            self?._appendAudioBuffer(sampleBuffer, source: "mic")
        }
    }

    /// Appends audio from any source to the single shared audio track.
    /// Enforces monotonically increasing timestamps; out-of-order buffers are dropped.
    private func _appendAudioBuffer(_ sampleBuffer: CMSampleBuffer, source: String) {
        guard let writer = assetWriter, writer.status == .writing else { return }
        guard let audioInput, audioInput.isReadyForMoreMediaData else { return }
        guard hasStartedSession else { return }

        let isFirstForSource = (source == "system" && audioBufferCount == 0) || (source == "mic" && micBufferCount == 0)
        if isFirstForSource {
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
                appLog("[Recording] \(source) audio format: sampleRate=\(asbd?.mSampleRate ?? 0), channels=\(asbd?.mChannelsPerFrame ?? 0), bitsPerChannel=\(asbd?.mBitsPerChannel ?? 0)")
            }
        }

        // Enforce monotonically increasing timestamps for the shared audio track
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if lastAudioPTS.isValid && CMTimeCompare(pts, lastAudioPTS) <= 0 {
            audioDropCount += 1
            if audioDropCount <= 5 {
                appLog("[Recording] Dropped out-of-order \(source) audio buffer (pts=\(pts.seconds)s <= last=\(lastAudioPTS.seconds)s)")
            }
            return
        }

        let ok = audioInput.append(sampleBuffer)
        if ok {
            lastAudioPTS = pts
            if source == "system" {
                audioBufferCount += 1
            } else {
                micBufferCount += 1
            }
        } else if (audioBufferCount + micBufferCount) == 0 {
            appLog("[Recording] Failed to append first \(source) audio buffer, writer status: \(writer.status.rawValue), error: \(describe(writer.error) ?? "none")")
        }
    }

    func stop() async throws -> URL {
        appLog("[Recording] Stopping — \(frameCount) video frames, \(audioBufferCount) system audio buffers, \(micBufferCount) mic audio buffers, \(audioDropCount) dropped out-of-order audio buffers")

        stopFillTimer()

        micSession?.stopRunning()
        micSession = nil

        guard let writer = assetWriter else {
            throw RecordingError.noActiveRecording
        }

        if writer.status == .failed {
            throw RecordingError.writingFailed(
                describe(writer.error) ?? "The recorder failed before the file could be finalized"
            )
        }

        if !hasStartedSession || frameCount == 0 {
            appLog("[Recording] Stop requested before the first screen frame arrived")
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            assetWriter = nil
            throw RecordingError.writingFailed(
                "No screen frames were captured. Grant screen access before recording and try again."
            )
        }

        // Drain the writing queue before finishing, so all pending frames are flushed
        let url: URL = try await withCheckedThrowingContinuation { continuation in
            writingQueue.async {
                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()

                writer.finishWriting {
                    let fileExists = FileManager.default.fileExists(atPath: self.outputURL.path)
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: self.outputURL.path)[.size] as? NSNumber)?.intValue ?? 0
                    appLog("[Recording] Writer finished with status: \(writer.status.rawValue), error: \(self.describe(writer.error) ?? "none"), fileExists: \(fileExists), fileSize: \(fileSize)")
                    if writer.status == .completed {
                        continuation.resume(returning: self.outputURL)
                    } else {
                        continuation.resume(throwing: RecordingError.writingFailed(
                            self.describe(writer.error) ?? "Unknown error"
                        ))
                    }
                }
            }
        }

        // Inspect the output file to verify audio tracks (off main thread)
        let fileURL = url
        DispatchQueue.global(qos: .utility).async {
            self.inspectOutputFile(fileURL)
        }
        return url
    }

    private func inspectOutputFile(_ url: URL) {
        let asset = AVAsset(url: url)
        let videoTracks = asset.tracks(withMediaType: .video)
        let audioTracks = asset.tracks(withMediaType: .audio)
        appLog("[Recording] Output file: \(videoTracks.count) video track(s), \(audioTracks.count) audio track(s)")

        for (i, track) in videoTracks.enumerated() {
            let duration = track.timeRange.duration.seconds
            appLog("[Recording]   Video track \(i): duration=\(String(format: "%.2f", duration))s")
        }

        for (i, track) in audioTracks.enumerated() {
            let duration = track.timeRange.duration.seconds
            let sampleCount = track.timeRange.duration.value
            if let first = track.formatDescriptions.first {
                let formatDesc = first as! CMFormatDescription
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
                appLog("[Recording]   Audio track \(i): duration=\(String(format: "%.2f", duration))s, sampleRate=\(asbd?.mSampleRate ?? 0), channels=\(asbd?.mChannelsPerFrame ?? 0), timeValue=\(sampleCount)")
            } else {
                appLog("[Recording]   Audio track \(i): duration=\(String(format: "%.2f", duration))s, format=unknown")
            }
        }
    }

    // MARK: - Camera Fill Timer

    private func startFillTimer() {
        guard fillTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: writingQueue)
        timer.schedule(deadline: .now() + 0.05, repeating: 1.0 / 24.0, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            self?.fillCameraFrame()
        }
        timer.resume()
        self.fillTimer = timer
        appLog("[Recording] Camera fill timer started (24fps)")
    }

    private func stopFillTimer() {
        fillTimer?.cancel()
        fillTimer = nil
    }

    /// When screen frames are infrequent (window capture), re-composite the last
    /// screen content with the current camera frame to keep the overlay smooth.
    private func fillCameraFrame() {
        guard let writer = assetWriter, writer.status == .writing else { return }
        guard hasStartedSession else { return }
        guard let videoInput, videoInput.isReadyForMoreMediaData else { return }
        guard let adaptor = pixelBufferAdaptor else { return }
        guard let screenPB = lastScreenPixelBuffer else { return }

        // Only fill when we have a camera
        cameraLock.lock()
        let hasCam = lastCameraBuffer != nil
        cameraLock.unlock()
        guard hasCam else { return }

        // Only fill if enough time has passed since the last written frame
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        guard lastWrittenTimestamp.isValid else { return }
        let elapsed = CMTimeSubtract(now, lastWrittenTimestamp).seconds
        guard elapsed >= 0.04 else { return }

        // Build fill frame: last screen content + current camera
        var outputImage = CIImage(cvPixelBuffer: screenPB)

        cameraLock.lock()
        let cameraBuffer = lastCameraBuffer
        cameraLock.unlock()

        if let cameraBuffer, let cameraImage = makeCameraOverlayImage(cameraBuffer: cameraBuffer) {
            outputImage = cameraImage.composited(over: outputImage)
        }

        guard let rendered = renderToPixelBuffer(outputImage) else { return }

        // Ensure monotonicity
        let fillTimestamp = CMTimeMaximum(
            now,
            CMTimeAdd(lastWrittenTimestamp, CMTime(value: 1, timescale: 600))
        )

        let ok = adaptor.append(rendered, withPresentationTime: fillTimestamp)
        if ok {
            lastWrittenTimestamp = fillTimestamp
        }
    }

    // MARK: - Camera Compositing

    private func renderFrame(screenBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard let screenPixelBuffer = CMSampleBufferGetImageBuffer(screenBuffer) else {
            return nil
        }

        var outputImage = CIImage(cvPixelBuffer: screenPixelBuffer)

        cameraLock.lock()
        let cameraBuffer = lastCameraBuffer
        cameraLock.unlock()

        if let cameraBuffer, let cameraImage = makeCameraOverlayImage(cameraBuffer: cameraBuffer) {
            outputImage = cameraImage.composited(over: outputImage)
        }

        return renderToPixelBuffer(outputImage)
    }

    private func makeCameraOverlayImage(cameraBuffer: CMSampleBuffer) -> CIImage? {
        guard let cameraPixelBuffer = CMSampleBufferGetImageBuffer(cameraBuffer) else {
            return nil
        }

        var cameraImage = CIImage(cvPixelBuffer: cameraPixelBuffer)
        let camWidth = cameraImage.extent.width
        let camHeight = cameraImage.extent.height
        let scale = cameraSize * 2 / min(camWidth, camHeight) // Retina
        cameraImage = cameraImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let circleSize = cameraSize * 2
        let center = CIVector(x: circleSize / 2, y: circleSize / 2)
        guard let circleGenerator = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": center,
            "inputRadius0": circleSize / 2 - 1,
            "inputRadius1": circleSize / 2,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.clear
        ]),
        let maskImage = circleGenerator.outputImage else {
            return nil
        }

        let mask = maskImage.cropped(to: CGRect(x: 0, y: 0, width: circleSize, height: circleSize))
        let padding: CGFloat = 40
        let offsetX = CGFloat(width) - circleSize - padding
        let offsetY = padding

        let centeredCropOriginX = max((cameraImage.extent.width - circleSize) / 2, 0)
        let centeredCropOriginY = max((cameraImage.extent.height - circleSize) / 2, 0)
        let centeredCrop = CGRect(
            x: centeredCropOriginX,
            y: centeredCropOriginY,
            width: circleSize,
            height: circleSize
        )

        let centeredCameraImage = cameraImage
            .cropped(to: centeredCrop)
            .transformed(by: CGAffineTransform(translationX: -centeredCropOriginX, y: -centeredCropOriginY))
            .cropped(to: CGRect(x: 0, y: 0, width: circleSize, height: circleSize))

        return centeredCameraImage
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: mask
            ])
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
    }

    private func renderToPixelBuffer(_ image: CIImage) -> CVPixelBuffer? {
        var outputBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &outputBuffer
        )

        guard let output = outputBuffer else { return nil }
        ciContext.render(image, to: output)
        return output
    }

    // MARK: - Microphone

    private func startMicrophone() {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard micStatus == .authorized else {
            appLog("[Recording] Mic capture skipped — permission status: \(micStatus.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")
            return
        }

        guard let micDevice = AVCaptureDevice.default(for: .audio) else {
            appLog("[Recording] Mic capture skipped — no audio device found")
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()

        guard let input = try? AVCaptureDeviceInput(device: micDevice),
              session.canAddInput(input) else {
            appLog("[Recording] Mic capture skipped — could not create device input")
            return
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        let delegate = MicDelegate { [weak self] buffer in
            self?.appendMicAudioBuffer(buffer)
        }
        output.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "com.mux.mic-capture"))

        guard session.canAddOutput(output) else {
            appLog("[Recording] Mic capture skipped — could not add audio output")
            return
        }
        session.addOutput(output)

        session.commitConfiguration()
        session.startRunning()
        appLog("[Recording] Mic capture started with device: \(micDevice.localizedName)")

        self.micSession = session
        self.micOutput = output
        self.micDelegate = delegate
    }

    private func describe(_ error: Error?) -> String? {
        guard let error else { return nil }
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
}

private class MicDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    let onBuffer: (CMSampleBuffer) -> Void

    init(onBuffer: @escaping (CMSampleBuffer) -> Void) {
        self.onBuffer = onBuffer
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onBuffer(sampleBuffer)
    }
}
