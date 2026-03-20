import AVFoundation
import CoreMedia

class CameraCapture: NSObject {
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let outputQueue = DispatchQueue(label: "com.mux.camera-capture")
    private let onFrame: (CMSampleBuffer) -> Void
    let device: AVCaptureDevice

    init(device: AVCaptureDevice, onFrame: @escaping (CMSampleBuffer) -> Void) {
        self.device = device
        self.onFrame = onFrame
        super.init()
    }

    func start() throws {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw CameraCaptureError.cannotAddInput
        }
        captureSession.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        guard captureSession.canAddOutput(videoOutput) else {
            throw CameraCaptureError.cannotAddOutput
        }
        captureSession.addOutput(videoOutput)

        captureSession.commitConfiguration()
        captureSession.startRunning()
    }

    func stop() {
        captureSession.stopRunning()
    }

    var session: AVCaptureSession { captureSession }
}

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame(sampleBuffer)
    }
}

enum CameraCaptureError: LocalizedError {
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .cannotAddInput: return "Cannot add camera input"
        case .cannotAddOutput: return "Cannot add camera output"
        }
    }
}
