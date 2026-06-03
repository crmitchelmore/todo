import UIKit

/// The "instrument for thought" design language, mirrored from the web surface: an ink canvas,
/// a single solar-amber signal accent, mint reserved for done/synced, characterful rounded display
/// type and monospaced metadata. Kept in sync with web/src/styles.css `:root` tokens.
enum Theme {
    // Canvas + surfaces
    static let ink = UIColor(hex: "0a0b0d")!
    static let surface = UIColor(hex: "16181d")!
    static let surfaceHi = UIColor(hex: "20242c")!

    // Signal + semantics
    static let signal = UIColor(hex: "ff9f2e")!
    static let signalDeep = UIColor(hex: "ff7a18")!
    static let mint = UIColor(hex: "4ade9e")!
    static let iris = UIColor(hex: "8b7bff")!
    static let danger = UIColor(hex: "ff6363")!

    // Text
    static let textPrimary = UIColor(hex: "f4f3ef")!
    static let textSecondary = UIColor(white: 1, alpha: 0.58)
    static let textTertiary = UIColor(white: 1, alpha: 0.34)

    /// Rounded grotesque-flavoured display face (Bricolage stand-in until a bundled font ships).
    static func display(_ size: CGFloat, _ weight: UIFont.Weight = .bold) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: d, size: size)
    }

    /// Monospaced face for metadata (dates, hints, counts) — the JetBrains Mono role.
    static func mono(_ size: CGFloat, _ weight: UIFont.Weight = .medium) -> UIFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Style a button as the primary amber action with dark ink text.
    static func primary(_ button: UIButton) {
        button.backgroundColor = signal
        button.setTitleColor(ink, for: .normal)
        button.layer.cornerRadius = 12
    }
}
