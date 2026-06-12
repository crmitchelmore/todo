import Foundation
import PowerSync

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

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

    public enum AgentHandoffMode: String, Sendable {
        case research
        case attempt
    }

    public func connect() async throws {
        try await db.connect(connector: connector)
    }

    /// Restart the streaming sync connection while preserving local data and pending uploads.
    /// The PowerSync coordinator safely replaces an existing connection when `connect` is called,
    /// but explicitly disconnecting first clears a stale streaming task after network resets.
    public func reconnect() async throws {
        try await db.disconnect()
        try await db.connect(connector: connector)
    }

    public func disconnect() async throws {
        try await db.disconnect()
    }

    @discardableResult
    public func requestAgentHandoff(taskId: String, mode: AgentHandoffMode, instructions: String?) async throws -> String {
        guard let token = auth?.currentToken() else { throw CaptureError.auth("not signed in") }
        let url = config.backendURL
            .appendingPathComponent("api")
            .appendingPathComponent("tasks")
            .appendingPathComponent(taskId)
            .appendingPathComponent("agent-handoff")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.applyBearer(token)
        request.timeoutInterval = 20
        let cleanedInstructions = instructions?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let body: [String: Any] = [
            "mode": mode.rawValue,
            "instructions": cleanedInstructions ?? NSNull()
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CaptureError.upload("agent handoff failed: no response") }
        let decoded = try? JSONDecoder().decode(AgentHandoffResponse.self, from: data)
        guard (200..<300).contains(http.statusCode), decoded?.ok == true, let requestId = decoded?.requestId else {
            throw CaptureError.upload(decoded?.error ?? "agent handoff failed (\(http.statusCode))")
        }
        return requestId
    }

    /// Wipe the local SQLite DB and pending upload queue. Call on a real account boundary (sign-out,
    /// or sign-in as a *different* user) so one account's optimistic, not-yet-uploaded writes can
    /// never replay or leak into another account's synced view.
    public func resetLocalData() async throws {
        try await db.disconnectAndClear()
    }

    private struct AgentHandoffResponse: Decodable {
        let ok: Bool?
        let requestId: String?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case ok, error
            case requestId = "request_id"
        }
    }

    private static let lastOwnerKey = "capture.lastOwnerId"

    /// Prepare local storage for the currently signed-in user. Only wipes when the account actually
    /// changed since the last run — a normal relaunch with the same restored session keeps the local
    /// DB (and any pending offline writes) intact so they still upload. Does not connect.
    public func prepareForActiveUser() async {
        let current = ownerId
        let last = UserDefaults.standard.string(forKey: Self.lastOwnerKey)
        if let last {
            guard last != current else { return }
            do {
                try await resetLocalData()
                UserDefaults.standard.set(current, forKey: Self.lastOwnerKey)
            } catch {
                NSLog("[Capture] Failed to reset local data when switching users; preserving owner marker for retry: \(error)")
            }
            return
        }

        do {
            let existingOwners = try await localOwnerIds()
            if existingOwners.contains(where: { $0 != current }) {
                try? await resetLocalData()
            }
            UserDefaults.standard.set(current, forKey: Self.lastOwnerKey)
        } catch {
            NSLog("[Capture] Could not inspect local owners before activation; preserving local cache and owner marker for retry: \(error)")
        }
    }

    /// Clear local data on sign-out so the next account starts clean and the gate can't briefly show
    /// the previous user's rows.
    public func clearActiveUser() async {
        try? await resetLocalData()
        UserDefaults.standard.removeObject(forKey: Self.lastOwnerKey)
    }

    public func localSyncDiagnostics() async throws -> LocalSyncDiagnostics {
        let rows: [(status: String, count: Int, lastUpdatedAt: String?)] = try await db.getAll(
            sql: """
            SELECT status,
                   COUNT(*) AS count,
                   MAX(updated_at) AS last_updated_at
              FROM \(TASKS_TABLE)
             GROUP BY status
             ORDER BY status
            """,
            parameters: nil,
            mapper: { cursor in (
                try cursor.getString(name: "status"),
                (try cursor.getIntOptional(name: "count")) ?? 0,
                try cursor.getStringOptional(name: "last_updated_at")
            ) }
        )
        let ownerIds: [String] = try await db.getAll(
            sql: Self.localOwnerIdsSQL,
            parameters: nil,
            mapper: { try $0.getString(name: "owner_id") }
        )
        let byStatus = Dictionary(uniqueKeysWithValues: rows.map { ($0.status, $0.count) })
        let lastUpdatedAt = rows
            .compactMap { ISO8601.date($0.lastUpdatedAt) }
            .max()
        return LocalSyncDiagnostics(
            ownerId: auth?.ownerId ?? config.ownerId,
            endpoints: SyncDiagnosticsEndpoints(
                backendURL: config.backendURL.absoluteString,
                powersyncURL: config.powersyncURL.absoluteString
            ),
            counts: SyncTaskCounts(
                total: rows.reduce(0) { $0 + $1.count },
                proposed: byStatus["proposed"] ?? 0,
                active: (byStatus["active"] ?? 0) + (byStatus["confirmed"] ?? 0),
                done: byStatus["done"] ?? 0,
                cancelled: byStatus["cancelled"] ?? 0,
                byStatus: byStatus,
                lastUpdatedAt: lastUpdatedAt
            ),
            ownerIds: ownerIds
        )
    }

    private static var localOwnerIdsSQL: String {
        """
        SELECT DISTINCT owner_id
          FROM \(TASKS_TABLE)
         WHERE owner_id IS NOT NULL
         ORDER BY owner_id
         LIMIT 20
        """
    }

    private func localOwnerIds() async throws -> [String] {
        try await db.getAll(
            sql: """
            \(Self.localOwnerIdsSQL)
            """,
            parameters: nil,
            mapper: { try $0.getString(name: "owner_id") }
        )
    }

    // MARK: - Capture (hot path)

    /// Instant capture: generates an id, fires a local insert + background
    /// enrichment, and returns immediately. Never blocks on the network or an LLM.
    @discardableResult
    public func capture(_ raw: String, attachments: [TaskAttachmentDraft] = []) -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID().uuidString.lowercased()
        let effectiveTitle = title.isEmpty ? (attachments.first?.filename ?? "Image attachment") : title
        guard !effectiveTitle.isEmpty else { return id }
        let ownerId = self.ownerId
        Task.detached { [db] in
            let now = ISO8601.string(Date())
            _ = try? await db.execute(
                sql: """
                INSERT INTO \(TASKS_TABLE)
                    (id, owner_id, title, status, source, created_at, updated_at)
                VALUES (?, ?, ?, 'proposed', 'capture', ?, ?)
                """,
                parameters: [id, ownerId, effectiveTitle, now, now]
            )
            await Self.insertAttachments(db: db, ownerId: ownerId, taskId: id, attachments: attachments, createdAt: now)
            await Self.enrich(db: db, id: id, title: effectiveTitle)
        }
        return id
    }

    public func addAttachment(taskId: String, attachment: TaskAttachmentDraft) async throws {
        try await Self.insertAttachment(db: db, ownerId: ownerId, taskId: taskId, attachment: attachment, createdAt: ISO8601.string(Date()))
    }

    static func insertAttachments(
        db: PowerSyncDatabaseProtocol,
        ownerId: String,
        taskId: String,
        attachments: [TaskAttachmentDraft],
        createdAt: String
    ) async {
        for attachment in attachments {
            _ = try? await insertAttachment(db: db, ownerId: ownerId, taskId: taskId, attachment: attachment, createdAt: createdAt)
        }
    }

    static func insertAttachment(
        db: PowerSyncDatabaseProtocol,
        ownerId: String,
        taskId: String,
        attachment: TaskAttachmentDraft,
        createdAt: String
    ) async throws {
        guard attachment.byteSize > 0,
              attachment.byteSize <= 512 * 1024,
              attachment.previewDataURL.hasPrefix("data:\(attachment.mimeType);base64,")
        else { return }
        try await db.execute(
            sql: """
            INSERT INTO \(TASK_ATTACHMENTS_TABLE)
                (id, owner_id, task_id, filename, mime_type, byte_size, preview_data_url, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                UUID().uuidString.lowercased(),
                ownerId,
                taskId,
                attachment.filename?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                attachment.mimeType,
                attachment.byteSize,
                attachment.previewDataURL,
                createdAt
            ]
        )
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
        let prepared: [(sourceIndex: Int, id: String, item: ParsedCaptureItem)] = items.enumerated()
            .map { (sourceIndex: $0.offset, id: UUID().uuidString.lowercased(), item: $0.element) }
            .filter { !$0.item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !prepared.isEmpty else { return [] }
        let allTags = TagsCodec.normalize(prepared.flatMap { $0.item.tags })
        let ownerId = self.ownerId
        let idBySourceIndex = Dictionary(uniqueKeysWithValues: prepared.map { ($0.sourceIndex, $0.id) })
        Task.detached { [db] in
            await Self.ensureTags(db: db, ownerId: ownerId, names: allTags)
            for entry in prepared {
                let id = entry.id
                let item = entry.item
                let now = ISO8601.string(Date())
                let tagsJSON = TagsCodec.encode(item.tags)
                let parentId = item.parentIndex.flatMap { idBySourceIndex[$0] }
                if item.isDone {
                    _ = try? await db.execute(
                        sql: """
                        INSERT INTO \(TASKS_TABLE)
                            (id, owner_id, parent_task_id, title, status, category, tags, source,
                             created_at, updated_at, confirmed_at, completed_at)
                        VALUES (?, ?, ?, ?, 'done', NULL, ?, 'paste', ?, ?, ?, ?)
                        """,
                        parameters: [id, ownerId, parentId, item.title, tagsJSON, now, now, now, now]
                    )
                } else {
                    _ = try? await db.execute(
                        sql: """
                        INSERT INTO \(TASKS_TABLE)
                            (id, owner_id, parent_task_id, title, status, tags, source, created_at, updated_at)
                        VALUES (?, ?, ?, ?, 'proposed', ?, 'paste', ?, ?)
                        """,
                        parameters: [id, ownerId, parentId, item.title, tagsJSON, now, now]
                    )
                    await Self.enrich(db: db, id: id, title: item.title)
                }
            }
        }
        return prepared.map(\.id)
    }

    // MARK: - Confirm / reject / complete

    /// Promote a proposed item to an active todo after the human confirms its structure.
    public func confirm(
        id: String,
        title: String?,
        dueAt: Date?,
        category: String?,
        tags: [String]? = nil,
        notes: String? = nil,
        priority: Int? = nil
    ) async throws {
        let now = ISO8601.string(Date())
        if let tags { await Self.ensureTags(db: db, ownerId: ownerId, names: TagsCodec.normalize(tags)) }
        let safePriority = priority.flatMap { (0...4).contains($0) ? $0 : nil }
        try await db.execute(
            sql: """
            UPDATE \(TASKS_TABLE)
              SET status = 'active',
                   title = COALESCE(?, title),
                   notes = COALESCE(?, notes),
                   due_at = ?, category = ?, tags = COALESCE(?, tags),
                   priority = ?,
                   confirmed_at = ?, updated_at = ?
             WHERE id = ?
            """,
            parameters: [
               title,
               notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
               dueAt.map(ISO8601.string),
               category,
               tags.map { TagsCodec.encode($0) ?? "[]" },
               safePriority,
               now,
               now,
               id
            ]
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

    /// Consolidated detail-pane save: one write for the editable properties so inspectors do not
    /// create noisy per-keystroke sync traffic.
    public func updateTask(
        id: String,
        title: String?,
        notes: String?,
        dueAt: Date?,
        category: String?,
        tags: [String]?,
        priority: Int?
    ) async throws {
        if let tags { await Self.ensureTags(db: db, ownerId: ownerId, names: TagsCodec.normalize(tags)) }
        let safePriority = priority.flatMap { (0...4).contains($0) ? $0 : nil }
        let cleanedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await db.execute(
            sql: """
            UPDATE \(TASKS_TABLE)
               SET title = COALESCE(?, title),
                   notes = ?,
                   due_at = ?,
                   category = ?,
                   tags = COALESCE(?, tags),
                   priority = ?,
                   updated_at = ?
             WHERE id = ?
            """,
            parameters: [
                (cleanedTitle?.isEmpty == false) ? cleanedTitle : nil,
                notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                dueAt.map(ISO8601.string),
                category?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                tags.map { TagsCodec.encode($0) ?? "[]" },
                safePriority,
                ISO8601.string(Date()),
                id
            ]
        )
    }

    public func reject(id: String) async throws {
        let now = ISO8601.string(Date())
        try await db.execute(
            sql: "UPDATE \(TASKS_TABLE) SET status = 'cancelled', updated_at = ? WHERE id = ?",
            parameters: [now, id]
        )
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

    public func listProposed() async throws -> [TaskItem] {
        try await db.getAll(
            sql: "SELECT * FROM \(TASKS_TABLE) WHERE status = 'proposed' ORDER BY created_at DESC",
            parameters: [],
            mapper: Self.map
        )
    }

    public func watchActive() throws -> AsyncThrowingStream<[TaskItem], Error> {
        try db.watch(
            sql: """
            SELECT * FROM \(TASKS_TABLE) WHERE status IN ('active', 'confirmed')
            ORDER BY (due_at IS NULL), due_at ASC, created_at DESC
            """,
            parameters: [],
            mapper: Self.map
        )
    }

    public func listActive() async throws -> [TaskItem] {
        try await db.getAll(
            sql: """
            SELECT * FROM \(TASKS_TABLE) WHERE status IN ('active', 'confirmed')
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

    public func watchRejected() throws -> AsyncThrowingStream<[TaskItem], Error> {
        try db.watch(
            sql: "SELECT * FROM \(TASKS_TABLE) WHERE status = 'cancelled' ORDER BY updated_at DESC LIMIT 50",
            parameters: [],
            mapper: Self.map
        )
    }

    public func listRejected() async throws -> [TaskItem] {
        try await db.getAll(
            sql: "SELECT * FROM \(TASKS_TABLE) WHERE status = 'cancelled' ORDER BY updated_at DESC LIMIT 50",
            parameters: [],
            mapper: Self.map
        )
    }

    public func watchTask(id: String) throws -> AsyncThrowingStream<TaskItem?, Error> {
        let rows = try db.watch(
            sql: "SELECT * FROM \(TASKS_TABLE) WHERE id = ? LIMIT 1",
            parameters: [id],
            mapper: { try Self.map($0) }
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await batch in rows {
                        continuation.yield(batch.first)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func watchTaskEvents(taskId: String, limit: Int = 80) throws -> AsyncThrowingStream<[TaskEvent], Error> {
        try db.watch(
            sql: """
            SELECT * FROM \(TASK_EVENTS_TABLE)
             WHERE task_id = ?
             ORDER BY created_at DESC, id DESC
             LIMIT ?
            """,
            parameters: [taskId, limit],
            mapper: Self.mapTaskEvent
        )
    }

    public func watchTaskAndDescendantAttachments(taskId: String, limit: Int = 80) throws -> AsyncThrowingStream<[TaskAttachment], Error> {
        try db.watch(
            sql: """
            WITH RECURSIVE descendants(id) AS (
                SELECT id FROM \(TASKS_TABLE) WHERE parent_task_id = ?
                UNION ALL
                SELECT t.id
                  FROM \(TASKS_TABLE) t
                  JOIN descendants d ON t.parent_task_id = d.id
            ),
            root_attachments AS (
                SELECT *
                  FROM \(TASK_ATTACHMENTS_TABLE)
                 WHERE task_id = ?
                 ORDER BY created_at DESC, id DESC
                 LIMIT ?
            ),
            descendant_attachments AS (
                SELECT a.*
                  FROM \(TASK_ATTACHMENTS_TABLE) a
                  JOIN descendants d ON a.task_id = d.id
                 ORDER BY a.created_at DESC, a.id DESC
                 LIMIT ?
            )
            SELECT * FROM root_attachments
            UNION ALL
            SELECT * FROM descendant_attachments
            ORDER BY created_at DESC, id DESC
            """,
            parameters: [taskId, taskId, limit, limit],
            mapper: Self.mapTaskAttachment
        )
    }

    public func watchTaskRollup(taskId: String) throws -> AsyncThrowingStream<TaskRollup, Error> {
        let rows = try db.watch(
            sql: """
            WITH RECURSIVE descendants(id) AS (
                SELECT id FROM \(TASKS_TABLE) WHERE parent_task_id = ?
                UNION ALL
                SELECT t.id
                  FROM \(TASKS_TABLE) t
                  JOIN descendants d ON t.parent_task_id = d.id
            )
            SELECT
                COUNT(*) AS total,
                COALESCE(SUM(CASE WHEN status = 'done' THEN 1 ELSE 0 END), 0) AS done,
                COALESCE(SUM(CASE WHEN status NOT IN ('done', 'cancelled') THEN 1 ELSE 0 END), 0) AS open
              FROM \(TASKS_TABLE)
             WHERE id IN (SELECT id FROM descendants)
               AND status <> 'cancelled'
            """,
            parameters: [taskId],
            mapper: Self.mapTaskRollup
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await batch in rows {
                        continuation.yield(batch.first ?? .empty)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func watchTaskAndDescendantEvents(taskId: String, limit: Int = 80) throws -> AsyncThrowingStream<[TaskEvent], Error> {
        try db.watch(
            sql: """
            WITH RECURSIVE descendants(id, task_title, depth) AS (
                SELECT id, title, 1 FROM \(TASKS_TABLE) WHERE parent_task_id = ?
                UNION ALL
                SELECT t.id, t.title, d.depth + 1
                  FROM \(TASKS_TABLE) t
                  JOIN descendants d ON t.parent_task_id = d.id
            ),
            root_events AS (
                SELECT
                    e.id,
                    e.owner_id,
                    e.task_id,
                    e.actor,
                    e.event_type,
                    e.title,
                    e.body,
                    e.metadata,
                    e.created_at
                  FROM \(TASK_EVENTS_TABLE) e
                 WHERE e.task_id = ?
                 ORDER BY e.created_at DESC, e.id DESC
                 LIMIT ?
            ),
            descendant_events AS (
                SELECT
                    e.id,
                    e.owner_id,
                    e.task_id,
                    e.actor,
                    e.event_type,
                    d.task_title || ': ' || e.title AS title,
                    e.body,
                    e.metadata,
                    e.created_at
                  FROM \(TASK_EVENTS_TABLE) e
                  JOIN descendants d ON e.task_id = d.id
                 ORDER BY e.created_at DESC, e.id DESC
                 LIMIT ?
            )
            SELECT * FROM root_events
            UNION ALL
            SELECT * FROM descendant_events
            ORDER BY created_at DESC, id DESC
            """,
            parameters: [taskId, taskId, limit, limit],
            mapper: Self.mapTaskEvent
        )
    }

    // MARK: - Tags (metadata for management + colours)

    public func watchCategories() throws -> AsyncThrowingStream<[TaskCategory], Error> {
        try db.watch(
            sql: "SELECT * FROM \(CATEGORIES_TABLE) ORDER BY name COLLATE NOCASE ASC",
            parameters: [],
            mapper: Self.mapCategory
        )
    }

    @discardableResult
    public func createCategory(name: String, color: String? = nil) async throws -> String {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !trimmed.isEmpty else { throw CategoryError.emptyName }
        if let existing = try await db.getOptional(
            sql: "SELECT id FROM \(CATEGORIES_TABLE) WHERE name = ? COLLATE NOCASE",
            parameters: [trimmed],
            mapper: { try $0.getString(name: "id") }
        ) { return existing }
        let id = UUID().uuidString.lowercased()
        let now = ISO8601.string(Date())
        try await db.execute(
            sql: """
            INSERT INTO \(CATEGORIES_TABLE) (id, owner_id, name, color, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            parameters: [id, ownerId, trimmed, color ?? CategoryPalette.color(for: trimmed), now, now]
        )
        return id
    }

    public func recolorCategory(id: String, color: String) async throws {
        try await db.execute(
            sql: "UPDATE \(CATEGORIES_TABLE) SET color = ?, updated_at = ? WHERE id = ?",
            parameters: [color, ISO8601.string(Date()), id]
        )
    }

    public func renameCategory(id: String, to newName: String) async throws {
        let trimmed = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !trimmed.isEmpty else { throw CategoryError.emptyName }
        let now = ISO8601.string(Date())
        let oldName = try await db.getOptional(
            sql: "SELECT name FROM \(CATEGORIES_TABLE) WHERE id = ?",
            parameters: [id],
            mapper: { try $0.getString(name: "name") }
        )
        guard let oldName else { return }
        if CategoryPalette.key(oldName) == CategoryPalette.key(trimmed) {
            try await db.execute(
                sql: "UPDATE \(CATEGORIES_TABLE) SET name = ?, updated_at = ? WHERE id = ?",
                parameters: [trimmed, now, id]
            )
            try await rewriteCategoryOnTasks(from: oldName, to: trimmed)
            return
        }
        let collision = try await db.getOptional(
            sql: "SELECT id FROM \(CATEGORIES_TABLE) WHERE name = ? COLLATE NOCASE AND id <> ?",
            parameters: [trimmed, id],
            mapper: { try $0.getString(name: "id") }
        )
        if collision != nil {
            try await rewriteCategoryOnTasks(from: oldName, to: trimmed)
            try await db.execute(sql: "DELETE FROM \(CATEGORIES_TABLE) WHERE id = ?", parameters: [id])
        } else {
            try await db.execute(
                sql: "UPDATE \(CATEGORIES_TABLE) SET name = ?, updated_at = ? WHERE id = ?",
                parameters: [trimmed, now, id]
            )
            try await rewriteCategoryOnTasks(from: oldName, to: trimmed)
        }
    }

    public func deleteCategory(id: String) async throws {
        let name = try await db.getOptional(
            sql: "SELECT name FROM \(CATEGORIES_TABLE) WHERE id = ?",
            parameters: [id],
            mapper: { try $0.getString(name: "name") }
        )
        try await db.execute(sql: "DELETE FROM \(CATEGORIES_TABLE) WHERE id = ?", parameters: [id])
        if let name { try await rewriteCategoryOnTasks(from: name, to: nil) }
    }

    private func rewriteCategoryOnTasks(from oldName: String, to newName: String?) async throws {
        try await db.execute(
            sql: """
            UPDATE \(TASKS_TABLE)
               SET category = ?, updated_at = ?
             WHERE category = ? COLLATE NOCASE
            """,
            parameters: [newName, ISO8601.string(Date()), oldName]
        )
        try await db.execute(
            sql: """
            UPDATE \(CATEGORISATION_RULES_TABLE)
               SET category = ?, updated_at = ?
             WHERE category = ? COLLATE NOCASE
            """,
            parameters: [newName, ISO8601.string(Date()), oldName]
        )
    }

    // MARK: - Categorisation rules

    public func watchCategorisationRules() throws -> AsyncThrowingStream<[CategorisationRule], Error> {
        try db.watch(
            sql: "SELECT * FROM \(CATEGORISATION_RULES_TABLE) ORDER BY enabled DESC, updated_at DESC, title COLLATE NOCASE ASC",
            parameters: [],
            mapper: Self.mapCategorisationRule
        )
    }

    @discardableResult
    public func createCategorisationRule(
        title: String,
        instructions: String,
        category: String?,
        tags: [String],
        enabled: Bool = true
    ) async throws -> String {
        let cleaned = Self.cleanRule(title: title, instructions: instructions, category: category, tags: tags)
        guard let cleaned else { throw CategorisationRuleError.emptyRule }
        let id = UUID().uuidString.lowercased()
        let now = ISO8601.string(Date())
        try await db.execute(
            sql: """
            INSERT INTO \(CATEGORISATION_RULES_TABLE)
              (id, owner_id, title, instructions, category, tags, enabled, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                id, ownerId, cleaned.title, cleaned.instructions, cleaned.category,
                TagsCodec.encode(cleaned.tags), enabled ? 1 : 0, now, now
            ]
        )
        return id
    }

    public func updateCategorisationRule(
        id: String,
        title: String,
        instructions: String,
        category: String?,
        tags: [String],
        enabled: Bool
    ) async throws {
        guard let cleaned = Self.cleanRule(title: title, instructions: instructions, category: category, tags: tags) else {
            throw CategorisationRuleError.emptyRule
        }
        try await db.execute(
            sql: """
            UPDATE \(CATEGORISATION_RULES_TABLE)
               SET title = ?, instructions = ?, category = ?, tags = ?, enabled = ?, updated_at = ?
             WHERE id = ?
            """,
            parameters: [
                cleaned.title, cleaned.instructions, cleaned.category, TagsCodec.encode(cleaned.tags),
                enabled ? 1 : 0, ISO8601.string(Date()), id
            ]
        )
    }

    public func deleteCategorisationRule(id: String) async throws {
        try await db.execute(sql: "DELETE FROM \(CATEGORISATION_RULES_TABLE) WHERE id = ?", parameters: [id])
    }

    private static func cleanRule(title: String, instructions: String, category: String?, tags: [String]) -> (title: String, instructions: String, category: String?, tags: [String])? {
        let cleanedTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        let cleanedInstructions = String(instructions.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !cleanedTitle.isEmpty, !cleanedInstructions.isEmpty else { return nil }
        let cleanedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty.map { String($0.prefix(80)) }
        return (cleanedTitle, cleanedInstructions, cleanedCategory, TagsCodec.normalize(tags).map { String($0.prefix(80)) })
    }

    // MARK: - User memories

    public func watchUserMemories(includeDeleted: Bool = false) throws -> AsyncThrowingStream<[UserMemory], Error> {
        try db.watch(
            sql: """
            SELECT * FROM \(USER_MEMORIES_TABLE)
             WHERE (? = 1 OR status <> 'deleted')
             ORDER BY status ASC, updated_at DESC, content COLLATE NOCASE ASC
            """,
            parameters: [includeDeleted ? 1 : 0],
            mapper: Self.mapUserMemory
        )
    }

    @discardableResult
    public func createUserMemory(
        content: String,
        domain: String? = nil,
        source: UserMemorySource = .manual,
        confidence: Double = 1,
        tags: [String] = [],
        expiresAt: Date? = nil,
        status: UserMemoryStatus = .active
    ) async throws -> String {
        guard let cleaned = Self.cleanMemory(content: content, domain: domain, confidence: confidence, tags: tags, status: status) else {
            throw UserMemoryError.emptyContent
        }
        let id = UUID().uuidString.lowercased()
        let now = ISO8601.string(Date())
        let deletedAt = cleaned.status == .deleted ? now : nil
        try await db.execute(
            sql: """
            INSERT INTO \(USER_MEMORIES_TABLE)
              (id, owner_id, content, domain, source, confidence, tags, status, expires_at, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                id, ownerId, cleaned.content, cleaned.domain, source.rawValue, cleaned.confidence,
                TagsCodec.encode(cleaned.tags), cleaned.status.rawValue, expiresAt.map(ISO8601.string),
                now, now, deletedAt
            ]
        )
        return id
    }

    public func updateUserMemory(
        id: String,
        content: String,
        domain: String?,
        source: UserMemorySource,
        confidence: Double,
        tags: [String],
        expiresAt: Date?,
        status: UserMemoryStatus
    ) async throws {
        guard let cleaned = Self.cleanMemory(content: content, domain: domain, confidence: confidence, tags: tags, status: status) else {
            throw UserMemoryError.emptyContent
        }
        let deletedAt = cleaned.status == .deleted ? ISO8601.string(Date()) : nil
        try await db.execute(
            sql: """
            UPDATE \(USER_MEMORIES_TABLE)
               SET content = ?, domain = ?, source = ?, confidence = ?, tags = ?, status = ?,
                   expires_at = ?, updated_at = ?, deleted_at = ?
             WHERE id = ?
            """,
            parameters: [
                cleaned.content, cleaned.domain, source.rawValue, cleaned.confidence,
                TagsCodec.encode(cleaned.tags), cleaned.status.rawValue, expiresAt.map(ISO8601.string),
                ISO8601.string(Date()), deletedAt, id
            ]
        )
    }

    public func setUserMemoryStatus(id: String, status: UserMemoryStatus) async throws {
        let now = ISO8601.string(Date())
        try await db.execute(
            sql: "UPDATE \(USER_MEMORIES_TABLE) SET status = ?, updated_at = ?, deleted_at = ? WHERE id = ?",
            parameters: [status.rawValue, now, status == .deleted ? now : nil, id]
        )
    }

    public func deleteUserMemory(id: String) async throws {
        try await setUserMemoryStatus(id: id, status: .deleted)
    }

    static func cleanMemory(content: String, domain: String?, confidence: Double, tags: [String], status: UserMemoryStatus) -> (content: String, domain: String?, confidence: Double, tags: [String], status: UserMemoryStatus)? {
        let cleanedContent = String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !cleanedContent.isEmpty else { return nil }
        let cleanedDomain = (domain?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty).map { String($0.prefix(80)) }
        return (
            cleanedContent,
            cleanedDomain,
            min(1, max(0, confidence)),
            TagsCodec.normalize(tags).map { String($0.prefix(80)) },
            status
        )
    }

    public func watchAgentDevices() throws -> AsyncThrowingStream<[AgentDevice], Error> {
        try db.watch(
            sql: """
            SELECT * FROM \(AGENT_DEVICES_TABLE)
             ORDER BY is_selected_backend DESC, status ASC, last_seen_at DESC, updated_at DESC, device_name COLLATE NOCASE ASC
            """,
            parameters: [],
            mapper: Self.mapAgentDevice
        )
    }

    @discardableResult
    public func upsertAgentDevice(
        id: String = UUID().uuidString.lowercased(),
        deviceName: String = "Mac",
        platform: String = "macos",
        harnessKind: AgentHarnessKind? = nil,
        harnessLabel: String? = nil,
        capabilities: [String] = [],
        selectedBackend: Bool = false
    ) async throws -> String {
        let now = ISO8601.string(Date())
        let cleanedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Mac"
        let cleanedPlatform = platform.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "macos"
        if selectedBackend {
            try await db.execute(
                sql: "UPDATE \(AGENT_DEVICES_TABLE) SET is_selected_backend = 0, updated_at = ? WHERE owner_id = ? AND id <> ?",
                parameters: [now, ownerId, id]
            )
        }
        let name = String(cleanedName.prefix(120))
        let platform = String(cleanedPlatform.prefix(40))
        let label = harnessLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty.map { String($0.prefix(120)) }
        let encodedCapabilities = TagsCodec.encode(capabilities)
        let existing = try await db.getOptional(
            sql: "SELECT id FROM \(AGENT_DEVICES_TABLE) WHERE id = ? AND owner_id = ? LIMIT 1",
            parameters: [id, ownerId],
            mapper: { try $0.getString(name: "id") }
        )
        if existing != nil {
            try await db.execute(
                sql: """
                UPDATE \(AGENT_DEVICES_TABLE)
                   SET device_name = ?,
                       platform = ?,
                       status = 'active',
                       is_selected_backend = ?,
                       harness_kind = ?,
                       harness_label = ?,
                       capabilities = ?,
                       last_seen_at = ?,
                       updated_at = ?
                 WHERE id = ? AND owner_id = ?
                """,
                parameters: [
                    name,
                    platform,
                    selectedBackend ? 1 : 0,
                    harnessKind?.rawValue,
                    label,
                    encodedCapabilities,
                    now,
                    now,
                    id,
                    ownerId
                ]
            )
        } else {
            try await db.execute(
                sql: """
                INSERT INTO \(AGENT_DEVICES_TABLE)
                    (id, owner_id, device_name, platform, status, is_selected_backend, harness_kind, harness_label, capabilities, last_seen_at, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?)
                """,
                parameters: [
                    id,
                    ownerId,
                    name,
                    platform,
                    selectedBackend ? 1 : 0,
                    harnessKind?.rawValue,
                    label,
                    encodedCapabilities,
                    now,
                    now,
                    now
                ]
            )
        }
        return id
    }

    public func selectAgentBackendDevice(id: String) async throws {
        let now = ISO8601.string(Date())
        try await db.execute(sql: "UPDATE \(AGENT_DEVICES_TABLE) SET is_selected_backend = 0, updated_at = ? WHERE owner_id = ?", parameters: [now, ownerId])
        try await db.execute(
            sql: "UPDATE \(AGENT_DEVICES_TABLE) SET is_selected_backend = 1, status = 'active', updated_at = ? WHERE id = ? AND owner_id = ?",
            parameters: [now, id, ownerId]
        )
    }

    public func disableAgentDevice(id: String) async throws {
        try await db.execute(
            sql: "UPDATE \(AGENT_DEVICES_TABLE) SET status = 'disabled', is_selected_backend = 0, updated_at = ? WHERE id = ? AND owner_id = ?",
            parameters: [ISO8601.string(Date()), id, ownerId]
        )
    }

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
        try await rewriteTagOnCategorisationRules(from: oldName, to: newName)
    }

    private func rewriteTagOnCategorisationRules(from oldName: String, to newName: String?) async throws {
        let key = TagPalette.key(oldName)
        let rows = try await db.getAll(
            sql: "SELECT id, tags FROM \(CATEGORISATION_RULES_TABLE) WHERE tags LIKE ?",
            parameters: ["%\(oldName)%"],
            mapper: { (try $0.getString(name: "id"), try $0.getStringOptional(name: "tags")) }
        )
        let now = ISO8601.string(Date())
        for (ruleId, rawTags) in rows {
            let current = TagsCodec.decode(rawTags)
            guard current.contains(where: { TagPalette.key($0) == key }) else { continue }
            var updated = current.filter { TagPalette.key($0) != key }
            if let newName { updated.append(newName) }
            try await db.execute(
                sql: "UPDATE \(CATEGORISATION_RULES_TABLE) SET tags = ?, updated_at = ? WHERE id = ?",
                parameters: [TagsCodec.encode(updated), now, ruleId]
            )
        }
    }

    public enum TagError: Error { case emptyName }
    public enum CategoryError: Error { case emptyName }
    public enum CategorisationRuleError: Error { case emptyRule }
    public enum UserMemoryError: Error { case emptyContent }

    static func mapCategory(_ cursor: SqlCursor) throws -> TaskCategory {
        let name = try cursor.getString(name: "name")
        return TaskCategory(
            id: try cursor.getString(name: "id"),
            ownerId: (try cursor.getStringOptional(name: "owner_id")) ?? "",
            name: name,
            color: (try cursor.getStringOptional(name: "color")) ?? CategoryPalette.color(for: name),
            createdAt: ISO8601.date(try cursor.getStringOptional(name: "created_at")),
            updatedAt: ISO8601.date(try cursor.getStringOptional(name: "updated_at"))
        )
    }

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

    static func mapCategorisationRule(_ cursor: SqlCursor) throws -> CategorisationRule {
        CategorisationRule(
            id: try cursor.getString(name: "id"),
            ownerId: (try cursor.getStringOptional(name: "owner_id")) ?? "",
            title: try cursor.getString(name: "title"),
            instructions: try cursor.getString(name: "instructions"),
            category: try cursor.getStringOptional(name: "category"),
            tags: TagsCodec.decode(try cursor.getStringOptional(name: "tags")),
            enabled: ((try cursor.getIntOptional(name: "enabled")) ?? 1) != 0,
            createdAt: ISO8601.date(try cursor.getStringOptional(name: "created_at")),
            updatedAt: ISO8601.date(try cursor.getStringOptional(name: "updated_at"))
        )
    }

    static func mapUserMemory(_ cursor: SqlCursor) throws -> UserMemory {
        let sourceRaw = (try cursor.getStringOptional(name: "source")) ?? UserMemorySource.manual.rawValue
        let statusRaw = (try cursor.getStringOptional(name: "status")) ?? UserMemoryStatus.active.rawValue
        return UserMemory(
            id: try cursor.getString(name: "id"),
            ownerId: (try cursor.getStringOptional(name: "owner_id")) ?? "",
            content: try cursor.getString(name: "content"),
            domain: try cursor.getStringOptional(name: "domain"),
            source: UserMemorySource(rawValue: sourceRaw) ?? .manual,
            confidence: (try cursor.getDoubleOptional(name: "confidence")) ?? 1,
            tags: TagsCodec.decode(try cursor.getStringOptional(name: "tags")),
            status: UserMemoryStatus(rawValue: statusRaw) ?? .active,
            expiresAt: ISO8601.date(try cursor.getStringOptional(name: "expires_at")),
            createdAt: ISO8601.date(try cursor.getStringOptional(name: "created_at")),
            updatedAt: ISO8601.date(try cursor.getStringOptional(name: "updated_at")),
            deletedAt: ISO8601.date(try cursor.getStringOptional(name: "deleted_at"))
        )
    }

    static func mapAgentDevice(_ cursor: SqlCursor) throws -> AgentDevice {
        let statusRaw = (try cursor.getStringOptional(name: "status")) ?? AgentDeviceStatus.active.rawValue
        let harnessRaw = try cursor.getStringOptional(name: "harness_kind")
        return AgentDevice(
            id: try cursor.getString(name: "id"),
            ownerId: (try cursor.getStringOptional(name: "owner_id")) ?? "",
            deviceName: try cursor.getString(name: "device_name"),
            platform: (try cursor.getStringOptional(name: "platform")) ?? "macos",
            status: AgentDeviceStatus(rawValue: statusRaw) ?? .active,
            isSelectedBackend: ((try cursor.getIntOptional(name: "is_selected_backend")) ?? 0) == 1,
            harnessKind: harnessRaw.flatMap(AgentHarnessKind.init(rawValue:)),
            harnessLabel: try cursor.getStringOptional(name: "harness_label"),
            capabilities: TagsCodec.decode(try cursor.getStringOptional(name: "capabilities")),
            lastSeenAt: ISO8601.date(try cursor.getStringOptional(name: "last_seen_at")),
            createdAt: ISO8601.date(try cursor.getStringOptional(name: "created_at")),
            updatedAt: ISO8601.date(try cursor.getStringOptional(name: "updated_at"))
        )
    }

    static func mapTaskEvent(_ cursor: SqlCursor) throws -> TaskEvent {
        TaskEvent(
            id: try cursor.getString(name: "id"),
            ownerId: (try cursor.getStringOptional(name: "owner_id")) ?? "",
            taskId: try cursor.getString(name: "task_id"),
            actor: try cursor.getString(name: "actor"),
            eventType: try cursor.getString(name: "event_type"),
            title: try cursor.getString(name: "title"),
            body: try cursor.getStringOptional(name: "body"),
            metadata: try cursor.getStringOptional(name: "metadata"),
            createdAt: ISO8601.date(try cursor.getStringOptional(name: "created_at"))
        )
    }

    static func mapTaskAttachment(_ cursor: SqlCursor) throws -> TaskAttachment {
        TaskAttachment(
            id: try cursor.getString(name: "id"),
            ownerId: (try cursor.getStringOptional(name: "owner_id")) ?? "",
            taskId: try cursor.getString(name: "task_id"),
            filename: try cursor.getStringOptional(name: "filename"),
            mimeType: try cursor.getString(name: "mime_type"),
            byteSize: (try cursor.getIntOptional(name: "byte_size")) ?? 0,
            previewDataURL: try cursor.getString(name: "preview_data_url"),
            createdAt: ISO8601.date(try cursor.getStringOptional(name: "created_at"))
        )
    }

    static func mapTaskRollup(_ cursor: SqlCursor) throws -> TaskRollup {
        TaskRollup(
            total: (try cursor.getIntOptional(name: "total")) ?? 0,
            done: (try cursor.getIntOptional(name: "done")) ?? 0,
            open: (try cursor.getIntOptional(name: "open")) ?? 0
        )
    }

    static func map(_ cursor: SqlCursor) throws -> TaskItem {
        TaskItem(
            id: try cursor.getString(name: "id"),
            ownerId: (try cursor.getStringOptional(name: "owner_id")) ?? "",
            parentTaskId: try cursor.getStringOptional(name: "parent_task_id"),
            title: try cursor.getString(name: "title"),
            notes: try cursor.getStringOptional(name: "notes"),
            status: TaskStatus(rawValue: try cursor.getString(name: "status")) ?? .proposed,
            category: try cursor.getStringOptional(name: "category"),
            tags: TagsCodec.decode(try cursor.getStringOptional(name: "tags")),
            dueAt: ISO8601.date(try cursor.getStringOptional(name: "due_at")),
            priority: try cursor.getIntOptional(name: "priority"),
            githubRepo: try cursor.getStringOptional(name: "github_repo"),
            githubURL: try cursor.getStringOptional(name: "github_url"),
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
