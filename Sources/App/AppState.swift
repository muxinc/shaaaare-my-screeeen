import SwiftUI
import ScreenCaptureKit
import AVFoundation
import Darwin

enum AppScreen: Equatable {
    case permissions
    case settings
    case sourcePicker
    case countdown(Int)
    case recording
    case review(URL)
    case uploading(Double)
    case done(String)
    case library

    static func == (lhs: AppScreen, rhs: AppScreen) -> Bool {
        switch (lhs, rhs) {
        case (.permissions, .permissions): return true
        case (.settings, .settings): return true
        case (.sourcePicker, .sourcePicker): return true
        case (.countdown(let a), .countdown(let b)): return a == b
        case (.recording, .recording): return true
        case (.review(let a), .review(let b)): return a == b
        case (.uploading(let a), .uploading(let b)): return a == b
        case (.done(let a), .done(let b)): return a == b
        case (.library, .library): return true
        default: return false
        }
    }
}

struct UnavailableCamera: Identifiable, Equatable {
    let id: String
    let name: String
    let reason: String
}

@MainActor
class AppState: ObservableObject {
    static let systemBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.SystemUIServer",
        "com.apple.screencaptureui",
    ]

    @Published var screen: AppScreen = .permissions
    @Published var displays: [SCDisplay] = []
    @Published var windows: [SCWindow] = []
    @Published var cameras: [AVCaptureDevice] = []
    @Published var unavailableCameras: [UnavailableCamera] = []
    @Published var cameraAuthorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published var selectedDisplay: SCDisplay?
    @Published var selectedWindow: SCWindow?
    @Published var selectedCamera: AVCaptureDevice?
    @Published var captureSystemAudio: Bool = true
    @Published var captureMicrophone: Bool = true
    @Published var hasCredentials: Bool = false
    @Published var error: String?
    @Published var needsScreenRecordingPermission: Bool = false
    @Published var pendingReviewURL: URL?
    var mainWindow: NSWindow?
    let screenRecorder = ScreenRecorder()
    let credentialStore = CredentialStore()
    let preferencesStore = PreferencesStore()
    let historyStore = RecordingHistoryStore()

    init() {
        if ProcessInfo.processInfo.arguments.contains("--probe-camera-auth") {
            print(AVCaptureDevice.authorizationStatus(for: .video).rawValue)
            fflush(stdout)
            Darwin.exit(0)
        }

        hasCredentials = credentialStore.hasCredentials()

        // Start on the permissions screen so camera/mic access can be requested
        // and current TCC state is visible before source selection.
        screen = .permissions
    }

    func refreshSources() async {
        // Enumerate cameras (independent of screen recording permission)
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        let discoveredCameras = discovery.devices
        cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch cameraAuthorizationStatus {
        case .authorized:
            var availableCameras: [AVCaptureDevice] = []
            var rejectedCameras: [UnavailableCamera] = []

            for camera in discoveredCameras {
                do {
                    let _ = try AVCaptureDeviceInput(device: camera)
                    availableCameras.append(camera)
                } catch {
                    let reason = error.localizedDescription
                    appLog("[Sources] Rejecting camera \(camera.localizedName): \(reason)")
                    rejectedCameras.append(
                        UnavailableCamera(
                            id: camera.uniqueID,
                            name: camera.localizedName,
                            reason: reason
                        )
                    )
                }
            }

            cameras = availableCameras
            unavailableCameras = rejectedCameras
        case .denied, .restricted:
            cameras = []
            unavailableCameras = []
        case .notDetermined:
            cameras = []
            unavailableCameras = []
        @unknown default:
            cameras = []
            unavailableCameras = []
        }

        appLog("[Sources] Found \(discoveredCameras.count) camera(s): \(discoveredCameras.map { $0.localizedName })")

        if let selectedCamera, !cameras.contains(where: { $0.uniqueID == selectedCamera.uniqueID }) {
            let rejectedCamera = unavailableCameras.first { $0.id == selectedCamera.uniqueID }
            self.selectedCamera = nil
            CameraOverlayWindow.shared.close()

            if let rejectedCamera {
                error = "Cannot use \(rejectedCamera.name): \(rejectedCamera.reason)"
            }
        }

        // Enumerate displays/windows — try SCShareableContent directly rather
        // than guarding on CGPreflight, because on macOS 15+ the two permission
        // systems are separate.
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            displays = content.displays

            let ownBundleID = Bundle.main.bundleIdentifier
            windows = content.windows.filter { window in
                guard window.isOnScreen,
                      window.frame.width > 100,
                      window.frame.height > 100 else { return false }

                // Filter out windows with no owning application
                guard let bundleID = window.owningApplication?.bundleIdentifier else { return false }

                // Filter out our own windows
                if bundleID == ownBundleID { return false }

                // Filter out system UI windows
                if Self.systemBundleIDs.contains(bundleID) { return false }

                return true
            }
            needsScreenRecordingPermission = false

            if selectedDisplay == nil, let first = displays.first {
                selectedDisplay = first
            }
        } catch {
            appLog("[Sources] Screen capture permission error: \(error.localizedDescription)")
            needsScreenRecordingPermission = true
            displays = []
            windows = []
        }
    }

    func updateCameraPreview() {
        if selectedCamera != nil && screen == .sourcePicker {
            CameraOverlayWindow.shared.show(appState: self)
        } else if selectedCamera == nil {
            CameraOverlayWindow.shared.close()
        }
    }

    func startRecording() async {
        let hasScreenPermission = await PermissionManager.checkScreenRecordingPermission()
        if !hasScreenPermission {
            let granted = await PermissionManager.requestScreenRecordingPermission()
            if !granted {
                error = "Screen recording permission is required before recording can start"
                screen = .permissions
                return
            }
            await refreshSources()
        }

        do {
            try await screenRecorder.prepareCapture(
                display: selectedDisplay,
                window: selectedWindow,
                captureSystemAudio: captureSystemAudio
            )
        } catch {
            self.error = "Failed to prepare capture: \(error.localizedDescription)"
            screen = .sourcePicker
            return
        }

        SelectionHighlightWindow.shared.dismiss()

        screen = .countdown(3)
        try? await Task.sleep(for: .seconds(1))
        screen = .countdown(2)
        try? await Task.sleep(for: .seconds(1))
        screen = .countdown(1)
        try? await Task.sleep(for: .seconds(1))

        do {
            let outputURL = recordingOutputURL()
            try await screenRecorder.startRecording(
                display: selectedDisplay,
                window: selectedWindow,
                camera: selectedCamera,
                captureSystemAudio: captureSystemAudio,
                captureMicrophone: captureMicrophone,
                outputURL: outputURL
            )
            screen = .recording

            // Store reference to main window before hiding it
            if let window = NSApplication.shared.mainWindow {
                self.mainWindow = window
                window.orderOut(nil)
            }

            StopControlWindow.shared.show(appState: self)
            // Camera overlay is already showing from preview if camera is selected
        } catch {
            self.error = "Failed to start recording: \(error.localizedDescription)"
            screen = .sourcePicker
        }
    }

    func stopRecording() async {
        do {
            let fileURL = try await screenRecorder.stopRecording()
            StopControlWindow.shared.close()
            CameraOverlayWindow.shared.close()

            screen = .review(fileURL)

            // Show the main window after setting the screen so it renders the review
            if let window = mainWindow {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                self.mainWindow = nil
            }
        } catch {
            self.error = "Failed to stop recording: \(error.localizedDescription)"
            StopControlWindow.shared.close()
            CameraOverlayWindow.shared.close()

            screen = .sourcePicker

            if let window = mainWindow {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                self.mainWindow = nil
            }
        }
    }

    func retake(fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
        screen = .sourcePicker
    }

    func upload(fileURL: URL) async {
        guard let (tokenId, tokenSecret) = credentialStore.getCredentials() else {
            error = "No Mux credentials found — enter your credentials, then try again"
            pendingReviewURL = fileURL
            screen = .settings
            return
        }

        let api = MuxAPI(tokenId: tokenId, tokenSecret: tokenSecret)
        screen = .uploading(0.0)

        do {
            let directUpload = try await api.createDirectUpload()

            guard let uploadURL = URL(string: directUpload.url) else {
                throw MuxAPIError.requestFailed(statusCode: 0, body: "Invalid upload URL returned by Mux")
            }

            try await api.uploadFile(fileURL, to: uploadURL) { [weak self] progress in
                Task { @MainActor in
                    self?.screen = .uploading(progress * 0.5)
                }
            }

            screen = .uploading(0.5)

            var assetId: String?
            for _ in 0..<60 {
                try await Task.sleep(for: .seconds(2))
                let status = try await api.getUpload(id: directUpload.id)
                if status.status == "asset_created", let id = status.assetId {
                    assetId = id
                    break
                }
            }

            guard let assetId else {
                error = "Timed out waiting for asset creation"
                screen = .sourcePicker
                return
            }

            screen = .uploading(0.7)

            var playbackId: String?
            for _ in 0..<90 {
                try await Task.sleep(for: .seconds(2))
                let asset = try await api.getAsset(id: assetId)
                if asset.status == "ready", let id = asset.playbackIds?.first?.id {
                    playbackId = id
                    break
                }
                screen = .uploading(min(0.95, 0.7 + Double(Int.random(in: 0..<10)) * 0.01))
            }

            guard let playbackId else {
                error = "Timed out waiting for asset to be ready"
                screen = .sourcePicker
                return
            }

            if !preferencesStore.keepLocalRecordings {
                try? FileManager.default.removeItem(at: fileURL)
            }

            let playbackURL = "https://player.mux.com/\(playbackId)"
            historyStore.append(RecordingEntry(
                assetId: assetId,
                playbackId: playbackId,
                playbackURL: playbackURL
            ))

            screen = .done(playbackURL)
        } catch {
            self.error = "Upload failed: \(error.localizedDescription)"
            screen = .review(fileURL)
        }
    }

    private func recordingOutputURL() -> URL {
        let dir = preferencesStore.recordingsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "Recording-\(formatter.string(from: Date())).mov"
        return dir.appendingPathComponent(filename)
    }
}
