import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenId: String = ""
    @State private var tokenSecret: String = ""
    @State private var saved = false
    @State private var mcpInstalled = MCPSetup.isConfigured
    @State private var mcpActionResult: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    if let url = appState.pendingReviewURL {
                        appState.pendingReviewURL = nil
                        appState.screen = .review(url)
                    } else {
                        appState.screen = .sourcePicker
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text(appState.pendingReviewURL != nil ? "Review" : "Back")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(MuxTheme.orange)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(MuxTheme.display(size: 22))

                Spacer()

                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

        ScrollView {
        VStack(spacing: 24) {
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

            VStack(spacing: 8) {
                Toggle("Keep local recordings after upload", isOn: Binding(
                    get: { appState.preferencesStore.keepLocalRecordings },
                    set: { appState.preferencesStore.keepLocalRecordings = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
            }
            .padding(.horizontal, 32)

            // MCP Integration
            VStack(spacing: 8) {
                Divider()
                    .padding(.vertical, 4)

                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 14))
                        .foregroundColor(MuxTheme.orange)
                    Text("CLAUDE CODE MCP")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundColor(MuxTheme.textSecondary)
                    Spacer()
                }

                Text("Let Claude access your recording library via MCP.")
                    .font(.system(size: 12))
                    .foregroundColor(MuxTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    if mcpInstalled {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(MuxTheme.green)
                                .font(.system(size: 12))
                            Text("Connected")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MuxTheme.green)
                        }

                        Spacer()

                        Button("Remove") {
                            let result = MCPSetup.uninstall()
                            switch result {
                            case .success:
                                mcpInstalled = false
                                mcpActionResult = nil
                            case .failure(let error):
                                mcpActionResult = error.localizedDescription
                            }
                        }
                        .buttonStyle(MuxTextButtonStyle())
                    } else {
                        Button("Set Up MCP Server") {
                            let result = MCPSetup.install()
                            switch result {
                            case .success:
                                mcpInstalled = true
                                mcpActionResult = nil
                            case .failure(let error):
                                mcpActionResult = error.localizedDescription
                            }
                        }
                        .buttonStyle(MuxSecondaryButtonStyle())

                        Spacer()
                    }
                }

                if let mcpActionResult {
                    Text(mcpActionResult)
                        .font(.system(size: 11))
                        .foregroundColor(MuxTheme.red)
                }
            }
            .padding(.horizontal, 32)
        }
        .padding(.vertical, 24)
        .padding(.horizontal)
        }
        }
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
