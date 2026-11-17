import Foundation

/// Explicit, versioned consent for sending task content to the third-party AI provider used by the
/// Capture worker (App Store Review Guideline 5.1.2(i)). Stored in the shared App Group so the Share
/// Extension and App Intents honour the same decision as the main app.
public struct AIDataConsent: @unchecked Sendable {
    /// Bump when the provider or the data shared changes so users are asked again.
    public static let currentVersion = 1
    public static let versionKey = "capture.aiConsent.version"
    public static let decidedAtKey = "capture.aiConsent.decidedAt"

    public static let providerName = "OpenAI"
    public static let privacyPolicyURL = URL(string: "https://github.com/crmitchelmore/todo/blob/main/docs/privacy-policy.md")!

    public static let title = "AI processing of your tasks"
    public static let summary = """
    Capture uses \(providerName) to suggest categories, summarise links and research tasks. \
    When you capture or update a task, the Capture server sends \(providerName) the task title, \
    any research instructions, links in the task and their page text, and memory notes you've saved for research. \
    \(providerName) processes this data to return suggestions and doesn't receive your email address, \
    password or calendar. Calendar availability stays on this device.
    """
    public static let declineExplanation = """
    Capture needs AI processing to categorise and research tasks, so you can't capture tasks without it. \
    You can review this choice later in Settings or sign out.
    """

    // UserDefaults is documented thread-safe; it just lacks a Sendable annotation.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Prefers the shared App Group container so extensions see the main app's decision.
    public init(appGroupId: String? = "group.dev.crmitchelmore.capture") {
        self.init(defaults: appGroupId.flatMap(UserDefaults.init(suiteName:)) ?? .standard)
    }

    public var isGranted: Bool {
        defaults.integer(forKey: Self.versionKey) >= Self.currentVersion
    }

    public var decidedAt: Date? {
        defaults.object(forKey: Self.decidedAtKey) as? Date
    }

    public func grant(now: Date = Date()) {
        defaults.set(Self.currentVersion, forKey: Self.versionKey)
        defaults.set(now, forKey: Self.decidedAtKey)
    }

    public func revoke() {
        defaults.removeObject(forKey: Self.versionKey)
        defaults.removeObject(forKey: Self.decidedAtKey)
    }
}

public extension Notification.Name {
    static let captureAIConsentChanged = Notification.Name("CaptureAIConsentChanged")
}
