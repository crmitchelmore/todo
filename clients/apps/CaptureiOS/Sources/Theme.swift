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
    static var surfaceRaised: UIColor { UIColor(hex: light ? "ffffff" : "232830")! }
    static var surfaceSelected: UIColor { light ? UIColor(hex: "fff1dc")! : UIColor(hex: "2a241e")! }
    static var hairline: UIColor { light ? UIColor(white: 0, alpha: 0.10) : UIColor(white: 1, alpha: 0.08) }
    static var shadow: UIColor { light ? UIColor(white: 0, alpha: 0.16) : UIColor(white: 0, alpha: 0.42) }

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
    /// Scaled with the user's Dynamic Type setting (clamped so the dense cockpit layout survives
    /// accessibility sizes); at the default content size this is identical to the fixed size.
    static func display(_ size: CGFloat, _ weight: UIFont.Weight = .bold) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let rounded = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        return UIFontMetrics.default.scaledFont(for: rounded, maximumPointSize: size * 1.35)
    }

    /// Monospaced face for metadata (dates, hints, counts) — the JetBrains Mono role. Dynamic-Type
    /// scaled with a tighter clamp so tabular metadata stays legible without breaking row layout.
    static func mono(_ size: CGFloat, _ weight: UIFont.Weight = .medium) -> UIFont {
        let base = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        return UIFontMetrics.default.scaledFont(for: base, maximumPointSize: size * 1.3)
    }

    /// Style a button as the primary amber action with dark ink text.
    static func primary(_ button: UIButton) {
        button.backgroundColor = signal
        button.setTitleColor(ink, for: .normal)
        button.layer.cornerRadius = 12
        button.titleLabel?.font = display(15, .semibold)
    }

    static func quiet(_ button: UIButton, colour: UIColor? = nil) {
        button.backgroundColor = surfaceHi
        button.setTitleColor(colour ?? textSecondary, for: .normal)
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 1
        button.layer.borderColor = hairline.cgColor
        button.titleLabel?.font = display(14, .semibold)
    }

    static func panel(_ view: UIView, color: UIColor = Theme.surface, radius: CGFloat = 20, bordered: Bool = true) {
        view.backgroundColor = color
        view.layer.cornerRadius = radius
        view.layer.borderWidth = bordered ? 1 : 0
        view.layer.borderColor = hairline.cgColor
        view.layer.masksToBounds = false
    }

    static func card(_ view: UIView, color: UIColor = Theme.surfaceHi, radius: CGFloat = 18) {
        panel(view, color: color, radius: radius)
        view.layer.shadowColor = shadow.cgColor
        view.layer.shadowOpacity = light ? 0.10 : 0.24
        view.layer.shadowRadius = 18
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
    }

    static func input(_ field: UITextField) {
        field.textColor = textPrimary
        field.tintColor = signal
        field.backgroundColor = surfaceHi
        field.layer.cornerRadius = 14
        field.layer.borderWidth = 1
        field.layer.borderColor = hairline.cgColor
        field.borderStyle = .none
    }
}

/// Subtle, restrained haptics — reserved for meaningful moments (capture, confirm, complete),
/// never per-scroll or per-focus. Respects the system Haptics setting automatically.
@MainActor
enum Haptics {
    /// A light tap on capture submit — the "it landed" confirmation of the hot path.
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    /// Success notification when a proposal is confirmed or a task is completed.
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
