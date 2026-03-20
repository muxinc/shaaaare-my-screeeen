import SwiftUI

struct RecordingControlsView: View {
    @ObservedObject var appState: AppState
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 16) {
            // Elapsed time
            HStack(spacing: 6) {
                Circle()
                    .fill(MuxTheme.red)
                    .frame(width: 8, height: 8)
                    .opacity(pulsingOpacity)

                Text(formatTime(elapsed))
                    .font(MuxTheme.mono(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }

            Button(action: {
                Task { await appState.stopRecording() }
            }) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .padding(8)
                    .background(MuxTheme.red)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .onAppear {
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                elapsed += 1
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var pulsingOpacity: Double {
        let phase = Int(elapsed) % 2
        return phase == 0 ? 1.0 : 0.4
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Stop Control Window

class StopControlWindow {
    static let shared = StopControlWindow()
    var window: NSWindow?

    func show(appState: AppState) {
        let content = RecordingControlsView(appState: appState)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 50)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 50),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isMovableByWindowBackground = true

        // Position at top center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 110
            let y = screenFrame.maxY - 70
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        self.window = window
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}
