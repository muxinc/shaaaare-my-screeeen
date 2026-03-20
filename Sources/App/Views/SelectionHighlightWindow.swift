import AppKit
import ScreenCaptureKit

class SelectionHighlightWindow {
    static let shared = SelectionHighlightWindow()
    private var highlightWindow: NSWindow?
    private var borderView: HighlightBorderView?
    private let borderWidth: CGFloat = 4
    private let borderColor = NSColor(srgbRed: 0xFF/255, green: 0x61/255, blue: 0x00/255, alpha: 1)

    func highlightDisplay(_ display: SCDisplay) {
        // Find the matching NSScreen
        guard let screen = NSScreen.screens.first(where: { screen in
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return screenNumber == display.displayID
        }) else { return }

        showBorder(frame: screen.frame)
    }

    func highlightWindow(_ window: SCWindow) {
        // SCWindow.frame is in screen coordinates (origin at top-left)
        // NSWindow.frame uses bottom-left origin, so we need to convert
        guard let mainScreen = NSScreen.screens.first else { return }
        let screenHeight = mainScreen.frame.height

        let frame = NSRect(
            x: window.frame.origin.x,
            y: screenHeight - window.frame.origin.y - window.frame.height,
            width: window.frame.width,
            height: window.frame.height
        )

        showBorder(frame: frame)
    }

    func dismiss() {
        highlightWindow?.orderOut(nil)
    }

    private func showBorder(frame: NSRect) {
        let inset: CGFloat = -borderWidth
        let borderFrame = frame.insetBy(dx: inset, dy: inset)

        if let window = highlightWindow, let view = borderView {
            // Reuse existing window — just move and resize it
            window.setFrame(borderFrame, display: false)
            view.frame = NSRect(x: 0, y: 0, width: borderFrame.width, height: borderFrame.height)
            view.needsDisplay = true
            window.alphaValue = 1.0
            window.orderFrontRegardless()
        } else {
            // First time — create the window
            let window = NSWindow(
                contentRect: borderFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false

            let view = HighlightBorderView(borderWidth: borderWidth, borderColor: borderColor)
            view.frame = NSRect(x: 0, y: 0, width: borderFrame.width, height: borderFrame.height)

            window.contentView = view
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            window.alphaValue = 1.0
            window.orderFrontRegardless()
            self.highlightWindow = window
            self.borderView = view
        }

        // Fade to subtle after a moment
        let currentWindow = highlightWindow
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, self.highlightWindow === currentWindow, currentWindow?.isVisible == true else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                currentWindow?.animator().alphaValue = 0.6
            }
        }
    }
}

private class HighlightBorderView: NSView {
    let borderWidth: CGFloat
    let borderColor: NSColor

    init(borderWidth: CGFloat, borderColor: NSColor) {
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2),
                                xRadius: 6, yRadius: 6)
        path.lineWidth = borderWidth
        borderColor.withAlphaComponent(0.9).setStroke()
        path.stroke()

        // Subtle fill to tint the selected area
        borderColor.withAlphaComponent(0.03).setFill()
        path.fill()
    }
}
