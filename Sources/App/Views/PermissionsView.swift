import SwiftUI
import AVFoundation
import ScreenCaptureKit

struct PermissionsView: View {
    @EnvironmentObject var appState: AppState
    @State private var cameraGranted = false
    @State private var micGranted = false
    @State private var screenGranted = false
    @State private var cameraDenied = false
    @State private var micDenied = false
    @State private var checking = true

    // Only screen recording is truly required
    var canProceed: Bool {
        screenGranted
    }

    var allGranted: Bool {
        cameraGranted && micGranted && screenGranted
    }

    var hasDenied: Bool {
        cameraDenied || micDenied
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 44))
                    .foregroundColor(MuxTheme.orange)

                Text("Permissions")
                    .font(MuxTheme.display(size: 32))

                Text("Click each row to request only the permissions you want before you start recording.")
                    .font(.system(size: 14))
                    .foregroundColor(MuxTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
                .frame(height: 28)

            VStack(spacing: 10) {
                Button(action: requestScreenRecordingPermission) {
                    PermissionRow(
                        title: "Screen Recording",
                        subtitle: screenGranted ? "Record your display or window" : "Click to request access",
                        icon: "rectangle.dashed.badge.record",
                        granted: screenGranted,
                        actionLabel: screenGranted ? "Granted" : "Request"
                    )
                }
                .buttonStyle(.plain)
                .disabled(screenGranted)

                Button(action: handleCameraRowTap) {
                    PermissionRow(
                        title: "Camera",
                        subtitle: cameraDenied ? "Denied — click to reset and relaunch" : cameraGranted ? "Webcam overlay in recordings" : "Click to request access",
                        icon: "camera.fill",
                        granted: cameraGranted,
                        denied: cameraDenied,
                        actionLabel: cameraGranted ? "Granted" : cameraDenied ? "Reset" : "Request"
                    )
                }
                .buttonStyle(.plain)

                Button(action: handleMicrophoneRowTap) {
                    PermissionRow(
                        title: "Microphone",
                        subtitle: micDenied ? "Denied — click to reset and relaunch" : micGranted ? "Audio narration" : "Click to request access",
                        icon: "mic.fill",
                        granted: micGranted,
                        denied: micDenied,
                        actionLabel: micGranted ? "Granted" : micDenied ? "Reset" : "Request"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                if canProceed {
                    Button(action: {
                        appState.screen = .sourcePicker
                    }) {
                        Text("Get Started")
                    }
                    .buttonStyle(MuxPrimaryButtonStyle())
                    .padding(.horizontal, 24)

                    if cameraDenied {
                        Button(action: {
                            Task { await resetCameraPermission() }
                        }) {
                            Text("Reset Camera Permission (Relaunches)")
                        }
                        .buttonStyle(MuxSecondaryButtonStyle())
                        .padding(.horizontal, 24)
                    }

                    if micDenied {
                        Button(action: {
                            Task { await resetMicrophonePermission() }
                        }) {
                            Text("Reset Microphone Permission (Relaunches)")
                        }
                        .buttonStyle(MuxSecondaryButtonStyle())
                        .padding(.horizontal, 24)
                    }

                    if hasDenied {
                        Button(action: openPrivacySettings) {
                            HStack(spacing: 4) {
                                Image(systemName: "gear")
                                Text("Fix in System Settings")
                            }
                        }
                        .buttonStyle(MuxTextButtonStyle())
                    }
                } else if !checking {
                    if cameraDenied {
                        Button(action: {
                            Task { await resetCameraPermission() }
                        }) {
                            Text("Reset Camera Permission (Relaunches)")
                        }
                        .buttonStyle(MuxSecondaryButtonStyle())
                        .padding(.horizontal, 24)
                    }

                    if micDenied {
                        Button(action: {
                            Task { await resetMicrophonePermission() }
                        }) {
                            Text("Reset Microphone Permission (Relaunches)")
                        }
                        .buttonStyle(MuxSecondaryButtonStyle())
                        .padding(.horizontal, 24)
                    }

                    if hasDenied {
                        Button(action: openPrivacySettings) {
                            HStack(spacing: 4) {
                                Image(systemName: "gear")
                                Text("Open System Settings")
                            }
                        }
                        .buttonStyle(MuxTextButtonStyle())

                        Button("Re-check Permissions") {
                            Task { await checkCurrentPermissions() }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(MuxTheme.textSecondary)
                        .font(.system(size: 13))
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .task {
            await checkCurrentPermissions()
            checking = false
        }
    }

    private func checkCurrentPermissions() async {
        cameraGranted = false
        micGranted = false
        cameraDenied = false
        micDenied = false

        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        appLog("[Permissions] Camera authorizationStatus: \(camStatus.rawValue)")
        if camStatus == .authorized {
            cameraGranted = true
        } else if camStatus == .notDetermined {
            cameraGranted = false
        } else {
            cameraGranted = false
            cameraDenied = true
        }

        // Microphone: rely on TCC status only so the row stays request-driven.
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        appLog("[Permissions] Mic authorizationStatus: \(micStatus.rawValue)")
        if micStatus == .authorized {
            micGranted = true
        } else if micStatus == .notDetermined {
            micGranted = false
        } else {
            micGranted = false
            micDenied = true
        }

        // Check screen recording via SCShareableContent (reliable on Sequoia)
        screenGranted = await PermissionManager.checkScreenRecordingPermission()
        appLog("[Permissions] Screen recording check: \(screenGranted)")
    }

    private func requestScreenRecordingPermission() {
        Task {
            screenGranted = await PermissionManager.requestScreenRecordingPermission()
            await checkCurrentPermissions()
        }
    }

    private func handleCameraRowTap() {
        if cameraGranted {
            return
        }

        if cameraDenied {
            Task { await resetCameraPermission() }
            return
        }

        Task {
            cameraGranted = await PermissionManager.requestCameraPermission()
            await checkCurrentPermissions()
        }
    }

    private func handleMicrophoneRowTap() {
        if micGranted {
            return
        }

        if micDenied {
            Task { await resetMicrophonePermission() }
            return
        }

        Task {
            micGranted = await PermissionManager.requestMicrophonePermission()
            await checkCurrentPermissions()
        }
    }

    private func resetCameraPermission() async {
        do {
            try await PermissionManager.resetCameraPermission()
            relaunchApp()
        } catch {
            appState.error = "Failed to reset camera permission: \(error.localizedDescription)"
        }
    }

    private func resetMicrophonePermission() async {
        do {
            try await PermissionManager.resetMicrophonePermission()
            relaunchApp()
        } catch {
            appState.error = "Failed to reset microphone permission: \(error.localizedDescription)"
        }
    }

    private func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundlePath]
        try? task.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func openPrivacySettings() {
        if cameraDenied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            }
        } else if micDenied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let granted: Bool
    var denied: Bool = false
    var actionLabel: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(denied ? MuxTheme.yellow : MuxTheme.textSecondary)
            }

            Spacer()

            if let actionLabel {
                Text(actionLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(granted ? MuxTheme.green : denied ? MuxTheme.yellow : MuxTheme.orange)
            }

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(MuxTheme.green)
                    .font(.system(size: 18))
            } else if denied {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(MuxTheme.yellow)
                    .font(.system(size: 18))
            } else {
                Image(systemName: "chevron.right")
                    .foregroundColor(MuxTheme.textSecondary.opacity(0.6))
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(granted ? MuxTheme.green.opacity(0.2) : denied ? MuxTheme.yellow.opacity(0.2) : MuxTheme.border, lineWidth: 1)
        )
    }

    private var iconColor: Color {
        granted ? MuxTheme.green : denied ? MuxTheme.yellow : MuxTheme.orange
    }

    private var iconBackground: Color {
        granted ? MuxTheme.green.opacity(0.12) : denied ? MuxTheme.yellow.opacity(0.12) : MuxTheme.orange.opacity(0.12)
    }

    private var rowBackground: Color {
        granted ? MuxTheme.green.opacity(0.04) : denied ? MuxTheme.yellow.opacity(0.04) : MuxTheme.backgroundCard
    }
}
