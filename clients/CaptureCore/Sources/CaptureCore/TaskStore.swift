import Foundation
import PowerSync

/// The capture-first task store. `capture` is the hot path: a single instant
/// local insert with status=proposed, then enrichment fires in the background
/// and patches the row. Confirmation promotes a proposal to an active todo.
public final class TaskStore: @unchecked Sendable {
    public let db: PowerSyncDatabaseProtocol
    private let connector: BackendConnector
    private let config: CaptureConfig

    public init(config: CaptureConfig = .localDev) {
        self.config = config
        self.db = PowerSyncDatabase(schema: AppSchema, dbFilename: "capture.sqlite")
        self.connector = BackendConnector(config: config)
    }

    public func connect() async throws {
        try await db.connect(connector: connector)
    }

    public func disconnect() async throws {
        try await db.disconnect()
    }

    // MARK: - Capture (hot path)

    /// Instant capture: generates an id, fires a local insert + background
    /// enrichment, and returns immediately. Never blocks on the network or an LLM.
    @discardableResult
    public func capture(_ raw: String) -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID().uuidString.lowercased()
        guard !title.isEmpty else { return id }
        Task.detached { [db, config] in
            let now = ISO8601.string(Date())
            _ = try? await db.execute(
                sql: """
                INSERT INTO \(TASKS_TABLE)
                    (id, owner_id, title, status, source, created_at, updated_at)
                VALUES (?, ?, ?, 'proposed', 'capture', ?, ?)
                """,
                parameters: [id, config.ownerId, title, now, now]
            )
            await Self.enrich(db: db, id: id, title: title)
        }
        return id
    }

    private static func enrich(db: PowerSyncDatabaseProtocol, id: String, title: String) async {
        let s = Suggester.suggest(title)
        let now = ISO8601.string(Date())
        _ = try? await db.execute(
            sql: """
            UPDATE \(TASKS_TABLE)
               SET suggested_due_at = ?, suggested_category = ?, suggestion_confidence = ?,
                   suggestion_source = 'on-device', updated_at = ?
             WHERE id = ?
            """,
            parameters: [
                s.dueAt.map(ISO8601.string), s.category, s.confidence, now, id
            ]
        )
    }

    // MARK: - Confirm / reject / complete

    /// Promote a proposed item to an active todo after the human confirms its structure.
    public func confirm(id: String, title: String?, dueAt: Date?, category: String?) async throws {
        let now = ISO8601.string(Date())
        try await db.execute(
            sql: """
            UPDATE \(TASKS_TABLE)
               SET status = 'active',
                   title = COALESCE(?, title),
                   due_at = ?, category = ?, confirmed_at = ?, updated_at = ?
             WHERE id = ?
            """,
            parameters: [title, dueAt.map(ISO8601.string), category, now, now, id]
        )
    }

    public func reject(id: String) async throws {
        try await db.execute(sql: "DELETE FROM \(TASKS_TABLE) WHERE id = ?", parameters: [id])
    }

    public func setDone(id: String, done: Bool) async throws {
        let now = ISO8601.string(Date())
        try await db.execute(
            sql: "UPDATE \(TASKS_TABLE) SET status = ?, completed_at = ?, updated_at = ? WHERE id = ?",
            parameters: [done ? "done" : "active", done ? now : nil, now, id]
        )
    }

    // MARK: - Reactive reads

    public func watchProposed() throws -> AsyncThrowingStream<[TaskItem], Error> {
        try db.watch(
            sql: "SELECT * FROM \(TASKS_TABLE) WHERE status = 'proposed' ORDER BY created_at DESC",
            parameters: [],
            mapper: Self.map
        )
    }

    public func watchActive() throws -> AsyncThrowingStream<[TaskItem], Error> {
        try db.watch(
            sql: """
            SELECT * FROM \(TASKS_TABLE) WHERE status = 'active'
            ORDER BY (due_at IS NULL), due_at ASC, created_at DESC
            """,
            parameters: [],
            mapper: Self.map
        )
    }

    public func watchDone() throws -> AsyncThrowingStream<[TaskItem], Error> {
        try db.watch(
            sql: "SELECT * FROM \(TASKS_TABLE) WHERE status = 'done' ORDER BY completed_at DESC LIMIT 50",
            parameters: [],
            mapper: Self.map
        )
    }

    static func map(_ cursor: SqlCursor) throws -> TaskItem {
        TaskItem(
            id: try cursor.getString(name: "id"),
            ownerId: (try cursor.getStringOptional(name: "owner_id")) ?? "",
            title: try cursor.getString(name: "title"),
            notes: try cursor.getStringOptional(name: "notes"),
            status: TaskStatus(rawValue: try cursor.getString(name: "status")) ?? .proposed,
            category: try cursor.getStringOptional(name: "category"),
            dueAt: ISO8601.date(try cursor.getStringOptional(name: "due_at")),
            priority: try cursor.getIntOptional(name: "priority"),
            suggestedDueAt: ISO8601.date(try cursor.getStringOptional(name: "suggested_due_at")),
            suggestedCategory: try cursor.getStringOptional(name: "suggested_category"),
            suggestionConfidence: try cursor.getDoubleOptional(name: "suggestion_confidence"),
            suggestionSource: try cursor.getStringOptional(name: "suggestion_source"),
            source: try cursor.getStringOptional(name: "source"),
            createdAt: ISO8601.date(try cursor.getStringOptional(name: "created_at")),
            updatedAt: ISO8601.date(try cursor.getStringOptional(name: "updated_at")),
            confirmedAt: ISO8601.date(try cursor.getStringOptional(name: "confirmed_at")),
            completedAt: ISO8601.date(try cursor.getStringOptional(name: "completed_at"))
        )
    }
}
