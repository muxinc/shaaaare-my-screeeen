import SwiftUI
import Sparkle

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController!
    let appState = AppState()
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(
            appState: appState,
            updater: updaterController.updater
        )
        menuBarController.showPanel()
    }
}

@main
struct ShaaaareMyScreeenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AppLogger.shared.bootstrap()
        MuxTheme.registerFonts()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
