import AppKit
@preconcurrency import AVFoundation

// MARK: - Camera Preview NSView

class CameraPreviewView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession, size: CGFloat) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true

        layer?.cornerRadius = size / 2
        layer?.masksToBounds = true
        layer?.borderWidth = 3
        layer?.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor

        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = bounds
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }

    /// Disconnect the preview layer from the Core Animation render tree
    func disconnectPreviewLayer() {
        previewLayer.session = nil
        previewLayer.removeFromSuperlayer()
    }
}

// MARK: - Camera Overlay Window

class CameraOverlayWindow {
    static let shared = CameraOverlayWindow()
    var window: NSWindow?
    private var previewSession: AVCaptureSession?
    private let size: CGFloat = 180
    private let sessionQueue = DispatchQueue(label: "com.mux.camera-preview")

    @MainActor func show(appState: AppState) {
        // Close existing preview first
        close()

        guard let camera = appState.selectedCamera else {
            appLog("[CameraOverlay] No camera selected")
            return
        }

        appLog("[CameraOverlay] Setting up camera: \(camera.localizedName)")

        let session = AVCaptureSession()

        // Configure and start session on background queue
        sessionQueue.async {
            session.beginConfiguration()
            session.sessionPreset = .medium

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                guard session.canAddInput(input) else {
                    appLog("[CameraOverlay] Cannot add camera input to session")
                    return
                }
                session.addInput(input)
            } catch {
                let message = error.localizedDescription
                appLog("[CameraOverlay] Camera input error: \(message)")
                DispatchQueue.main.async {
                    if appState.selectedCamera?.uniqueID == camera.uniqueID {
                        appState.selectedCamera = nil
                    }
                    appState.error = "Cannot use \(camera.localizedName): \(message)"
                }
                return
            }

            session.commitConfiguration()
            appLog("[CameraOverlay] Starting capture session...")
            session.startRunning()
            appLog("[CameraOverlay] Session running: \(session.isRunning)")

            // Create window on main thread after session is running
            DispatchQueue.main.async {
                CameraOverlayWindow.shared.createWindow(session: session)
            }
        }

        self.previewSession = session
    }

    @MainActor private func createWindow(session: AVCaptureSession) {
        let previewView = CameraPreviewView(session: session, size: size)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.contentView = previewView
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.hasShadow = true
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Position in bottom-right corner
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - size - 20
            let y = screenFrame.minY + 20
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }

        win.orderFrontRegardless()
        self.window = win
        appLog("[CameraOverlay] Window shown")
    }

    func close() {
        // 1. Disconnect the preview layer from Core Animation FIRST
        //    This prevents CA from trying to render frames from a stopped session
        if let previewView = window?.contentView as? CameraPreviewView {
            previewView.disconnectPreviewLayer()
        }

        // 2. Hide the window (don't deallocate — isReleasedWhenClosed = false)
        window?.orderOut(nil)
        window = nil

        // 3. Stop session on background queue AFTER layer is disconnected
        let session = previewSession
        previewSession = nil
        if let session {
            sessionQueue.async {
                session.stopRunning()
            }
        }
    }
}
