import Foundation
import PowerSync

/// The capture-first task store. `capture` is the hot path: a single instant
/// local insert with status=proposed, then enrichment fires in the background
/// and patches the row. Confirmation promotes a proposal to an active todo.
public final class TaskStore: @unchecked Sendable {
    public let db: PowerSyncDatabaseProtocol
    private let connector: BackendConnector
    private let config: CaptureConfig
    private let auth: AuthStore?

    public init(config: CaptureConfig = .localDev, auth: AuthStore? = nil) {
        self.config = config
        self.auth = auth
        self.db = PowerSyncDatabase(schema: AppSchema, dbFilename: "capture.sqlite")
        self.connector = BackendConnector(config: config, token: auth ?? AnonymousToken())
    }

    /// The owner id stamped on locally-created rows: the signed-in user when authenticated, else the
    /// config fallback (used by the offline probe/tests). Keeping this aligned with the server's
    /// owner-scoped writes and the per-user sync filter is what stops a fresh local row from being
    /// filtered straight back out on the next sync round-trip.
    private var ownerId: String { auth?.ownerId ?? config.ownerId }

    public func connect() async throws {
        try await db.connect(connector: connector)
    }

    public func disconnect() async throws {
        try await db.disconnect()
    }

    /// Wipe the local SQLite DB and pending upload queue. Call on every auth boundary (sign-in and
    /// sign-out) so one account's optimistic, not-yet-uploaded writes can never replay or leak into
    /// another account's synced view.
    public func resetLocalData() async throws {
        try await db.disconnectAndClear()
    }

    // MARK: - Capture (hot path)

