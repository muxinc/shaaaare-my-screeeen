import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            MuxTheme.backgroundPrimary
                .ignoresSafeArea()

            VStack {
                switch appState.screen {
                case .permissions:
                    PermissionsView()
                case .settings:
                    SettingsView()
                case .sourcePicker:
                    SourcePickerView()
                case .countdown(let count):
                    CountdownView(count: count)
                case .recording:
                    // Main window is hidden during recording
                    EmptyView()
                case .review(let url):
                    ReviewView(fileURL: url)
                case .uploading(let progress):
                    UploadProgressView(progress: progress)
                case .done(let url):
                    DoneView(playbackURL: url)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appState.screen)

            if let error = appState.error {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(MuxTheme.yellow)
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Button("Dismiss") {
                            appState.error = nil
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(14)
                    .background(MuxTheme.red.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(16)
                }
                .transition(.move(edge: .bottom))
            }
        }
    }
}
