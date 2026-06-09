import UIKit
import CaptureCore

struct CaptureSyncSummary: Equatable {
    enum State: Equatable { case checking, aligned, warning, offline }

    let state: State
    let title: String
    let detail: String

    static let checking = CaptureSyncSummary(
        state: .checking,
        title: "sync checking",
        detail: "Comparing local cache with Railway."
    )

    static func offline(_ message: String) -> CaptureSyncSummary {
        CaptureSyncSummary(state: .offline, title: "sync unknown", detail: message)
    }

    static func from(server: ServerSyncDiagnostics, local: LocalSyncDiagnostics) -> CaptureSyncSummary {
        if local.ownerId != server.owner.id {
            return CaptureSyncSummary(
                state: .warning,
                title: "account mismatch",
                detail: "Local owner does not match the authenticated server session."
            )
        }
        if local.ownerIds.contains(where: { $0 != server.owner.id }) {
            return CaptureSyncSummary(
                state: .warning,
                title: "cache mixed",
                detail: "Local cache contains rows for another owner."
            )
        }
        if local.counts.total != server.serverCounts.total {
            return CaptureSyncSummary(
                state: .warning,
                title: "sync catching up",
                detail: "Server/local tasks \(server.serverCounts.total)/\(local.counts.total)."
            )
        }
        return CaptureSyncSummary(
            state: .aligned,
            title: "synced",
            detail: "Server/local tasks \(server.serverCounts.total)/\(local.counts.total)."
        )
    }
}

/// Bridges CaptureCore's background watch streams onto the main actor so UIKit
/// can render reactively. Capture itself stays instant (fire-and-forget).
@MainActor
final class CaptureViewModel {
    let store: TaskStore
    let auth: AuthStore
    private(set) var proposed: [TaskItem] = []
    private(set) var active: [TaskItem] = []
    private(set) var done: [TaskItem] = []
    private(set) var allTags: [Tag] = []
    private(set) var tagColors: [String: String] = [:]   // lowercased name -> hex
    private(set) var tagFilter: Set<String> = []          // lowercased; AND semantics
    private(set) var syncSummary: CaptureSyncSummary = .checking

    var onChange: (() -> Void)?
    private var tasks: [Task<Void, Never>] = []
    private var syncTask: Task<Void, Never>?

    init(auth: AuthStore, config: CaptureConfig = .fromEnvironment()) {
        self.auth = auth
        self.store = TaskStore(config: config, auth: auth)
    }

    func start() {
        Task { try? await store.connect() }
        watch({ try self.store.watchProposed() }, assign: { self.proposed = $0 })
        watch({ try self.store.watchActive() }, assign: { self.active = $0 })
        watch({ try self.store.watchDone() }, assign: { self.done = $0 })
        watchTags()
        refreshSyncSummary()
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
                        self.tagFilter.formIntersection(Set(rows.map { $0.name.lowercased() }))
                        self.onChange?()
                    }
                }
            } catch {}
        }
        tasks.append(t)
    }

    func color(forTag name: String) -> String {
        tagColors[name.lowercased()] ?? TagPalette.color(for: name)
    }

    // MARK: - Tag filtering (AND/intersection)

    func toggleFilter(_ name: String) {
        let key = name.lowercased()
        if tagFilter.contains(key) { tagFilter.remove(key) } else { tagFilter.insert(key) }
        onChange?()
    }

    func clearFilter() {
        guard !tagFilter.isEmpty else { return }
        tagFilter.removeAll()
        onChange?()
    }

    func isFiltering(_ name: String) -> Bool { tagFilter.contains(name.lowercased()) }

    private func matchesFilter(_ item: TaskItem) -> Bool {
        guard !tagFilter.isEmpty else { return true }
        let have = Set(item.tags.map { $0.lowercased() })
        return tagFilter.allSatisfy { have.contains($0) }
    }

    var filteredActiveCount: Int { active.filter(matchesFilter).count }
    var filteredDoneCount: Int { done.filter(matchesFilter).count }

    /// Filtered active items grouped into date buckets (in bucket order), for "view by date".
    var activeGroups: [(bucket: DateBucket, items: [TaskItem])] {
        let items = active.filter(matchesFilter)
        var byBucket: [DateBucket: [TaskItem]] = [:]
        for item in items {
            byBucket[DateGrouping.bucket(for: item.dueAt), default: []].append(item)
        }
        return DateBucket.allCases.compactMap { bucket in
            guard let group = byBucket[bucket], !group.isEmpty else { return nil }
            return (bucket, group)
        }
    }

    var filteredDone: [TaskItem] { done.filter(matchesFilter) }

    private func watch(
        _ make: @escaping () throws -> AsyncThrowingStream<[TaskItem], Error>,
        assign: @escaping ([TaskItem]) -> Void
    ) {
        let t = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try make() {
                    await MainActor.run {
                        assign(rows)
                        self.onChange?()
                    }
                }
            } catch {
                // stream ended/cancelled
            }
        }
        tasks.append(t)
    }

    func capture(_ text: String, attachments: [TaskAttachmentDraft] = []) {
        if ingestIfList(text) { return }
        store.capture(text, attachments: attachments) // instant, non-blocking
        refreshSyncSummary()
    }

    /// If `text` is a markdown / checkbox list, ingest each line as its own item (nested lines
    /// become parent-linked subtasks with compatibility tags; `[x]` items import as done).
    /// Returns true if it was a list.
    @discardableResult
    func ingestIfList(_ text: String) -> Bool {
        guard let items = store.detectList(text) else { return false }
        store.captureBatch(items)
        refreshSyncSummary()
        return true
    }

    func confirm(_ item: TaskItem, title: String, dueAt: Date?, category: String?, tags: [String]? = nil) {
        Task {
            try? await store.confirm(id: item.id, title: title, dueAt: dueAt, category: category, tags: tags)
            await MainActor.run { self.refreshSyncSummary() }
        }
    }

    func saveDetail(_ item: TaskItem, form: IOSTaskDetailForm) {
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
            await MainActor.run { self.refreshSyncSummary() }
        }
    }

    func confirmDetail(_ item: TaskItem, form: IOSTaskDetailForm) {
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
            await MainActor.run { self.refreshSyncSummary() }
        }
    }

    func reject(_ item: TaskItem) {
        Task {
            try? await store.reject(id: item.id)
            await MainActor.run { self.refreshSyncSummary() }
        }
    }

    func setDone(_ item: TaskItem, _ done: Bool) {
        Task {
            try? await store.setDone(id: item.id, done: done)
            await MainActor.run { self.refreshSyncSummary() }
        }
    }

    /// Set or clear an active task's due date (inline date editing).
    func setDue(_ item: TaskItem, _ date: Date?) {
        Task {
            try? await store.setDue(id: item.id, dueAt: date)
            await MainActor.run { self.refreshSyncSummary() }
        }
    }

    func refreshSyncSummary() {
        syncTask?.cancel()
        syncSummary = .checking
        onChange?()
        syncTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let server = self.auth.fetchSyncDiagnostics()
                async let local = self.store.localSyncDiagnostics()
                let (serverDiagnostics, localDiagnostics) = try await (server, local)
                await MainActor.run {
                    self.syncSummary = CaptureSyncSummary.from(server: serverDiagnostics, local: localDiagnostics)
                    self.onChange?()
                }
            } catch {
                let message = (error as? CaptureError)?.message ?? error.localizedDescription
                await MainActor.run {
                    self.syncSummary = .offline(message)
                    self.onChange?()
                }
            }
        }
    }

    deinit {
        tasks.forEach { $0.cancel() }
        syncTask?.cancel()
    }
}
