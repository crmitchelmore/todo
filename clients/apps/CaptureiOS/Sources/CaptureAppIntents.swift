import AppIntents
import CaptureCore

/// Siri / Shortcuts / Action Button capture. Runs **without opening the app** so a thought goes
/// from intent to a `proposed` row in one tap/utterance — capture first, organise later.
///
/// Deliberately UIKit/AppIntents only (no SwiftUI). The intent never touches PowerSync; it uses the
/// same resilient backend-POST-with-offline-outbox path as the Share Extension, so a capture made
/// with no signal is queued in the App Group and drained by the app on next launch.
struct CaptureTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture a To-Do"
    static let description = IntentDescription(
        "Instantly capture a to-do. It's saved as a proposal you confirm later.",
        categoryName: "Capture"
    )

    /// Capture happens in the background — speed is the whole point.
    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "To-Do",
        description: "What do you need to do?",
        requestValueDialog: "What do you want to capture?"
    )
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Nothing to capture.")
        }
        let ingress = CaptureConfig.fromEnvironment().makeIngress()
        let input = CaptureInput(rawText: trimmed, source: "app-intent")
        try await ingress.capture(input)
        return .result(dialog: "Captured. I'll suggest a date and category for you to confirm.")
    }
}

/// Phrases that expose the intent to Siri and let it be assigned to the Action Button / Shortcuts.
struct CaptureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureTodoIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "Capture a to-do in \(.applicationName)",
                "Add a to-do to \(.applicationName)",
                "New \(.applicationName) to-do"
            ],
            shortTitle: "Capture To-Do",
            systemImageName: "bolt.fill"
        )
    }
}
