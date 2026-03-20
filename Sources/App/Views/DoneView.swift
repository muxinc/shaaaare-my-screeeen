import SwiftUI

struct DoneView: View {
    @EnvironmentObject var appState: AppState
    let playbackURL: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(MuxTheme.green)

            VStack(spacing: 8) {
                Text("Upload Complete")
                    .font(MuxTheme.display(size: 28))

                Text("Your recording is ready to share.")
                    .font(.system(size: 14))
                    .foregroundColor(MuxTheme.textSecondary)
            }

            // Playback URL
            VStack(spacing: 8) {
                Text("PLAYBACK URL")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(MuxTheme.textSecondary)

                HStack {
                    Text(playbackURL)
                        .font(MuxTheme.mono(size: 12))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .foregroundColor(.primary)

                    Button(action: copyURL) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundColor(copied ? MuxTheme.green : MuxTheme.orange)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(MuxTheme.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(MuxTheme.border, lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: {
                appState.screen = .sourcePicker
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                    Text("Record Another")
                }
            }
            .buttonStyle(MuxPrimaryButtonStyle())
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .padding()
    }

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(playbackURL, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}
