import Foundation

public struct Suggestion: Sendable, Equatable {
    public var dueAt: Date?
    public var category: String?
    public var confidence: Double
    public init(dueAt: Date?, category: String?, confidence: Double) {
        self.dueAt = dueAt
        self.category = category
        self.confidence = confidence
    }
}

/// Fully on-device, deliberately cheap suggestion pass so it never delays capture.
/// Dates via `NSDataDetector` (native NL parsing); categories via keyword hits.
public enum Suggester {
    private static let categoryKeywords: [(String, [String])] = [
        ("engineering", ["pr", "pull request", "code review", "review", "deploy", "bug", "incident", "on-call", "architecture", "spec", "refactor", "test", "ci", "build", "infra", "api", "jira"]),
        ("leadership", ["1:1", "one-on-one", "performance review", "hiring", "interview", "strategy", "roadmap", "planning", "okr", "team sync", "standup", "retro", "stakeholder", "mentor"]),
        ("home", ["clean", "fix", "laundry", "cook", "tidy", "bin", "water plants", "repair", "garden", "kids", "family"]),
        ("errands", ["buy", "pick up", "grocery", "shop", "post office", "pharmacy", "return", "collect", "drop off"]),
        ("health", ["gym", "run", "doctor", "dentist", "workout", "meds", "appointment", "physio"]),
        ("finance", ["pay", "bill", "tax", "bank", "transfer", "budget", "renew", "subscription"]),
        ("personal", ["call", "text", "birthday", "dinner", "meet", "party", "rsvp", "friend", "mum", "dad"])
    ]

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// Pure and deterministic category guess — used directly in tests.
    public static func category(for text: String) -> (category: String?, hits: Int) {
        let lower = text.lowercased()
        var category: String?
        var best = 0
        for (cat, words) in categoryKeywords {
            let hits = words.filter { lower.contains($0) }.count
            if hits > best {
                best = hits
                category = cat
            }
        }
        return (category, best)
    }

    public static func detectDate(in text: String) -> Date? {
        guard let detector else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range).first?.date
    }

    public static func suggest(_ text: String) -> Suggestion {
        let dueAt = detectDate(in: text)
        let (category, hits) = category(for: text)
        let confidence = min(1.0, (dueAt != nil ? 0.5 : 0.0) + Double(hits) * 0.25)
        return Suggestion(dueAt: dueAt, category: category, confidence: confidence)
    }
}
