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
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var hasStartedSession = false
    private var sessionStartTime: CMTime?
    private let writingQueue = DispatchQueue(label: "com.mux.recording-session")
    private var frameCount = 0
    private var systemAudioBufferCount = 0
    private var micAudioBufferCount = 0
    private var writerFailed = false
    private var lastSystemAudioPTS: CMTime = .invalid
    private var lastMicAudioPTS: CMTime = .invalid

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
    private var lastRenderedFrame: CVPixelBuffer?
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

        // HEVC handles high resolutions (3600x2114+) without the macroblock-rate
        // limits that cause H.264 to fail with -12737 at >Level 5.1 rates.
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 4,
                AVVideoExpectedSourceFrameRateKey: 60
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
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
        )
        self.pixelBufferAdaptor = adaptor

        // Separate audio inputs for system audio (stereo) and mic (mono).
        // Sharing a single input caused two problems:
        //   1. Mono mic data fed into a stereo encoder → high-pitch playback
        //   2. Mic timestamps ran ahead of system audio → all system audio dropped
        if captureSystemAudio {
            self.systemAudioInput = Self.makeAudioInput(channels: 2, writer: writer)
        }
        if captureMicrophone {
            self.micAudioInput = Self.makeAudioInput(channels: 1, writer: writer)
        }

        appLog("[Recording] Writer configured: HEVC \(width)x\(height), bitrate=\(width * height * 4), systemAudio=\(captureSystemAudio), mic=\(captureMicrophone), output: \(outputURL.lastPathComponent)")

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

        let rawTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !hasStartedSession {
            // Start at the raw capture timestamp so we never need to retime
            // sample buffers. Retiming audio via CMSampleBufferCreateCopyWithNewTiming
            // with sampleTimingEntryCount:1 was producing malformed buffers that
            // crashed the encoder with -12737 (kCMSampleBufferError_ArrayTooSmall).
            writer.startSession(atSourceTime: rawTimestamp)
            sessionStartTime = rawTimestamp
            hasStartedSession = true
            appLog("[Recording] Session started at raw PTS: \(rawTimestamp.seconds)s")
        }

        guard sessionStartTime != nil else { return }

        frameCount += 1
        if frameCount <= 5 || frameCount % 60 == 0 {
            appLog("[Recording] Frame #\(frameCount) PTS=\(rawTimestamp.seconds)s, writer status: \(writer.status.rawValue)")
        }

        if frameCount <= 5 {
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
        var writeTimestamp = rawTimestamp
        if lastWrittenTimestamp.isValid && CMTimeCompare(writeTimestamp, lastWrittenTimestamp) <= 0 {
            writeTimestamp = CMTimeAdd(lastWrittenTimestamp, CMTime(value: 1, timescale: 600))
        }

        let ok = adaptor.append(renderedFrame, withPresentationTime: writeTimestamp)
        if ok {
            lastWrittenTimestamp = writeTimestamp
            lastRenderedFrame = renderedFrame
            if frameCount <= 5 {
                appLog("[Recording] Video frame #\(frameCount) appended OK, writerStatus=\(writer.status.rawValue)")
            }
        } else {
            appLog("[Recording] !! VIDEO APPEND FAILED frame #\(frameCount) PTS=\(writeTimestamp.seconds)s, writer status: \(writer.status.rawValue), error: \(describe(writer.error) ?? "none")")
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
            guard let self else { return }
            let isFirst = self.systemAudioBufferCount == 0
            if let newPTS = self._appendAudio(sampleBuffer, to: self.systemAudioInput, lastPTS: self.lastSystemAudioPTS, source: "system", isFirst: isFirst) {
                self.lastSystemAudioPTS = newPTS
                self.systemAudioBufferCount += 1
            }
        }
    }

    func appendMicAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        writingQueue.async { [weak self] in
            guard let self else { return }
            let isFirst = self.micAudioBufferCount == 0
            if let newPTS = self._appendAudio(sampleBuffer, to: self.micAudioInput, lastPTS: self.lastMicAudioPTS, source: "mic", isFirst: isFirst) {
                self.lastMicAudioPTS = newPTS
                self.micAudioBufferCount += 1
            }
        }
    }

    /// Shared audio append logic. Each source writes to its own AVAssetWriterInput
    /// with independent timestamp tracking. Returns the raw PTS on success.
    ///
    /// We append the original sample buffer without retiming. The session starts
    /// at the first video frame's raw PTS, so audio buffers are already in the
    /// correct time base. Previously we used CMSampleBufferCreateCopyWithNewTiming
    /// with sampleTimingEntryCount:1 which produced malformed multi-sample audio
    /// buffers and crashed the encoder with -12737.
    private func _appendAudio(
        _ sampleBuffer: CMSampleBuffer,
        to input: AVAssetWriterInput?,
        lastPTS: CMTime,
        source: String,
        isFirst: Bool
    ) -> CMTime? {
        guard let writer = assetWriter, writer.status == .writing else { return nil }
        guard let input, input.isReadyForMoreMediaData else { return nil }
        guard hasStartedSession, let startTime = sessionStartTime else { return nil }

        let rawPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)

        if isFirst {
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
                appLog("[Recording] \(source) audio format: formatID=\(asbd?.mFormatID ?? 0), flags=\(asbd?.mFormatFlags ?? 0), sampleRate=\(asbd?.mSampleRate ?? 0), channels=\(asbd?.mChannelsPerFrame ?? 0), bitsPerChannel=\(asbd?.mBitsPerChannel ?? 0), numSamples=\(numSamples)")
            }
        }

        // Drop audio that arrived before the video session started.
        if CMTimeCompare(rawPTS, startTime) < 0 {
            if isFirst {
                appLog("[Recording] Dropping pre-session \(source) audio: PTS=\(rawPTS.seconds)s < start=\(startTime.seconds)s")
            }
            return nil
        }

        if lastPTS.isValid && CMTimeCompare(rawPTS, lastPTS) <= 0 {
            return nil
        }

        // Append the original buffer directly — no retiming needed since the
        // session started at the raw capture timestamp.
        if input.append(sampleBuffer) {
            if isFirst || writer.status != .writing {
                appLog("[Recording] \(source) audio appended OK, writerStatus=\(writer.status.rawValue)")
            }
            return rawPTS
        } else {
            appLog("[Recording] !! AUDIO APPEND FAILED \(source) PTS=\(rawPTS.seconds)s numSamples=\(numSamples), writer status: \(writer.status.rawValue), error: \(describe(writer.error) ?? "none")")
        }
        return nil
    }

    func stop() async throws -> URL {
        appLog("[Recording] Stopping — \(frameCount) video frames, \(systemAudioBufferCount) system audio, \(micAudioBufferCount) mic audio")

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
                // Duplicate the last frame at the wall-clock stop time so the
                // video duration matches the actual recording length.
                if let lastFrame = self.lastRenderedFrame,
                   let adaptor = self.pixelBufferAdaptor,
                   let videoInput = self.videoInput, videoInput.isReadyForMoreMediaData {
                    // Raw timestamps are host-clock based, so CMClockGetHostTimeClock
                    // gives a directly comparable value.
                    let finalPTS = CMClockGetTime(CMClockGetHostTimeClock())
                    if self.lastWrittenTimestamp.isValid && CMTimeCompare(finalPTS, self.lastWrittenTimestamp) > 0 {
                        let ok = adaptor.append(lastFrame, withPresentationTime: finalPTS)
                        if ok {
                            appLog("[Recording] Appended final frame at \(finalPTS.seconds)s for correct duration")
                        }
                    }
                }

                self.videoInput?.markAsFinished()
                self.systemAudioInput?.markAsFinished()
                self.micAudioInput?.markAsFinished()

                writer.finishWriting {
                    let fileExists = FileManager.default.fileExists(atPath: self.outputURL.path)
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: self.outputURL.path)[.size] as? NSNumber)?.intValue ?? 0
                    appLog("[Recording] Writer finished with status: \(writer.status.rawValue), error: \(self.describe(writer.error) ?? "none"), fileExists: \(fileExists), fileSize: \(fileSize)")
                    if writer.status == .completed {
                        continuation.resume(returning: self.outputURL)
                    } else if fileExists && fileSize > 1024 {
                        // The file may still be usable even if finishWriting reports an error.
                        // Some encoder errors (-12737 etc.) leave a valid partial MOV.
                        appLog("[Recording] Writer did not complete cleanly but file exists (\(fileSize) bytes) — returning partial recording")
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

    // MARK: - Audio Input Factory

    private static func makeAudioInput(channels: Int, writer: AVAssetWriter) -> AVAssetWriterInput {
        var channelLayout = AudioChannelLayout(
            mChannelLayoutTag: channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo,
            mChannelBitmap: AudioChannelBitmap(rawValue: 0),
            mNumberChannelDescriptions: 0,
            mChannelDescriptions: AudioChannelDescription(
                mChannelLabel: kAudioChannelLabel_Unknown,
                mChannelFlags: AudioChannelFlags(rawValue: 0),
                mCoordinates: (0, 0, 0)
            )
        )
        let channelLayoutData = Data(
            bytes: &channelLayout,
            count: MemoryLayout<AudioChannelLayout>.size
        )

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels == 1 ? 64000 : 128000,
            AVChannelLayoutKey: channelLayoutData
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        return input
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

    private var fillFrameCount = 0

    /// When screen frames are infrequent (window capture), re-composite the last
    /// screen content with the current camera frame to keep the overlay smooth.
    private func fillCameraFrame() {
        guard let writer = assetWriter, writer.status == .writing else { return }
        guard hasStartedSession else { return }
        guard let videoInput, videoInput.isReadyForMoreMediaData else { return }
        guard let adaptor = pixelBufferAdaptor else { return }
        guard let screenPB = lastScreenPixelBuffer else { return }
        guard lastWrittenTimestamp.isValid else { return }

        // Only fill when we have a camera
        cameraLock.lock()
        let hasCam = lastCameraBuffer != nil
        cameraLock.unlock()
        guard hasCam else { return }

        // Advance from the last written timestamp by one frame interval.
        let frameInterval = CMTime(value: 1, timescale: 24)
        let fillTimestamp = CMTimeAdd(lastWrittenTimestamp, frameInterval)

        // Build fill frame: last screen content + current camera
        var outputImage = CIImage(cvPixelBuffer: screenPB)

        cameraLock.lock()
        let cameraBuffer = lastCameraBuffer
        cameraLock.unlock()

        if let cameraBuffer, let cameraImage = makeCameraOverlayImage(cameraBuffer: cameraBuffer) {
            outputImage = cameraImage.composited(over: outputImage)
        }

        guard let rendered = renderToPixelBuffer(outputImage) else { return }

        fillFrameCount += 1
        let ok = adaptor.append(rendered, withPresentationTime: fillTimestamp)
        if ok {
            lastWrittenTimestamp = fillTimestamp
            lastRenderedFrame = rendered
            if fillFrameCount <= 3 {
                appLog("[Recording] Fill frame #\(fillFrameCount) PTS=\(fillTimestamp.seconds)s")
            }
        } else {
            appLog("[Recording] !! FILL FRAME APPEND FAILED #\(fillFrameCount) PTS=\(fillTimestamp.seconds)s, writer status: \(writer.status.rawValue), error: \(describe(writer.error) ?? "none")")
        }
    }

    // MARK: - Camera Compositing

    private func renderFrame(screenBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard let screenPixelBuffer = CMSampleBufferGetImageBuffer(screenBuffer) else {
            return nil
        }

        cameraLock.lock()
        let cameraBuffer = lastCameraBuffer
        cameraLock.unlock()

        // Fast path: no camera → use the original SCK pixel buffer directly.
        // This avoids an unnecessary CIContext GPU copy and ensures the encoder
        // receives a pixel buffer with the exact properties SCK provides.
        guard let cameraBuffer, let cameraImage = makeCameraOverlayImage(cameraBuffer: cameraBuffer) else {
            return screenPixelBuffer
        }

        let outputImage = cameraImage.composited(over: CIImage(cvPixelBuffer: screenPixelBuffer))
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
        // Prefer the adaptor's pixel buffer pool for efficient, encoder-compatible buffers
        var outputBuffer: CVPixelBuffer?

        if let pool = pixelBufferAdaptor?.pixelBufferPool {
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
            if status != kCVReturnSuccess {
                appLog("[Recording] Pool buffer allocation failed (\(status)), falling back to manual")
                outputBuffer = nil
            }
        }

        if outputBuffer == nil {
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                width, height,
                kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
                &outputBuffer
            )
        }

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
