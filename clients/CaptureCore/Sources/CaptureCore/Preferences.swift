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
    public static let obsidianEnabledKey = "capture.obsidian.enabled"
    public static let obsidianVaultKey = "capture.obsidian.vault"
    public static let obsidianSummaryFolderKey = "capture.obsidian.summaryFolder"
    public static let obsidianCLICommandKey = "capture.obsidian.cliCommand"

    public var appearance: CaptureAppearanceMode
    public var obsidianEnabled: Bool
    public var obsidianVault: String
    public var obsidianSummaryFolder: String
    public var obsidianCLICommand: String

    public init(
        appearance: CaptureAppearanceMode = .dark,
        obsidianEnabled: Bool = false,
        obsidianVault: String = "",
        obsidianSummaryFolder: String = "Capture/Summaries",
        obsidianCLICommand: String = "obsidian"
    ) {
        self.appearance = appearance
        self.obsidianEnabled = obsidianEnabled
        self.obsidianVault = obsidianVault
        self.obsidianSummaryFolder = obsidianSummaryFolder
        self.obsidianCLICommand = obsidianCLICommand
    }

    public static func load(defaults: UserDefaults = .standard) -> CapturePreferences {
        let raw = defaults.string(forKey: appearanceKey)
        return CapturePreferences(
            appearance: raw.flatMap(CaptureAppearanceMode.init(rawValue:)) ?? .dark,
            obsidianEnabled: defaults.bool(forKey: obsidianEnabledKey),
            obsidianVault: defaults.string(forKey: obsidianVaultKey) ?? "",
            obsidianSummaryFolder: defaults.string(forKey: obsidianSummaryFolderKey) ?? "Capture/Summaries",
            obsidianCLICommand: defaults.string(forKey: obsidianCLICommandKey) ?? "obsidian"
        )
    }

    public func save(defaults: UserDefaults = .standard) {
        defaults.set(appearance.rawValue, forKey: Self.appearanceKey)
        defaults.set(obsidianEnabled, forKey: Self.obsidianEnabledKey)
        defaults.set(obsidianVault.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.obsidianVaultKey)
        defaults.set(obsidianSummaryFolder.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.obsidianSummaryFolderKey)
        defaults.set(obsidianCLICommand.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.obsidianCLICommandKey)
    }
}

public extension Notification.Name {
    static let captureAppearanceChanged = Notification.Name("CaptureAppearanceChanged")
}
