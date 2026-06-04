import UIKit
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
            return UITraitCollection.current.userInterfaceStyle == .light
        }
    }

    // Canvas + surfaces
    static var ink: UIColor { UIColor(hex: light ? "f3efe5" : "0a0b0d")! }
    static var surface: UIColor { UIColor(hex: light ? "fff8ee" : "16181d")! }
    static var surfaceHi: UIColor { UIColor(hex: light ? "fffdf7" : "20242c")! }

    // Signal + semantics
    static var signal: UIColor { UIColor(hex: "ff9f2e")! }
    static var signalDeep: UIColor { UIColor(hex: "ff7a18")! }
    static var mint: UIColor { UIColor(hex: light ? "25915d" : "4ade9e")! }
    static var iris: UIColor { UIColor(hex: light ? "6757d8" : "8b7bff")! }
    static var danger: UIColor { UIColor(hex: light ? "cb3636" : "ff6363")! }

    // Text
    static var textPrimary: UIColor { UIColor(hex: light ? "1c1915" : "f4f3ef")! }
    static var textSecondary: UIColor { light ? UIColor(hex: "655d52")! : UIColor(white: 1, alpha: 0.58) }
    static var textTertiary: UIColor { light ? UIColor(hex: "8e8374")! : UIColor(white: 1, alpha: 0.34) }

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
