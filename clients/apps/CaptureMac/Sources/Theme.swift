import AppKit
import CaptureCore

/// The "instrument for thought" design language, mirrored from the web surface: an ink canvas,
/// a single solar-amber signal accent, mint reserved for done/synced, characterful rounded display
/// type and monospaced metadata. Kept in sync with web/src/styles.css `:root` tokens.
enum Theme {
    private static var light: Bool {
        switch CapturePreferences.load().appearance {
        case .light:
            return true
        case .dark:
            return false
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        }
    }

    // Canvas + surfaces
    static var ink: NSColor { NSColor(hex: light ? "f3efe5" : "0a0b0d")! }
    static var surface: NSColor { NSColor(hex: light ? "fff8ee" : "16181d")! }
    static var surfaceHi: NSColor { NSColor(hex: light ? "fffdf7" : "20242c")! }
    static var surfaceRaised: NSColor { NSColor(hex: light ? "ffffff" : "232830")! }
    static var surfaceSelected: NSColor { light ? NSColor(hex: "fff1dc")! : NSColor(hex: "2a241e")! }
    static var hairline: NSColor { light ? NSColor(white: 0, alpha: 0.10) : NSColor(white: 1, alpha: 0.08) }
    static var shadow: NSColor { light ? NSColor(white: 0, alpha: 0.16) : NSColor(white: 0, alpha: 0.42) }

    // Signal + semantics
    static var signal: NSColor { NSColor(hex: "ff9f2e")! }
    static var signalDeep: NSColor { NSColor(hex: "ff7a18")! }
    static var mint: NSColor { NSColor(hex: light ? "25915d" : "4ade9e")! }
    static var iris: NSColor { NSColor(hex: light ? "6757d8" : "8b7bff")! }
    static var danger: NSColor { NSColor(hex: light ? "cb3636" : "ff6363")! }

    // Text
    static var textPrimary: NSColor { NSColor(hex: light ? "1c1915" : "f4f3ef")! }
    static var textSecondary: NSColor { light ? NSColor(hex: "655d52")! : NSColor(white: 1, alpha: 0.58) }
    static var textTertiary: NSColor { light ? NSColor(hex: "8e8374")! : NSColor(white: 1, alpha: 0.34) }

    /// Rounded grotesque-flavoured display face (Bricolage stand-in until a bundled font ships).
    static func display(_ size: CGFloat, _ weight: NSFont.Weight = .bold) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let desc = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return NSFont(descriptor: desc, size: size) ?? base
    }

    /// Monospaced face for metadata (dates, hints, counts) — the JetBrains Mono role.
    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Style a push button as the primary amber action with dark ink text.
    static func primary(_ button: NSButton, fontSize: CGFloat = 13) {
        button.bezelStyle = .rounded
        button.bezelColor = signal
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: ink,
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            ])
    }

    /// Give a view a flat ink background (used on the root content views).
    static func paintInk(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = ink.cgColor
    }

    static func panel(_ view: NSView, color: NSColor = Theme.surface, radius: CGFloat = 18, bordered: Bool = true) {
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.layer?.cornerRadius = radius
        view.layer?.masksToBounds = false
        view.layer?.borderWidth = bordered ? 1 : 0
        view.layer?.borderColor = hairline.cgColor
    }

    static func card(_ view: NSView, color: NSColor = Theme.surfaceHi, radius: CGFloat = 16) {
        panel(view, color: color, radius: radius)
        view.layer?.shadowColor = shadow.cgColor
        view.layer?.shadowOpacity = light ? 0.08 : 0.18
        view.layer?.shadowRadius = 18
        view.layer?.shadowOffset = CGSize(width: 0, height: -4)
    }

    static func quietButton(_ button: NSButton, fontSize: CGFloat = 12) {
        button.bezelStyle = .rounded
        button.font = Theme.display(fontSize, .semibold)
        button.contentTintColor = textSecondary
    }
}
