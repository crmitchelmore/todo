import AppKit
import Carbon.HIToolbox

/// A user-configurable global hotkey: a key plus modifier flags.
///
/// Adapted from the justspeaktoit SpeakHotKeys package, trimmed to the custom-combination
/// case (Capture summons a panel, so it doesn't need the Fn/hold/tap gesture machinery).
struct HotKey: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: ModifierSet

    /// Default summon shortcut: ⌥Space.
    static let `default` = HotKey(keyCode: UInt16(kVK_Space), modifiers: .option)

    /// Human-readable representation, e.g. "⌥Space" or "⌘⇧K".
    var displayString: String {
        modifiers.displayString + KeyCodeMapping.string(for: keyCode)
    }

    /// Modifier flags stored as a Codable, Sendable, Hashable set.
    struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
        let rawValue: UInt
        init(rawValue: UInt) { self.rawValue = rawValue }

        static let command = ModifierSet(rawValue: 1 << 0)
        static let option = ModifierSet(rawValue: 1 << 1)
        static let shift = ModifierSet(rawValue: 1 << 2)
        static let control = ModifierSet(rawValue: 1 << 3)

        init(from nsFlags: NSEvent.ModifierFlags) {
            var raw: UInt = 0
            if nsFlags.contains(.command) { raw |= ModifierSet.command.rawValue }
            if nsFlags.contains(.option) { raw |= ModifierSet.option.rawValue }
            if nsFlags.contains(.shift) { raw |= ModifierSet.shift.rawValue }
            if nsFlags.contains(.control) { raw |= ModifierSet.control.rawValue }
            self.init(rawValue: raw)
        }

        /// Carbon modifier mask for `RegisterEventHotKey`.
        var carbonFlags: UInt32 {
            var carbon: UInt32 = 0
            if contains(.command) { carbon |= UInt32(cmdKey) }
            if contains(.option) { carbon |= UInt32(optionKey) }
            if contains(.shift) { carbon |= UInt32(shiftKey) }
            if contains(.control) { carbon |= UInt32(controlKey) }
            return carbon
        }

        var displayString: String {
            var parts: [String] = []
            if contains(.control) { parts.append("⌃") }
            if contains(.option) { parts.append("⌥") }
            if contains(.shift) { parts.append("⇧") }
            if contains(.command) { parts.append("⌘") }
            return parts.joined()
        }
    }
}

/// Maps macOS virtual key codes to human-readable strings. Ported from SpeakHotKeys.
enum KeyCodeMapping {
    static func string(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"; case 1: return "S"; case 2: return "D"; case 3: return "F"
        case 4: return "H"; case 5: return "G"; case 6: return "Z"; case 7: return "X"
        case 8: return "C"; case 9: return "V"; case 11: return "B"; case 12: return "Q"
        case 13: return "W"; case 14: return "E"; case 15: return "R"; case 16: return "Y"
        case 17: return "T"; case 18: return "1"; case 19: return "2"; case 20: return "3"
        case 21: return "4"; case 22: return "6"; case 23: return "5"; case 24: return "="
        case 25: return "9"; case 26: return "7"; case 27: return "-"; case 28: return "8"
        case 29: return "0"; case 30: return "]"; case 31: return "O"; case 32: return "U"
        case 33: return "["; case 34: return "I"; case 35: return "P"; case 36: return "↩"
        case 37: return "L"; case 38: return "J"; case 39: return "'"; case 40: return "K"
        case 41: return ";"; case 42: return "\\"; case 43: return ","; case 44: return "/"
        case 45: return "N"; case 46: return "M"; case 47: return "."; case 48: return "⇥"
        case 49: return "Space"; case 50: return "`"; case 51: return "⌫"; case 53: return "⎋"
        case 96: return "F5"; case 97: return "F6"; case 98: return "F7"; case 99: return "F3"
        case 100: return "F8"; case 101: return "F9"; case 103: return "F11"; case 105: return "F13"
        case 107: return "F14"; case 109: return "F10"; case 111: return "F12"; case 113: return "F15"
        case 118: return "F4"; case 119: return "End"; case 120: return "F2"; case 121: return "PgDn"
        case 122: return "F1"; case 123: return "←"; case 124: return "→"; case 125: return "↓"
        case 126: return "↑"
        default: return "Key\(keyCode)"
        }
    }

    /// Modifier-only key codes — ignored when recording a shortcut.
    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 60, 58, 61, 59, 62, 63]
}
