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
        ("work", ["email", "meeting", "report", "deck", "client", "invoice", "slack", "jira", "pr", "deploy", "standup"]),
        ("errands", ["buy", "pick up", "grocery", "shop", "post office", "pharmacy", "return", "collect"]),
        ("health", ["gym", "run", "doctor", "dentist", "workout", "meds", "appointment"]),
        ("finance", ["pay", "bill", "tax", "bank", "transfer", "budget", "renew"]),
        ("home", ["clean", "fix", "laundry", "cook", "tidy", "bin", "water plants"]),
        ("social", ["call", "text", "birthday", "dinner", "meet", "party", "rsvp"])
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
