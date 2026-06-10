import AppKit
import CaptureCore

/// A row in the Mac active list: either a date-bucket section header or a task.
enum MacActiveRow {
    case header(label: String, count: Int)
    case task(TaskItem)
    case rejected(TaskItem)
}

@MainActor
final class MacViewModel {
    let store: TaskStore
    let auth: AuthStore
    private(set) var proposed: [TaskItem] = []
    private(set) var active: [TaskItem] = []
    private(set) var rejected: [TaskItem] = []
    private(set) var allTags: [Tag] = []
    private(set) var allCategories: [TaskCategory] = []
    private(set) var tagColors: [String: String] = [:]   // lowercased name -> hex
    private(set) var tagFilter: Set<String> = []          // lowercased names; AND semantics
    private(set) var selectedTask: TaskItem?
    private(set) var selectedEvents: [TaskEvent] = []
    private(set) var selectedAttachments: [TaskAttachment] = []
    private(set) var selectedRollup: TaskRollup = .empty

    private var observers: [() -> Void] = []
    private var started = false
    private var tasks: [Task<Void, Never>] = []
    private var detailTasks: [Task<Void, Never>] = []
    private var lastSyncRestart: Date?

    init(auth: AuthStore, config: CaptureConfig = .fromEnvironment()) {
        self.auth = auth
        self.store = TaskStore(config: config, auth: auth)
    }

