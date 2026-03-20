import SwiftUI
import ScreenCaptureKit
import AVFoundation
import AppKit

// MARK: - Window Grouping

private struct WindowGroup: Identifiable {
    let id: String
    let appName: String
    let appIcon: NSImage?
    var windows: [SCWindow]
}

// MARK: - Source Picker

struct SourcePickerView: View {
    @EnvironmentObject var appState: AppState
    @State private var windowSearch = ""

    private var filteredWindowGroups: [WindowGroup] {
        let windows: [SCWindow]
        if windowSearch.isEmpty {
            windows = appState.windows
        } else {
            windows = appState.windows.filter { window in
                let appName = window.owningApplication?.applicationName ?? ""
                let title = window.title ?? ""
                return appName.localizedCaseInsensitiveContains(windowSearch) ||
                       title.localizedCaseInsensitiveContains(windowSearch)
            }
        }

        var groupDict: [String: WindowGroup] = [:]
        for window in windows {
            let bundleID = window.owningApplication?.bundleIdentifier ?? "unknown"
            let appName = window.owningApplication?.applicationName ?? "Unknown"
            if groupDict[bundleID] != nil {
                groupDict[bundleID]!.windows.append(window)
            } else {
                let icon = appIcon(for: bundleID)
                groupDict[bundleID] = WindowGroup(
                    id: bundleID,
                    appName: appName,
                    appIcon: icon,
                    windows: [window]
                )
            }
        }

        return groupDict.values.sorted { $0.appName.localizedCompare($1.appName) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Record")
                    .font(MuxTheme.display(size: 28))
                Spacer()
                Button(action: { appState.screen = .settings }) {
                    Image(systemName: "gear")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(MuxTheme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(MuxTheme.backgroundSecondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Screen recording permission prompt
                    if appState.needsScreenRecordingPermission {
                        VStack(spacing: 12) {
                            Image(systemName: "rectangle.dashed.badge.record")
                                .font(.system(size: 28))
                                .foregroundColor(MuxTheme.orange)

                            Text("Screen Recording Permission Required")
                                .font(.system(size: 15, weight: .semibold))

                            Text("Grant screen access before recording so macOS doesn't interrupt the countdown with a system prompt.")
                                .font(.system(size: 13))
                                .foregroundColor(MuxTheme.textSecondary)
                                .multilineTextAlignment(.leading)

                            VStack(spacing: 8) {
                                Button(action: requestScreenRecordingPermission) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "hand.raised.fill")
                                        Text("Grant Screen Access")
                                    }
                                }
                                .buttonStyle(MuxPrimaryButtonStyle())

                                Button(action: {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "gear")
                                        Text("Open System Settings")
                                    }
                                }
                                .buttonStyle(MuxSecondaryButtonStyle())
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(MuxTheme.orange.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(MuxTheme.orange.opacity(0.15), lineWidth: 1)
                        )
                    }

                    // Displays
                    if !appState.displays.isEmpty {
                        SourceSection(title: "Displays") {
                            ForEach(appState.displays, id: \.displayID) { display in
                                SourceRow(
                                    title: "Display \(display.displayID)",
                                    subtitle: "\(Int(display.width)) x \(Int(display.height))",
                                    icon: "display",
                                    isSelected: appState.selectedDisplay?.displayID == display.displayID && appState.selectedWindow == nil
                                ) {
                                    appState.selectedDisplay = display
                                    appState.selectedWindow = nil
                                    SelectionHighlightWindow.shared.highlightDisplay(display)
                                }
                            }
                        }
                    }

                    // Windows
                    if !appState.windows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            MuxSectionHeader(title: "Windows")

                            // Search field
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(MuxTheme.textSecondary)
                                    .font(.system(size: 12))
                                TextField("Filter windows...", text: $windowSearch)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                if !windowSearch.isEmpty {
                                    Button(action: { windowSearch = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(MuxTheme.textSecondary)
                                            .font(.system(size: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(MuxTheme.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(MuxTheme.border, lineWidth: 1)
                            )

                            if filteredWindowGroups.isEmpty && !windowSearch.isEmpty {
                                Text("No windows matching \"\(windowSearch)\"")
                                    .font(.system(size: 13))
                                    .foregroundColor(MuxTheme.textSecondary)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(filteredWindowGroups) { group in
                                    VStack(alignment: .leading, spacing: 4) {
                                        // App group header
                                        HStack(spacing: 8) {
                                            if let icon = group.appIcon {
                                                Image(nsImage: icon)
                                                    .resizable()
                                                    .frame(width: 18, height: 18)
                                            } else {
                                                Image(systemName: "app.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(MuxTheme.textSecondary)
                                                    .frame(width: 18, height: 18)
                                            }
                                            Text(group.appName)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.primary)
                                            if group.windows.count > 1 {
                                                Text("\(group.windows.count)")
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(MuxTheme.textSecondary)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(MuxTheme.backgroundSecondary)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                            }
                                        }
                                        .padding(.top, 4)

                                        ForEach(group.windows, id: \.windowID) { window in
                                            WindowSourceRow(
                                                window: window,
                                                isSelected: appState.selectedWindow?.windowID == window.windowID
                                            ) {
                                                appState.selectedWindow = window
                                                appState.selectedDisplay = nil
                                                SelectionHighlightWindow.shared.highlightWindow(window)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Camera
                    SourceSection(title: "Camera") {
                        if appState.cameraAuthorizationStatus == .denied || appState.cameraAuthorizationStatus == .restricted {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Camera access is disabled for this app.")
                                    .font(.system(size: 13))
                                    .foregroundColor(MuxTheme.textSecondary)

                                Button(action: resetCameraPermission) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Reset Camera Permission (Relaunches)")
                                    }
                                }
                                .buttonStyle(MuxSecondaryButtonStyle())

                                Button(action: openCameraSettings) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "gear")
                                        Text("Open Camera Settings")
                                    }
                                }
                                .buttonStyle(MuxTextButtonStyle())
                            }
                            .padding(.vertical, 4)
                        } else {
                            if appState.cameraAuthorizationStatus == .notDetermined {
                                Text("No camera permission yet.")
                                    .font(.system(size: 13))
                                    .foregroundColor(MuxTheme.textSecondary)
                                    .padding(.top, 4)

                                Button(action: requestCameraAccess) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "camera.badge.ellipsis")
                                        Text("Grant Camera Access")
                                    }
                                }
                                .buttonStyle(MuxSecondaryButtonStyle())
                                .padding(.bottom, 4)
                            }

                            if appState.cameraAuthorizationStatus == .authorized &&
                                appState.cameras.isEmpty && appState.unavailableCameras.isEmpty {
                                Text("No cameras found")
                                    .font(.system(size: 13))
                                    .foregroundColor(MuxTheme.textSecondary)
                                    .padding(.vertical, 4)
                            } else if appState.cameraAuthorizationStatus == .authorized {
                                ForEach(appState.cameras, id: \.uniqueID) { camera in
                                    SourceRow(
                                        title: camera.localizedName,
                                        subtitle: nil,
                                        icon: "camera.fill",
                                        isSelected: appState.selectedCamera?.uniqueID == camera.uniqueID,
                                        isToggle: true
                                    ) {
                                        if appState.selectedCamera?.uniqueID == camera.uniqueID {
                                            appState.selectedCamera = nil
                                        } else {
                                            appState.selectedCamera = camera
                                        }
                                        appState.updateCameraPreview()
                                    }
                                }

                                ForEach(appState.unavailableCameras) { camera in
                                    DisabledSourceRow(
                                        title: camera.name,
                                        subtitle: camera.reason,
                                        icon: "camera.fill"
                                    )
                                }
                            }
                        }
                    }

                    // Audio
                    SourceSection(title: "Audio") {
                        Toggle("System Audio", isOn: $appState.captureSystemAudio)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 13))
                        Toggle("Microphone", isOn: $appState.captureMicrophone)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 13))
                        if appState.captureMicrophone && AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(MuxTheme.yellow)
                                    .font(.system(size: 11))
                                Text("Microphone access is denied — enable in System Settings")
                                    .font(.system(size: 11))
                                    .foregroundColor(MuxTheme.yellow)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            // Record button
            VStack(spacing: 0) {
                Divider()
                    .background(MuxTheme.border)

                Button(action: {
                    Task { await appState.startRecording() }
                }) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                        Text("Start Recording")
                    }
                }
                .buttonStyle(MuxPrimaryButtonStyle(isDestructive: true))
                .disabled(appState.selectedDisplay == nil && appState.selectedWindow == nil)
                .padding(24)
            }
        }
        .task {
            await appState.refreshSources()
        }
        .onAppear {
            appState.updateCameraPreview()
        }
        .onDisappear {
            SelectionHighlightWindow.shared.dismiss()
            // Only close camera preview if we're not going into recording
            if appState.screen != .recording && appState.screen != .countdown(3)
                && appState.screen != .countdown(2) && appState.screen != .countdown(1) {
                CameraOverlayWindow.shared.close()
            }
        }
    }

    private func appIcon(for bundleID: String) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    private func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundlePath]
        task.launch()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func requestScreenRecordingPermission() {
        Task {
            let granted = await PermissionManager.requestScreenRecordingPermission()
            await appState.refreshSources()
            if !granted {
                appState.error = "Screen recording permission is required before recording can start."
            }
        }
    }

    private func requestCameraAccess() {
        Task {
            let granted = await PermissionManager.requestCameraPermission()
            if !granted && AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                appState.error = "Camera access was denied. Use Reset Camera Permission to try again."
            }
            await appState.refreshSources()
        }
    }

    private func resetCameraPermission() {
        Task {
            do {
                try await PermissionManager.resetCameraPermission()
                relaunchApp()
            } catch {
                appState.error = "Failed to reset camera permission: \(error.localizedDescription)"
            }
        }
    }

    private func openCameraSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Window Row with Thumbnail

