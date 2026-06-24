import Foundation

/// Lifecycle of a captured item. Only `confirmed`/`active`+ are "real" todos;
/// `proposed` is the instant-capture inbox awaiting the mandatory human confirm,
/// and `cancelled` is the low-fidelity rejected bin.
public enum TaskStatus: String, Sendable, CaseIterable {
    case proposed
    case active
    case done
    case cancelled
}

public enum TaskAgentMode: String, Codable, Sendable, Equatable, CaseIterable {
    case research
    case attempt
}

/// A single task row. Mirrors `public.tasks` in Postgres and the web SQLite schema.
/// Timestamps are ISO-8601 text (PowerSync columns are text/integer/real only).
public struct TaskItem: Identifiable, Sendable, Equatable {
    public let id: String
    public var ownerId: String
    public var parentTaskId: String?
    public var title: String
    public var notes: String?
    public var status: TaskStatus
    public var category: String?
    public var tags: [String]
    public var dueAt: Date?
    public var priority: Int?
    public var githubRepo: String?
    public var githubURL: String?
    public var agentMode: TaskAgentMode
    public var agentPlanConfirmation: Bool
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
        parentTaskId: String? = nil,
        title: String,
        notes: String? = nil,
        status: TaskStatus,
        category: String? = nil,
        tags: [String] = [],
        dueAt: Date? = nil,
        priority: Int? = nil,
        githubRepo: String? = nil,
        githubURL: String? = nil,
        agentMode: TaskAgentMode = .research,
        agentPlanConfirmation: Bool = true,
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
        self.parentTaskId = parentTaskId
        self.title = title
        self.notes = notes
        self.status = status
        self.category = category
        self.tags = tags
        self.dueAt = dueAt
        self.priority = priority
        self.githubRepo = githubRepo
        self.githubURL = githubURL
        self.agentMode = agentMode
        self.agentPlanConfirmation = agentPlanConfirmation
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

public struct CaptureNotification: Identifiable, Sendable, Equatable {
    public let id: String
    public var ownerId: String
    public var taskId: String?
    public var kind: String
    public var severity: String
    public var title: String
    public var body: String?
    public var metadata: String?
    public var createdAt: Date?

    public init(id: String, ownerId: String, taskId: String?, kind: String, severity: String, title: String, body: String?, metadata: String?, createdAt: Date?) {
        self.id = id
        self.ownerId = ownerId
        self.taskId = taskId
        self.kind = kind
        self.severity = severity
        self.title = title
        self.body = body
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public let CAPTURE_CATEGORIES = [
    "engineering", "leadership", "home", "errands", "health", "finance", "personal", "inbox"
]

/// A user-managed category. Tasks reference categories by name so renames can preserve the stable
/// metadata row while rewriting task.category values.
public struct TaskCategory: Identifiable, Sendable, Equatable {
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

/// User-owned, human-readable instructions that guide background categorisation. The worker only
/// uses these to propose category/tag suggestions; task confirmation remains a human action.
public struct CategorisationRule: Identifiable, Sendable, Equatable {
    public let id: String
    public var ownerId: String
    public var title: String
    public var instructions: String
    public var category: String?
    public var tags: [String]
    public var enabled: Bool
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String,
        ownerId: String,
        title: String,
        instructions: String,
        category: String? = nil,
        tags: [String] = [],
        enabled: Bool = true,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.instructions = instructions
        self.category = category
        self.tags = tags
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum UserMemoryStatus: String, Sendable, Equatable {
    case active
    case disabled
    case deleted
}

public enum UserMemorySource: String, Sendable, Equatable {
    case manual
    case correction
    case inferred
    case agent
}

/// User-visible facts/preferences that the worker may use as context for agent research.
/// Memories are soft-deletable and optionally expire so stale personal context does not silently
/// guide future decisions forever.
public struct UserMemory: Identifiable, Sendable, Equatable {
    public let id: String
    public var ownerId: String
    public var content: String
    public var domain: String?
    public var source: UserMemorySource
    public var confidence: Double
    public var tags: [String]
    public var status: UserMemoryStatus
    public var expiresAt: Date?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(
        id: String,
        ownerId: String,
        content: String,
        domain: String? = nil,
        source: UserMemorySource = .manual,
        confidence: Double = 1,
        tags: [String] = [],
        status: UserMemoryStatus = .active,
        expiresAt: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.content = content
        self.domain = domain
        self.source = source
        self.confidence = confidence
        self.tags = tags
        self.status = status
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public enum AgentDeviceStatus: String, Sendable, Equatable {
    case active
    case disabled
}

public enum AgentHarnessKind: String, Sendable, Equatable, CaseIterable {
    case copilotCLI = "copilot-cli"
    case hermes
    case openclaw
    case custom
}

/// A synced local-computer registration row. Multiple Macs can install Capture, but at most one
/// active device should be selected as the backend computer for approved local harness attempts.
public struct AgentDevice: Identifiable, Sendable, Equatable {
    public let id: String
    public var ownerId: String
    public var deviceName: String
    public var platform: String
    public var status: AgentDeviceStatus
    public var isSelectedBackend: Bool
    public var harnessKind: AgentHarnessKind?
    public var harnessLabel: String?
    public var capabilities: [String]
    public var lastSeenAt: Date?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String,
        ownerId: String,
        deviceName: String,
        platform: String = "macos",
        status: AgentDeviceStatus = .active,
        isSelectedBackend: Bool = false,
        harnessKind: AgentHarnessKind? = nil,
        harnessLabel: String? = nil,
        capabilities: [String] = [],
        lastSeenAt: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.deviceName = deviceName
        self.platform = platform
        self.status = status
        self.isSelectedBackend = isSelectedBackend
        self.harnessKind = harnessKind
        self.harnessLabel = harnessLabel
        self.capabilities = capabilities
        self.lastSeenAt = lastSeenAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

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

/// User-attached image preview associated with a task. The row is synced so every detail pane can
/// render the history thumbnail; callers should pre-compress images before inserting.
public struct TaskAttachment: Identifiable, Sendable, Equatable {
    public let id: String
    public var ownerId: String
    public var taskId: String
    public var filename: String?
    public var mimeType: String
    public var byteSize: Int
    public var previewDataURL: String
    public var createdAt: Date?

    public init(
        id: String,
        ownerId: String,
        taskId: String,
        filename: String? = nil,
        mimeType: String,
        byteSize: Int,
        previewDataURL: String,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.taskId = taskId
        self.filename = filename
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.previewDataURL = previewDataURL
        self.createdAt = createdAt
    }
}

public struct TaskAttachmentDraft: Sendable, Equatable {
    public var filename: String?
    public var mimeType: String
    public var byteSize: Int
    public var previewDataURL: String

    public init(filename: String? = nil, mimeType: String, byteSize: Int, previewDataURL: String) {
        self.filename = filename
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.previewDataURL = previewDataURL
    }
}

/// Read-only aggregate for a task's descendants. Parent tasks/projects use this to show progress
/// without denormalising child state back into the parent row.
public struct TaskRollup: Sendable, Equatable {
    public let total: Int
    public let done: Int
    public let open: Int

    public init(total: Int, done: Int, open: Int) {
        self.total = total
        self.done = done
        self.open = open
    }

    public static let empty = TaskRollup(total: 0, done: 0, open: 0)
}

/// A user-managed label. Projects are represented by task/subtask hierarchy, while tags remain
/// lightweight labels.
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

public enum CategoryPalette {
    public static let colors = TagPalette.colors

    public static func color(for name: String) -> String {
        TagPalette.color(for: name)
    }

    public static func key(_ name: String) -> String {
        TagPalette.key(name)
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
