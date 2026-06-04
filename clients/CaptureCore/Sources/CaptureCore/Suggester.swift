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
        ("engineering", ["pr", "pull request", "merge", "code review", "review", "deploy", "deployment", "release", "ship", "bug", "debug", "incident", "on-call", "oncall", "pager", "alert", "architecture", "design doc", "tech spec", "spec", "rfc", "refactor", "test", "tests", "ci", "cd", "pipeline", "build", "infra", "infrastructure", "terraform", "kubernetes", "docker", "api", "backend", "frontend", "database", "migration", "jira", "ticket", "issue", "slack", "github", "branch", "commit", "repo", "monitoring", "logs", "sentry", "railway"]),
        ("leadership", ["1:1", "one-on-one", "one to one", "performance review", "review cycle", "hiring", "hire", "interview", "candidate", "recruiting", "strategy", "roadmap", "planning", "plan", "quarterly", "okr", "okrs", "goal", "goals", "team sync", "standup", "retro", "retrospective", "stakeholder", "management update", "exec update", "leadership", "mentor", "mentoring", "coaching", "feedback", "promotion", "career", "headcount", "budget review"]),
        ("home", ["clean", "laundry", "cook", "tidy", "bin", "bins", "rubbish", "trash", "water plants", "vacuum", "repair", "assemble", "declutter", "garden", "lawn", "mow", "diy", "paint", "plumber", "electrician", "sink", "tap", "boiler", "door", "kids", "school run", "family", "meal prep"]),
        ("errands", ["buy", "pick up", "pickup", "grocery", "groceries", "shop", "shopping", "post office", "pharmacy", "return", "collect", "order", "drop off", "parcel", "package", "chemist", "dry cleaning", "book appointment", "car wash"]),
        ("health", ["gym", "run", "doctor", "dentist", "workout", "meds", "medicine", "appointment", "physio", "therapy", "prescription", "walk", "yoga", "optician", "checkup", "blood test", "vaccine", "vaccination", "health"]),
        ("finance", ["pay", "bill", "tax", "bank", "transfer", "budget", "renew", "renewal", "subscription", "mortgage", "rent", "insurance", "refund", "invoice", "expense", "expenses", "pension", "savings", "accountant", "hmrc", "vat"]),
        ("personal", ["call", "text", "birthday", "dinner", "meet", "party", "rsvp", "message", "catch up", "visit", "wedding", "reunion", "friend", "friends", "mum", "dad", "parents", "coffee", "date night", "holiday", "travel"])
    ]

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// Precompiled word-boundary matchers, one per keyword, so short keywords
    /// like "pr"/"run"/"ci" match whole tokens and not substrings ("prep",
    /// "running", "special"). Boundaries are non-alphanumeric or string ends,
    /// which still allows multi-word/punctuated keywords ("1:1", "on-call").
    private static let categoryMatchers: [(String, [NSRegularExpression])] = categoryKeywords.map { cat, words in
        (cat, words.map { boundedMatcher($0) })
    }

    private static func boundedMatcher(_ keyword: String) -> NSRegularExpression {
        let escaped = NSRegularExpression.escapedPattern(for: keyword.lowercased())
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(
            pattern: "(^|[^a-z0-9])\(escaped)([^a-z0-9]|$)",
            options: [.caseInsensitive]
        )
    }

    /// Pure and deterministic category guess — used directly in tests.
    public static func category(for text: String) -> (category: String?, hits: Int) {
        let lower = text.lowercased()
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        var category: String?
        var best = 0
        for (cat, matchers) in categoryMatchers {
            let hits = matchers.filter { $0.firstMatch(in: lower, options: [], range: range) != nil }.count
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
