import AVFoundation
import ScreenCaptureKit
import Foundation
import CoreGraphics

struct PermissionManager {
    private static let screenPermissionRequestedKey = "ScreenPermissionRequestedFromUI"

    /// Synchronous quick-check using the legacy CGWindowList API.
    /// On macOS 15+, this may return false even when ScreenCaptureKit
    /// permission is granted. Use `checkScreenRecordingPermission()` for
    /// a reliable async check.
    static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func clearScreenPermissionRequestState() {
        UserDefaults.standard.removeObject(forKey: screenPermissionRequestedKey)
    }

    /// Reliable async check: tries SCShareableContent which reflects the
    /// actual ScreenCaptureKit permission state on macOS 15+.
    static func checkScreenRecordingPermission() async -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }

        // Avoid triggering the Sequoia prompt on first launch. Only probe
        // ScreenCaptureKit directly after the user explicitly clicked the row.
        guard UserDefaults.standard.bool(forKey: screenPermissionRequestedKey) else {
            return false
        }

        // On Sequoia, CGPreflight may be false while ScreenCaptureKit works.
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let granted = !content.displays.isEmpty
            appLog("[Permissions] Screen recording check via SCShareableContent: \(granted)")
            return granted
        } catch {
            appLog("[Permissions] Screen recording check failed: \(error.localizedDescription)")
            return false
        }
    }

    static func requestScreenRecordingPermission() async -> Bool {
        UserDefaults.standard.set(true, forKey: screenPermissionRequestedKey)

        if CGPreflightScreenCaptureAccess() { return true }

        // On macOS 15+, calling SCShareableContent triggers the
        // ScreenCaptureKit permission dialog. Fall back to the legacy
        // CGRequestScreenCaptureAccess which opens System Settings.
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if !content.displays.isEmpty {
                appLog("[Permissions] Screen recording granted via SCShareableContent")
                return true
            }
        } catch {
            appLog("[Permissions] SCShareableContent request failed: \(error.localizedDescription)")
        }

        // Legacy fallback — opens System Settings on pre-Sequoia
        let granted = CGRequestScreenCaptureAccess()
        appLog("[Permissions] Screen recording granted (legacy): \(granted)")
        return granted
    }

    static func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        appLog("[Permissions] Request camera permission with status: \(status.rawValue)")
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    static func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        appLog("[Permissions] Request microphone permission with status: \(status.rawValue)")
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    static func resetCameraPermission() async throws {
        try await resetPermission(service: "Camera")
    }

    static func resetMicrophonePermission() async throws {
        try await resetPermission(service: "Microphone")
    }

    private static func resetPermission(service: String) async throws {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            throw PermissionResetError.missingBundleIdentifier
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw PermissionResetError.resetFailed(service: service, status: process.terminationStatus)
        }

        appLog("[Permissions] Reset \(service) permission for \(bundleID)")
    }
}

enum PermissionResetError: LocalizedError {
    case missingBundleIdentifier
    case resetFailed(service: String, status: Int32)

    var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier:
            return "Missing bundle identifier for permission reset"
        case .resetFailed(let service, let status):
            return "Failed to reset \(service.lowercased()) permission (exit status \(status))"
        }
    }
}
