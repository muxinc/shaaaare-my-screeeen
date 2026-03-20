import SwiftUI
import AppKit

// MARK: - Mux Brand Theme

enum MuxTheme {

    // MARK: Colors (light/dark adaptive)

    static let backgroundPrimary = Color(nsColor: .init(name: nil) { ap in
        ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x16/255, green: 0x16/255, blue: 0x18/255, alpha: 1)
            : NSColor(srgbRed: 0xFA/255, green: 0xFA/255, blue: 0xF9/255, alpha: 1) // putty-lighter
    })

    static let backgroundSecondary = Color(nsColor: .init(name: nil) { ap in
        ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x1E/255, green: 0x1E/255, blue: 0x22/255, alpha: 1)
            : NSColor(srgbRed: 0xF4/255, green: 0xF6/255, blue: 0xF4/255, alpha: 1) // putty-light
    })

    static let backgroundCard = Color(nsColor: .init(name: nil) { ap in
        ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x24/255, green: 0x24/255, blue: 0x28/255, alpha: 1)
            : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    })

    static let border = Color(nsColor: .init(name: nil) { ap in
        ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x30/255, green: 0x30/255, blue: 0x36/255, alpha: 1)
            : NSColor(srgbRed: 0xE2/255, green: 0xE4/255, blue: 0xDD/255, alpha: 1) // putty
    })

    static let textSecondary = Color(nsColor: .init(name: nil) { ap in
        ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x9A/255, green: 0x9A/255, blue: 0xA0/255, alpha: 1)
            : NSColor(srgbRed: 0x82/255, green: 0x8C/255, blue: 0x97/255, alpha: 1)
    })

    // Fixed brand colors
    static let orange      = Color(r: 0xFF, g: 0x61, b: 0x00)
    static let orangeDark  = Color(r: 0xBA, g: 0x43, b: 0x00)
    static let green       = Color(r: 0x00, g: 0xBE, b: 0x43)
    static let red         = Color(r: 0xEA, g: 0x37, b: 0x37)
    static let yellow      = Color(r: 0xFF, g: 0xB2, b: 0x00)
    static let charcoal    = Color(r: 0x24, g: 0x26, b: 0x28)

    // MARK: Typography

    /// Display/heading font — Rotonto if bundled, SF Rounded fallback
    static func display(size: CGFloat) -> Font {
        if hasRotonto { return .custom("Rotonto", size: size) }
        return .system(size: size, weight: .bold, design: .rounded)
    }

    /// Body font — Aeonik if bundled, system fallback
    static func body(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if hasAeonik { return .custom("Aeonik", size: size) }
        return .system(size: size, weight: weight)
    }

    /// Monospace font
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: Font Registration

    /// Call once at app launch. Drop .ttf/.otf files into Resources/Fonts/ to use
    /// Rotonto (display), Aeonik (body), and JetBrains Mono (code).
    static func registerFonts() {
        for ext in ["ttf", "otf"] {
            guard let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) else { continue }
            for url in urls {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    private static let hasRotonto: Bool = { NSFont(name: "Rotonto", size: 12) != nil }()
    private static let hasAeonik: Bool  = { NSFont(name: "Aeonik", size: 12)  != nil }()
}

// MARK: - Color Helper

private extension Color {
    init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.init(red: r / 255, green: g / 255, blue: b / 255)
    }
}

// MARK: - Button Styles

struct MuxPrimaryButtonStyle: ButtonStyle {
    var isDestructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(
                    configuration.isPressed
                        ? (isDestructive ? MuxTheme.red.opacity(0.8) : MuxTheme.orangeDark)
                        : (isDestructive ? MuxTheme.red : MuxTheme.orange)
                )
            )
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct MuxSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    Capsule().fill(MuxTheme.backgroundCard)
                    Capsule().strokeBorder(MuxTheme.border, lineWidth: 1.5)
                }
            )
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct MuxTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(configuration.isPressed ? MuxTheme.orangeDark : MuxTheme.orange)
    }
}

// MARK: - Section Header

struct MuxSectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.2)
            .foregroundColor(MuxTheme.textSecondary)
    }
}
