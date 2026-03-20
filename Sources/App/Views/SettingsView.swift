import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenId: String = ""
    @State private var tokenSecret: String = ""
    @State private var saved = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 36))
                    .foregroundColor(MuxTheme.orange)

                Text("Mux Credentials")
                    .font(MuxTheme.display(size: 24))

                Text("Enter your Mux API access token to enable uploads.")
                    .font(.system(size: 14))
                    .foregroundColor(MuxTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                if appState.hasCredentials {
                    Text("Credentials are already saved in Keychain. Enter new values to replace them.")
                        .font(.system(size: 12))
                        .foregroundColor(MuxTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("TOKEN ID")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundColor(MuxTheme.textSecondary)
                    TextField("Enter token ID", text: $tokenId)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(10)
                        .background(MuxTheme.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(MuxTheme.border, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("TOKEN SECRET")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundColor(MuxTheme.textSecondary)
                    SecureField("Enter token secret", text: $tokenSecret)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(10)
                        .background(MuxTheme.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(MuxTheme.border, lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Button(action: saveCredentials) {
                    HStack(spacing: 8) {
                        if saved {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Saved")
                        } else {
                            Text("Save Credentials")
                        }
                    }
                }
                .buttonStyle(MuxPrimaryButtonStyle())
                .disabled(tokenId.isEmpty || tokenSecret.isEmpty)
                .padding(.horizontal, 32)

                Button(appState.pendingReviewURL != nil ? "Back to Review" : "Back to Recording") {
                    if let url = appState.pendingReviewURL {
                        appState.pendingReviewURL = nil
                        appState.screen = .review(url)
                    } else {
                        appState.screen = .sourcePicker
                    }
                }
                .buttonStyle(MuxTextButtonStyle())
            }

            VStack(spacing: 8) {
                Toggle("Keep local recordings after upload", isOn: Binding(
                    get: { appState.preferencesStore.keepLocalRecordings },
                    set: { appState.preferencesStore.keepLocalRecordings = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }

    private func saveCredentials() {
        let success = appState.credentialStore.saveCredentials(
            tokenId: tokenId,
            tokenSecret: tokenSecret
        )
        if success {
            appState.hasCredentials = true
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                saved = false
                if let url = appState.pendingReviewURL {
                    appState.pendingReviewURL = nil
                    appState.screen = .review(url)
                } else {
                    appState.screen = .sourcePicker
                }
            }
        } else {
            appState.error = "Failed to save credentials to Keychain"
        }
    }
}