private struct WindowSourceRow: View {
    let window: SCWindow
    let isSelected: Bool
    let action: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Thumbnail
                ZStack {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        MuxTheme.backgroundSecondary
                    }
                }
                .frame(width: 72, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? MuxTheme.orange : MuxTheme.border,
                            lineWidth: isSelected ? 2 : 1
                        )
                )

                Text(window.title?.isEmpty == false ? window.title! : "Untitled")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Spacer()

                if isSelected {
                    Image(systemName: "largecircle.fill.circle")
                        .foregroundColor(MuxTheme.orange)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(MuxTheme.textSecondary.opacity(0.4))
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? MuxTheme.orange.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .task {
            guard thumbnail == nil else { return }
            do {
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.width = 144
                config.height = 92
                let cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config
                )
                thumbnail = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height)
                )
            } catch {
                // No thumbnail available for this window
            }
        }
    }
}

// MARK: - Shared Components

private struct SourceSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MuxSectionHeader(title: title)
            content()
        }
    }
}

private struct SourceRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let isSelected: Bool
    var isToggle: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? MuxTheme.orange : MuxTheme.textSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(MuxTheme.textSecondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: isToggle ? "checkmark.circle.fill" : "largecircle.fill.circle")
                        .foregroundColor(MuxTheme.orange)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(MuxTheme.textSecondary.opacity(0.4))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? MuxTheme.orange.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DisabledSourceRow: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(MuxTheme.textSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(MuxTheme.textSecondary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(MuxTheme.yellow)
            }

            Spacer()

            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(MuxTheme.yellow)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(MuxTheme.yellow.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(MuxTheme.yellow.opacity(0.15), lineWidth: 1)
        )
    }
}