    /// Instant capture: generates an id, fires a local insert + background
    /// enrichment, and returns immediately. Never blocks on the network or an LLM.
    @discardableResult
    public func capture(_ raw: String) -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID().uuidString.lowercased()
        guard !title.isEmpty else { return id }
        let ownerId = self.ownerId
        Task.detached { [db] in
            let now = ISO8601.string(Date())
            _ = try? await db.execute(
                sql: """
                INSERT INTO \(TASKS_TABLE)
                    (id, owner_id, title, status, source, created_at, updated_at)
                VALUES (?, ?, ?, 'proposed', 'capture', ?, ?)
                """,
                parameters: [id, ownerId, title, now, now]
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

    // MARK: - Batch capture (paste a markdown / checkbox list)

    /// Detects whether `raw` is a markdown/checkbox list. Returns the parsed items, or
    /// `nil` if it should be treated as a single capture.
    public func detectList(_ raw: String) -> [ParsedCaptureItem]? {
        MarkdownListParser.parse(raw)
    }

    /// Insert many items at once from a parsed list. Active (`[ ]` / plain) items land in
    /// the proposed inbox and get background enrichment; done (`[x]`) items import directly
    /// as completed. Any tags are materialised in the `tags` table (auto-coloured) so they
    /// show up in the manager. Returns the new ids in order.
    @discardableResult
    public func captureBatch(_ items: [ParsedCaptureItem]) -> [String] {
        let prepared: [(id: String, item: ParsedCaptureItem)] = items
            .map { (UUID().uuidString.lowercased(), $0) }
            .filter { !$0.1.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !prepared.isEmpty else { return [] }
        let allTags = TagsCodec.normalize(prepared.flatMap { $0.item.tags })
        let ownerId = self.ownerId
        Task.detached { [db] in
            await Self.ensureTags(db: db, ownerId: ownerId, names: allTags)
            for (id, item) in prepared {
                let now = ISO8601.string(Date())
                let tagsJSON = TagsCodec.encode(item.tags)
                if item.isDone {
                    _ = try? await db.execute(
                        sql: """
                        INSERT INTO \(TASKS_TABLE)
                            (id, owner_id, title, status, category, tags, source,
                             created_at, updated_at, confirmed_at, completed_at)
                        VALUES (?, ?, ?, 'done', NULL, ?, 'paste', ?, ?, ?, ?)
                        """,
                        parameters: [id, ownerId, item.title, tagsJSON, now, now, now, now]
                    )
                } else {
                    _ = try? await db.execute(
                        sql: """
                        INSERT INTO \(TASKS_TABLE)
                            (id, owner_id, title, status, tags, source, created_at, updated_at)
                        VALUES (?, ?, ?, 'proposed', ?, 'paste', ?, ?)
                        """,
                        parameters: [id, ownerId, item.title, tagsJSON, now, now]
                    )
                    await Self.enrich(db: db, id: id, title: item.title)
                }
            }
        }
        return prepared.map(\.id)
    }

    // MARK: - Confirm / reject / complete

    /// Promote a proposed item to an active todo after the human confirms its structure.
    public func confirm(id: String, title: String?, dueAt: Date?, category: String?, tags: [String]? = nil) async throws {
        let now = ISO8601.string(Date())
        if let tags { await Self.ensureTags(db: db, ownerId: ownerId, names: TagsCodec.normalize(tags)) }
        try await db.execute(
            sql: """
            UPDATE \(TASKS_TABLE)
               SET status = 'active',
                   title = COALESCE(?, title),
                   due_at = ?, category = ?, tags = COALESCE(?, tags),
                   confirmed_at = ?, updated_at = ?
             WHERE id = ?
            """,
            parameters: [title, dueAt.map(ISO8601.string), category,
                         tags.map { TagsCodec.encode($0) ?? "[]" }, now, now, id]
        )
    }

    /// Replace the tag set on an existing task (used by inline tag editing on a row).
    public func setTags(id: String, tags: [String]) async throws {
        let normalized = TagsCodec.normalize(tags)
        await Self.ensureTags(db: db, ownerId: ownerId, names: normalized)
        let now = ISO8601.string(Date())
        try await db.execute(
            sql: "UPDATE \(TASKS_TABLE) SET tags = ?, updated_at = ? WHERE id = ?",
            parameters: [TagsCodec.encode(normalized) ?? "[]", now, id]
        )
    }

    /// Set or clear the due date on any task (used by inline date editing on a row).
    public func setDue(id: String, dueAt: Date?) async throws {
        let now = ISO8601.string(Date())
        try await db.execute(
            sql: "UPDATE \(TASKS_TABLE) SET due_at = ?, updated_at = ? WHERE id = ?",
            parameters: [dueAt.map(ISO8601.string), now, id]
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

    // MARK: - Tags (metadata for management + colours)

    public func watchTags() throws -> AsyncThrowingStream<[Tag], Error> {
        try db.watch(
            sql: "SELECT * FROM \(TAGS_TABLE) ORDER BY name COLLATE NOCASE ASC",
            parameters: [],
            mapper: Self.mapTag
        )
    }

    /// Create any tags that don't already exist (case-insensitive by name), auto-colouring
    /// new ones. Idempotent — safe to call on every capture/confirm.
    static func ensureTags(db: PowerSyncDatabaseProtocol, ownerId: String, names: [String]) async {
        for name in TagsCodec.normalize(names) {
            let existing = try? await db.getOptional(
                sql: "SELECT id FROM \(TAGS_TABLE) WHERE name = ? COLLATE NOCASE",
                parameters: [name],
                mapper: { try $0.getString(name: "id") }
            )
            if existing != nil { continue }
            let now = ISO8601.string(Date())
            _ = try? await db.execute(
                sql: """
                INSERT INTO \(TAGS_TABLE) (id, owner_id, name, color, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                parameters: [UUID().uuidString.lowercased(), ownerId, name,
                             TagPalette.color(for: name), now, now]
            )
        }
    }

    @discardableResult
    public func createTag(name: String, color: String? = nil) async throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TagError.emptyName }
        if let existing = try await db.getOptional(
            sql: "SELECT id FROM \(TAGS_TABLE) WHERE name = ? COLLATE NOCASE",
            parameters: [trimmed],
            mapper: { try $0.getString(name: "id") }
        ) { return existing }
        let id = UUID().uuidString.lowercased()
        let now = ISO8601.string(Date())
        try await db.execute(
            sql: """
            INSERT INTO \(TAGS_TABLE) (id, owner_id, name, color, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            parameters: [id, ownerId, trimmed, color ?? TagPalette.color(for: trimmed), now, now]
        )
        return id
    }

    public func recolorTag(id: String, color: String) async throws {
        try await db.execute(
            sql: "UPDATE \(TAGS_TABLE) SET color = ?, updated_at = ? WHERE id = ?",
            parameters: [color, ISO8601.string(Date()), id]
        )
    }

    /// Rename a tag in its metadata row AND across every task whose JSON array contains the
    /// old name (best-effort, case-insensitive). Tasks key tags by name, so both must move.
    /// Renaming onto an existing tag MERGES into it (the unique(owner,lower(name)) index would
    /// otherwise be violated once the rows sync): tasks are rewritten and this row is removed.
    public func renameTag(id: String, to newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TagError.emptyName }
        let now = ISO8601.string(Date())
        let oldName = try await db.getOptional(
            sql: "SELECT name FROM \(TAGS_TABLE) WHERE id = ?",
            parameters: [id],
            mapper: { try $0.getString(name: "name") }
        )
        guard let oldName else { return }
        if TagPalette.key(oldName) == TagPalette.key(trimmed) {
            // Pure case change: keep the row, just fix the spelling everywhere.
            try await db.execute(
                sql: "UPDATE \(TAGS_TABLE) SET name = ?, updated_at = ? WHERE id = ?",
                parameters: [trimmed, now, id]
            )
            try await rewriteTagOnTasks(from: oldName, to: trimmed)
            return
        }
        let collision = try await db.getOptional(
            sql: "SELECT id FROM \(TAGS_TABLE) WHERE name = ? COLLATE NOCASE AND id <> ?",
            parameters: [trimmed, id],
            mapper: { try $0.getString(name: "id") }
        )
        if collision != nil {
            // Merge into the existing tag: move tasks over, drop this metadata row.
            try await rewriteTagOnTasks(from: oldName, to: trimmed)
            try await db.execute(sql: "DELETE FROM \(TAGS_TABLE) WHERE id = ?", parameters: [id])
        } else {
            try await db.execute(
                sql: "UPDATE \(TAGS_TABLE) SET name = ?, updated_at = ? WHERE id = ?",
                parameters: [trimmed, now, id]
            )
            try await rewriteTagOnTasks(from: oldName, to: trimmed)
        }
    }

    /// Delete a tag's metadata and strip it from every task's JSON array.
    public func deleteTag(id: String) async throws {
        let name = try await db.getOptional(
            sql: "SELECT name FROM \(TAGS_TABLE) WHERE id = ?",
            parameters: [id],
            mapper: { try $0.getString(name: "name") }
        )
        try await db.execute(sql: "DELETE FROM \(TAGS_TABLE) WHERE id = ?", parameters: [id])
        if let name { try await rewriteTagOnTasks(from: name, to: nil) }
    }

    /// Rewrite a tag name on every task that references it. `to == nil` removes it.
    private func rewriteTagOnTasks(from oldName: String, to newName: String?) async throws {
        let key = TagPalette.key(oldName)
        let rows = try await db.getAll(
            sql: "SELECT id, tags FROM \(TASKS_TABLE) WHERE tags LIKE ?",
            parameters: ["%\(oldName)%"],
            mapper: { (try $0.getString(name: "id"), try $0.getStringOptional(name: "tags")) }
        )
        let now = ISO8601.string(Date())
        for (taskId, rawTags) in rows {
            let current = TagsCodec.decode(rawTags)
            guard current.contains(where: { TagPalette.key($0) == key }) else { continue }
            var updated = current.filter { TagPalette.key($0) != key }
            if let newName { updated.append(newName) }
            try await db.execute(
                sql: "UPDATE \(TASKS_TABLE) SET tags = ?, updated_at = ? WHERE id = ?",
                parameters: [TagsCodec.encode(updated), now, taskId]
            )
        }
    }

    public enum TagError: Error { case emptyName }

    static func mapTag(_ cursor: SqlCursor) throws -> Tag {
        Tag(
            id: try cursor.getString(name: "id"),
            ownerId: (try cursor.getStringOptional(name: "owner_id")) ?? "",
            name: try cursor.getString(name: "name"),
            color: (try cursor.getStringOptional(name: "color")) ?? "#9BA1A6",
            createdAt: ISO8601.date(try cursor.getStringOptional(name: "created_at")),
            updatedAt: ISO8601.date(try cursor.getStringOptional(name: "updated_at"))
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
            tags: TagsCodec.decode(try cursor.getStringOptional(name: "tags")),
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
