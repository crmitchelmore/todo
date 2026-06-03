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
    public var tags: [String]
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
        tags: [String] = [],
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
        self.tags = tags
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

/// Append-only history row for a task. Written by the backend/worker and synced read-only to
/// clients so detail panes can show user changes and AI/agent work without joining into hot lists.
public struct TaskEvent: Identifiable, Sendable, Equatable {
    public let id: String
    public var ownerId: String
    public var taskId: String
    public var actor: String
    public var eventType: String
    public var title: String
    public var body: String?
    public var metadata: String?
    public var createdAt: Date?

    public init(
        id: String,
        ownerId: String,
        taskId: String,
        actor: String,
        eventType: String,
        title: String,
        body: String? = nil,
        metadata: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.taskId = taskId
        self.actor = actor
        self.eventType = eventType
        self.title = title
        self.body = body
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

/// A user-managed label (also used for "projects" — a project is just a tag).
/// Mirrors `public.tags` in Postgres and the client SQLite schema.
public struct Tag: Identifiable, Sendable, Equatable {
    public let id: String
    public var ownerId: String
    public var name: String
    public var color: String
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(id: String, ownerId: String, name: String, color: String, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Tag presentation helpers. Tags are stored on a task as a JSON array of names (PowerSync
/// has no array column type); identity is the case-insensitive name.
public enum TagPalette {
    /// A fixed, pleasant set of chip colours. New tags get a stable colour derived from their
    /// name so they look consistent across clients even before a row exists in `tags`.
    public static let colors = [
        "#E5484D", "#E54666", "#F76B15", "#FFB224", "#46A758", "#12A594",
        "#0091FF", "#3E63DD", "#8E4EC6", "#D6409F", "#9BA1A6", "#A18072"
    ]

    public static func color(for name: String) -> String {
        let key = name.lowercased()
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return colors[Int(hash % UInt64(colors.count))]
    }

    /// Canonical comparison key for a tag name (trimmed, case-insensitive).
    public static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Encodes/decodes the `tasks.tags` JSON-array text column.
public enum TagsCodec {
    public static func encode(_ tags: [String]) -> String? {
        let cleaned = normalize(tags)
        guard !cleaned.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(cleaned) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decode(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty, let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Trim, drop empties, and de-duplicate case-insensitively (keeping first spelling).
    public static func normalize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in tags {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            if !trimmed.isEmpty && !seen.contains(key) {
                seen.insert(key)
                out.append(trimmed)
            }
        }
        return out
    }
}


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
