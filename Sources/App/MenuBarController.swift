import SwiftUI
import AppKit

@MainActor
class MenuBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init()
        setupStatusItem()
        setupPanel()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Shaaaare My Screeeen")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        let menu = NSMenu()

        let newRecording = NSMenuItem(title: "New Recording", action: #selector(newRecording), keyEquivalent: "n")
        newRecording.target = self

        let library = NSMenuItem(title: "Library", action: #selector(openLibrary), keyEquivalent: "l")
        library.target = self

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self

        menu.addItem(newRecording)
        menu.addItem(library)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(settings)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Shaaaare My Screeeen", action: #selector(quitApp), keyEquivalent: "q"))

        // Set target for quit item
        menu.items.last?.target = self

        statusItem.menu = menu
    }

    @objc private func newRecording() {
        appState.screen = .sourcePicker
        showPanel()
    }

    @objc private func openLibrary() {
        appState.screen = .library
        showPanel()
    }

    @objc private func openSettings() {
        appState.screen = .settings
        showPanel()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func setupPanel() {
        let contentView = ContentView()
            .environmentObject(appState)
            .frame(minWidth: 420, minHeight: 500)
            .tint(MuxTheme.orange)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = NSHostingView(rootView: contentView)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = NSColor(MuxTheme.backgroundPrimary)

        appState.mainWindow = panel
    }

    func showPanel() {
        guard let button = statusItem.button else { return }
        let buttonFrame = button.window?.frame ?? .zero

        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height
        let x = buttonFrame.midX - panelWidth / 2
        let y = buttonFrame.minY - panelHeight

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hidePanel() {
        panel.orderOut(nil)
    }
}
