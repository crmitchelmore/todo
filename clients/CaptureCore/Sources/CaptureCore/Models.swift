import Foundation

/// Lifecycle of a captured item. Only `confirmed`/`active`+ are "real" todos;
/// `proposed` is the instant-capture inbox awaiting the mandatory human confirm.
public enum TaskStatus: String, Sendable, CaseIterable {
    case proposed
    case active
    case done
    case cancelled
}

/// A single task row. Mirrors `public.tasks` in Postgres and the web SQLite schema.
/// Timestamps are ISO-8601 text (PowerSync columns are text/integer/real only).
public struct TaskItem: Identifiable, Sendable, Equatable {
    public let id: String
    public var ownerId: String
    public var title: String
    public var notes: String?
    public var status: TaskStatus
    public var category: String?
    public var dueAt: Date?
    public var priority: Int?
    public var suggestedDueAt: Date?
    public var suggestedCategory: String?
    public var suggestionConfidence: Double?
    public var suggestionSource: String?
    public var source: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var confirmedAt: Date?
    public var completedAt: Date?

    public init(
        id: String,
        ownerId: String,
        title: String,
        notes: String? = nil,
        status: TaskStatus,
        category: String? = nil,
        dueAt: Date? = nil,
        priority: Int? = nil,
        suggestedDueAt: Date? = nil,
        suggestedCategory: String? = nil,
        suggestionConfidence: Double? = nil,
        suggestionSource: String? = nil,
        source: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        confirmedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.notes = notes
        self.status = status
        self.category = category
        self.dueAt = dueAt
        self.priority = priority
        self.suggestedDueAt = suggestedDueAt
        self.suggestedCategory = suggestedCategory
        self.suggestionConfidence = suggestionConfidence
        self.suggestionSource = suggestionSource
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.confirmedAt = confirmedAt
        self.completedAt = completedAt
    }
}

public let CAPTURE_CATEGORIES = [
    "engineering", "leadership", "home", "errands", "health", "finance", "personal", "inbox"
]

enum ISO8601 {
    // ISO8601DateFormatter is thread-safe for formatting/parsing in modern Foundation.
    nonisolated(unsafe) static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }

    static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return formatter.date(from: s) ?? plain.date(from: s)
    }
}
