import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController!
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(appState: appState)
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
