import Foundation

public enum CaptureAppearanceMode: String, CaseIterable, Sendable, Identifiable {
    case system
    case dark
    case light

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
}

public struct CapturePreferences: Sendable {
    public static let appearanceKey = "capture.appearanceMode"

    public var appearance: CaptureAppearanceMode

    public init(appearance: CaptureAppearanceMode = .dark) {
        self.appearance = appearance
    }

    public static func load(defaults: UserDefaults = .standard) -> CapturePreferences {
        let raw = defaults.string(forKey: appearanceKey)
        return CapturePreferences(appearance: raw.flatMap(CaptureAppearanceMode.init(rawValue:)) ?? .dark)
    }

    public func save(defaults: UserDefaults = .standard) {
        defaults.set(appearance.rawValue, forKey: Self.appearanceKey)
    }
}

public extension Notification.Name {
    static let captureAppearanceChanged = Notification.Name("CaptureAppearanceChanged")
}
