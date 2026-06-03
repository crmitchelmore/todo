import AppKit

/// The "instrument for thought" design language, mirrored from the web surface: an ink canvas,
/// a single solar-amber signal accent, mint reserved for done/synced, characterful rounded display
/// type and monospaced metadata. Kept in sync with web/src/styles.css `:root` tokens.
enum Theme {
    // Canvas + surfaces
    static let ink = NSColor(hex: "0a0b0d")!
    static let surface = NSColor(hex: "16181d")!
    static let surfaceHi = NSColor(hex: "20242c")!
    static let hairline = NSColor(white: 1, alpha: 0.08)

    // Signal + semantics
    static let signal = NSColor(hex: "ff9f2e")!
    static let signalDeep = NSColor(hex: "ff7a18")!
    static let mint = NSColor(hex: "4ade9e")!
    static let iris = NSColor(hex: "8b7bff")!
    static let danger = NSColor(hex: "ff6363")!

    // Text
    static let textPrimary = NSColor(hex: "f4f3ef")!
    static let textSecondary = NSColor(white: 1, alpha: 0.58)
    static let textTertiary = NSColor(white: 1, alpha: 0.34)

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
}