    /// Register a change observer. Multiple surfaces (main window, quick panel, status item)
    /// share one store/PowerSync instance, so changes must fan out to all of them.
    func addObserver(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    private func notify() { observers.forEach { $0() } }

    func start() {
        guard !started else { return } // single shared store: only connect/watch once
        started = true
        refreshTaskSnapshots(reason: "startup")
        Task {
            do {
                try await store.connect()
                NSLog("[Capture] PowerSync connected")
                refreshTaskSnapshots(reason: "connect")
            } catch {
                NSLog("[Capture] PowerSync connect failed: \(error)")
            }
        }
        watch("proposed", { try self.store.watchProposed() }, assign: { self.proposed = $0 })
        watch("active", { try self.store.watchActive() }, assign: { self.active = $0 })
        watch("rejected", { try self.store.watchRejected() }, assign: { self.rejected = $0 })
        watchTags()
        watchCategories()
    }

    func restartSyncIfNeeded(reason: String) {
        guard started, auth.isAuthenticated else { return }
        let now = Date()
        if let lastSyncRestart, now.timeIntervalSince(lastSyncRestart) < 15 { return }
        lastSyncRestart = now
        Task {
            do {
                try await store.reconnect()
                NSLog("[Capture] PowerSync reconnected: \(reason)")
                refreshTaskSnapshots(reason: "reconnect")
            } catch {
                NSLog("[Capture] PowerSync reconnect failed (\(reason)): \(error)")
            }
        }
    }

    private func refreshTaskSnapshots(reason: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                async let proposedRows = self.store.listProposed()
                async let activeRows = self.store.listActive()
                async let rejectedRows = self.store.listRejected()
                let (nextProposed, nextActive, nextRejected) = try await (proposedRows, activeRows, rejectedRows)
                await MainActor.run {
                    self.proposed = nextProposed
                    self.active = nextActive
                    self.rejected = nextRejected
                    NSLog("[Capture] Loaded task snapshot (\(reason)): proposed=\(nextProposed.count) active=\(nextActive.count) rejected=\(nextRejected.count)")
                    self.notify()
                }
            } catch {
                NSLog("[Capture] Task snapshot failed (\(reason)): \(error)")
            }
        }
    }

    private func watchTags() {
        let t = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.store.watchTags() {
                    await MainActor.run {
                        self.allTags = rows
                        self.tagColors = Dictionary(
                            rows.map { ($0.name.lowercased(), $0.color) },
                            uniquingKeysWith: { a, _ in a }
                        )
                        // Drop any filter selections whose tag no longer exists.
                        let names = Set(rows.map { $0.name.lowercased() })
                        self.tagFilter.formIntersection(names)
                        self.notify()
                    }
                }
            } catch {
                NSLog("[Capture] Tag watch failed: \(error)")
            }
        }
        tasks.append(t)
    }

    private func watchCategories() {
        let t = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.store.watchCategories() {
                    await MainActor.run {
                        self.allCategories = rows
                        self.notify()
                    }
                }
            } catch {
                NSLog("[Capture] Category watch failed: \(error)")
            }
        }
        tasks.append(t)
    }

    /// Colour for a tag chip — user-chosen if known, else the deterministic palette colour
    /// (matches the web fallback) so chips look consistent before metadata syncs.
    func color(forTag name: String) -> String {
        tagColors[name.lowercased()] ?? TagPalette.color(for: name)
    }

    // MARK: - Tag filtering ("slice by tag or multiple tags", AND/intersection)

    func toggleFilter(_ name: String) {
        let key = name.lowercased()
        if tagFilter.contains(key) { tagFilter.remove(key) } else { tagFilter.insert(key) }
        notify()
    }

    func clearFilter() {
        guard !tagFilter.isEmpty else { return }
        tagFilter.removeAll()
        notify()
    }

    func isFiltering(_ name: String) -> Bool { tagFilter.contains(name.lowercased()) }

    private func matchesFilter(_ item: TaskItem) -> Bool {
        guard !tagFilter.isEmpty else { return true }
        let have = Set(item.tags.map { $0.lowercased() })
        return tagFilter.allSatisfy { have.contains($0) }
    }

    var filteredActiveCount: Int { active.filter(matchesFilter).count }

    /// The active list filtered by the tag selection and grouped into date buckets, flattened
    /// into header + task rows for the table.
    var activeRows: [MacActiveRow] {
        let items = active.filter(matchesFilter)
        var byBucket: [DateBucket: [TaskItem]] = [:]
        for item in items {
            byBucket[DateGrouping.bucket(for: item.dueAt), default: []].append(item)
        }
        var rows: [MacActiveRow] = []
        for bucket in DateBucket.allCases {
            guard let group = byBucket[bucket], !group.isEmpty else { continue }
            rows.append(.header(label: bucket.label, count: group.count))
            rows.append(contentsOf: group.map { .task($0) })
        }
        let rejectedItems = rejected.filter(matchesFilter)
        if !rejectedItems.isEmpty {
            rows.append(.header(label: "Rejected", count: rejectedItems.count))
            rows.append(contentsOf: rejectedItems.map { .rejected($0) })
        }
        return rows
    }

    private func watch(
        _ label: String,
        _ make: @escaping () throws -> AsyncThrowingStream<[TaskItem], Error>,
        assign: @escaping ([TaskItem]) -> Void
    ) {
        let t = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try make() {
                    await MainActor.run {
                        assign(rows)
                        self.notify()
                    }
                }
            } catch {
                NSLog("[Capture] \(label) watch failed: \(error)")
                await MainActor.run { self.refreshTaskSnapshots(reason: "\(label) watch failed") }
            }
        }
        tasks.append(t)
    }

    func capture(_ text: String, attachments: [TaskAttachmentDraft] = []) {
        if ingestIfList(text) { return }
        store.capture(text, attachments: attachments)
    }

    /// If `text` is a markdown / checkbox list, ingest each line as its own item (nested lines
    /// become parent-linked subtasks with compatibility tags; `[x]` items import as done).
    /// Returns true if it was a list.
    @discardableResult
    func ingestIfList(_ text: String) -> Bool {
        guard let items = store.detectList(text) else { return false }
        store.captureBatch(items)
        return true
    }

    func confirm(_ item: TaskItem) {
        // Quick path: accept on-device suggestions as-is.
        Task {
            try? await store.confirm(
                id: item.id,
                title: item.title,
                dueAt: item.suggestedDueAt,
                category: item.suggestedCategory,
                tags: item.tags
            )
            self.refreshTaskSnapshots(reason: "confirm")
        }
    }

    func select(_ item: TaskItem) {
        guard selectedTask?.id != item.id else { return }
        detailTasks.forEach { $0.cancel() }
        detailTasks.removeAll()
        selectedTask = item
        selectedEvents = []
        selectedAttachments = []
        selectedRollup = .empty
        notify()
        watchSelectedTask(id: item.id)
        watchSelectedRollup(id: item.id)
        watchSelectedEvents(id: item.id)
        watchSelectedAttachments(id: item.id)
    }

    func clearSelection() {
        detailTasks.forEach { $0.cancel() }
        detailTasks.removeAll()
        selectedTask = nil
        selectedEvents = []
        selectedAttachments = []
        selectedRollup = .empty
        notify()
    }

    private func watchSelectedTask(id: String) {
        let t = Task { [weak self] in
            guard let self else { return }
            do {
                for try await task in try self.store.watchTask(id: id) {
                    await MainActor.run {
                        guard self.selectedTask?.id == id else { return }
                        self.selectedTask = task
                        if task == nil {
                            self.selectedEvents = []
                            self.selectedRollup = .empty
                        }
                        self.notify()
                    }
                }
            } catch {}
        }
        detailTasks.append(t)
    }

    private func watchSelectedRollup(id: String) {
        let t = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rollup in try self.store.watchTaskRollup(taskId: id) {
                    await MainActor.run {
                        guard self.selectedTask?.id == id else { return }
                        self.selectedRollup = rollup
                        self.notify()
                    }
                }
            } catch {}
        }
        detailTasks.append(t)
    }

    private func watchSelectedEvents(id: String) {
        let t = Task { [weak self] in
            guard let self else { return }
            do {
                for try await events in try self.store.watchTaskAndDescendantEvents(taskId: id) {
                    await MainActor.run {
                        guard self.selectedTask?.id == id else { return }
                        self.selectedEvents = events
                        self.notify()
                    }
                }
            } catch {}
        }
        detailTasks.append(t)
    }

    private func watchSelectedAttachments(id: String) {
        let t = Task { [weak self] in
            guard let self else { return }
            do {
                for try await attachments in try self.store.watchTaskAndDescendantAttachments(taskId: id) {
                    await MainActor.run {
                        guard self.selectedTask?.id == id else { return }
                        self.selectedAttachments = attachments
                        self.notify()
                    }
                }
            } catch {}
        }
        detailTasks.append(t)
    }

    func saveDetail(_ form: MacTaskDetailForm) {
        guard let item = selectedTask else { return }
        Task {
            try? await store.updateTask(
                id: item.id,
                title: form.title,
                notes: form.notes,
                dueAt: form.dueAt,
                category: form.category,
                tags: form.tags,
                priority: form.priority
            )
        }
    }

    func confirmDetail(_ form: MacTaskDetailForm) {
        guard let item = selectedTask else { return }
        Task {
            try? await store.updateTask(
                id: item.id,
                title: form.title,
                notes: form.notes,
                dueAt: form.dueAt,
                category: form.category,
                tags: form.tags,
                priority: form.priority
            )
            try? await store.confirm(
                id: item.id,
                title: form.title,
                dueAt: form.dueAt,
                category: form.category,
                tags: form.tags,
                notes: form.notes,
                priority: form.priority
            )
        }
    }

    func reject(_ item: TaskItem) {
        Task {
            try? await store.reject(id: item.id)
            self.refreshTaskSnapshots(reason: "reject")
        }
    }

    func rejectSelected() {
        guard let item = selectedTask else { return }
        clearSelection()
        reject(item)
    }

    func setDone(_ item: TaskItem, _ done: Bool) {
        Task { try? await store.setDone(id: item.id, done: done) }
    }

    /// Set or clear a task's due date (inline date editing on an active row).
    func setDue(_ item: TaskItem, _ date: Date?) {
        Task { try? await store.setDue(id: item.id, dueAt: date) }
    }

    func requestAgentHandoff(mode: TaskStore.AgentHandoffMode, instructions: String?) {
        guard let item = selectedTask else { return }
        Task {
            do {
                _ = try await store.requestAgentHandoff(taskId: item.id, mode: mode, instructions: instructions)
                try? await Task.sleep(nanoseconds: 400_000_000)
                await MainActor.run { self.refreshTaskSnapshots(reason: "agent handoff") }
            } catch {
                NSLog("[Capture] Failed to request agent handoff: \(error)")
            }
        }
    }

    deinit {
        tasks.forEach { $0.cancel() }
        detailTasks.forEach { $0.cancel() }
    }
}
