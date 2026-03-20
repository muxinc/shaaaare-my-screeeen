import SwiftUI

@main
struct ShaaaareMyScreeenApp: App {
    @StateObject private var appState = AppState()

    init() {
        AppLogger.shared.bootstrap()
        MuxTheme.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 420, minHeight: 500)
                .tint(MuxTheme.orange)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
