import UIKit
import CaptureCore
import UserNotifications

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
    private(set) var rejected: [TaskItem] = []
    private(set) var allTags: [Tag] = []
    private(set) var allCategories: [TaskCategory] = []
    private(set) var tagColors: [String: String] = [:]   // lowercased name -> hex
    private(set) var tagFilter: Set<String> = []          // lowercased; AND semantics
    private(set) var syncSummary: CaptureSyncSummary = .checking
    private(set) var notifications: [CaptureNotification] = []

    var onChange: (() -> Void)?
    private var tasks: [Task<Void, Never>] = []
    private var syncTask: Task<Void, Never>?
    private var started = false
    private var lastSyncRestart: Date?
    private var notificationBootstrapComplete = false
    private let deliveredNotificationsKey = "capture.ios.deliveredNotifications"

    init(auth: AuthStore, config: CaptureConfig = .fromEnvironment()) {
        self.auth = auth
        self.store = TaskStore(config: config, auth: auth)
    }

    func start() {
        guard !started else {
            refreshTaskSnapshots(reason: "start requested again")
            refreshSyncSummary()
            return
        }
        started = true
        refreshTaskSnapshots(reason: "startup")
        Task {
            do {
                try await store.connect()
                refreshTaskSnapshots(reason: "connect")
            } catch {
                NSLog("[Capture] PowerSync connect failed: \(error)")
            }
        }
        watch({ try self.store.watchProposed() }, assign: { self.proposed = $0 })
        watch({ try self.store.watchActive() }, assign: { self.active = $0 })
        watch({ try self.store.watchDone() }, assign: { self.done = $0 })
        watch({ try self.store.watchRejected() }, assign: { self.rejected = $0 })
        watchTags()
        watchCategories()
        watchNotifications()
        refreshSyncSummary()
    }

    func restartSyncIfNeeded(reason: String) {
        guard started, auth.isAuthenticated else { return }
        let now = Date()
        if let lastSyncRestart, now.timeIntervalSince(lastSyncRestart) < 15 { return }
        lastSyncRestart = now
        Task {
            do {
                try await store.reconnect()
                refreshTaskSnapshots(reason: "reconnect")
                refreshSyncSummary()
            } catch {
                NSLog("[Capture] PowerSync reconnect failed (\(reason)): \(error)")
                refreshSyncSummary()
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
                        self.tagFilter.formIntersection(Set(rows.map { $0.name.lowercased() }))
                        self.onChange?()
                    }
                }
            } catch {}
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
                        self.onChange?()
                    }
                }
            } catch {}
        }
        tasks.append(t)
    }

    private func watchNotifications() {
        let t = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.store.watchNotifications() {
                    await MainActor.run {
                        self.notifications = rows
                        self.deliverNotifications(rows)
                        self.onChange?()
                    }
                }
            } catch {}
        }
        tasks.append(t)
    }

    private func deliverNotifications(_ rows: [CaptureNotification]) {
        var delivered = Set(UserDefaults.standard.stringArray(forKey: deliveredNotificationsKey) ?? [])
        if !notificationBootstrapComplete {
            delivered.formUnion(rows.map(\.id))
            UserDefaults.standard.set(Array(delivered.suffix(200)), forKey: deliveredNotificationsKey)
            notificationBootstrapComplete = true
            return
        }
        for notification in rows.reversed() where !delivered.contains(notification.id) {
            delivered.insert(notification.id)
            scheduleSystemNotification(notification)
        }
        UserDefaults.standard.set(Array(delivered.suffix(200)), forKey: deliveredNotificationsKey)
    }

    private func scheduleSystemNotification(_ notification: CaptureNotification) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let addRequest = {
                let content = UNMutableNotificationContent()
                content.title = notification.title
                content.body = notification.body ?? ""
                content.sound = .default
                let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: nil)
                center.add(request)
            }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                addRequest()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    CaptureDiagnostics.record(
                        severity: error == nil ? .info : .error,
                        category: "notifications",
                        name: "notifications.authorization",
                        message: granted ? "Notification permission granted" : "Notification permission not granted",
                        fields: error.map { ["error": $0.localizedDescription] } ?? [:]
                    )
                    if granted { addRequest() }
                }
            case .denied:
                CaptureDiagnostics.record(
                    severity: .warning,
                    category: "notifications",
                    name: "notifications.delivery.skipped",
                    message: "Notification permission denied",
                    fields: ["notification_id": notification.id]
                )
            @unknown default:
                break
            }
        }
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
    var filteredRejectedCount: Int { rejected.filter(matchesFilter).count }

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
    var filteredRejected: [TaskItem] { rejected.filter(matchesFilter) }

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
                    self.onChange?()
                }
            } catch {
                NSLog("[Capture] Task snapshot failed (\(reason)): \(error)")
            }
        }
    }

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

    func capture(_ text: String, attachments: [TaskAttachmentDraft] = [], options: TaskStore.CaptureOptions = .researchOnly) {
        Haptics.tap()
        if ingestIfList(text, options: options) { return }
        store.capture(text, attachments: attachments, options: options) // instant, non-blocking
        refreshSyncSummary()
    }

    /// If `text` is a markdown / checkbox list, ingest each line as its own item (nested lines
    /// become parent-linked subtasks with compatibility tags; `[x]` items import as done).
    /// Returns true if it was a list.
    @discardableResult
    func ingestIfList(_ text: String, options: TaskStore.CaptureOptions = .researchOnly) -> Bool {
        guard let items = store.detectList(text) else { return false }
        store.captureBatch(items, options: options)
        refreshSyncSummary()
        return true
    }

    func confirm(_ item: TaskItem, title: String, dueAt: Date?, category: String?, tags: [String]? = nil) {
        Haptics.success()
        Task {
            try? await store.confirm(id: item.id, title: title, dueAt: dueAt, category: category, tags: tags)
            refreshTaskSnapshots(reason: "confirm")
            refreshSyncSummary()
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
            refreshSyncSummary()
        }
    }

    func confirmDetail(_ item: TaskItem, form: IOSTaskDetailForm) {
        Haptics.success()
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
            refreshTaskSnapshots(reason: "confirm detail")
            refreshSyncSummary()
        }
    }

    func reject(_ item: TaskItem) {
        Task {
            try? await store.reject(id: item.id)
            refreshTaskSnapshots(reason: "reject")
            refreshSyncSummary()
        }
    }

    func setDone(_ item: TaskItem, _ done: Bool) {
        if done { Haptics.success() }
        Task {
            try? await store.setDone(id: item.id, done: done)
            refreshSyncSummary()
        }
    }

    /// Set or clear an active task's due date (inline date editing).
    func setDue(_ item: TaskItem, _ date: Date?) {
        Task {
            try? await store.setDue(id: item.id, dueAt: date)
            refreshSyncSummary()
        }
    }

    func requestAgentHandoff(_ item: TaskItem, mode: TaskStore.AgentHandoffMode, instructions: String?) {
        Task {
            do {
                _ = try await store.requestAgentHandoff(taskId: item.id, mode: mode, instructions: instructions)
                refreshSyncSummary()
            } catch {
                NSLog("[Capture] Failed to request agent handoff: \(error)")
            }
        }
    }

    func createCategory(_ name: String) {
        Task { try? await store.createCategory(name: name) }
    }

    func renameCategory(_ id: String, to name: String) {
        Task { try? await store.renameCategory(id: id, to: name) }
    }

    func recolorCategory(_ id: String, color: String) {
        Task { try? await store.recolorCategory(id: id, color: color) }
    }

    func deleteCategory(_ id: String) {
        Task { try? await store.deleteCategory(id: id) }
    }

    func createTag(_ name: String) {
        Task { try? await store.createTag(name: name) }
    }

    func renameTag(_ id: String, to name: String) {
        Task { try? await store.renameTag(id: id, to: name) }
    }

    func recolorTag(_ id: String, color: String) {
        Task { try? await store.recolorTag(id: id, color: color) }
    }

    func deleteTag(_ id: String) {
        Task { try? await store.deleteTag(id: id) }
    }

    func createCategorisationRule(title: String, instructions: String, category: String?, tags: [String], enabled: Bool) {
        Task { try? await store.createCategorisationRule(title: title, instructions: instructions, category: category, tags: tags, enabled: enabled) }
    }

    func updateCategorisationRule(id: String, title: String, instructions: String, category: String?, tags: [String], enabled: Bool) {
        Task { try? await store.updateCategorisationRule(id: id, title: title, instructions: instructions, category: category, tags: tags, enabled: enabled) }
    }

    func deleteCategorisationRule(_ id: String) {
        Task { try? await store.deleteCategorisationRule(id: id) }
    }

    func createUserMemory(content: String, domain: String?, tags: [String], expiresAt: Date?) {
        Task { try? await store.createUserMemory(content: content, domain: domain, tags: tags, expiresAt: expiresAt) }
    }

    func updateUserMemory(_ memory: UserMemory, content: String, domain: String?, tags: [String], expiresAt: Date?, status: UserMemoryStatus) {
        Task {
            try? await store.updateUserMemory(
                id: memory.id,
                content: content,
                domain: domain,
                source: memory.source,
                confidence: memory.confidence,
                tags: tags,
                expiresAt: expiresAt,
                status: status
            )
        }
    }

    func setUserMemoryStatus(_ id: String, status: UserMemoryStatus) {
        Task { try? await store.setUserMemoryStatus(id: id, status: status) }
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
                self.syncSummary = CaptureSyncSummary.from(server: serverDiagnostics, local: localDiagnostics)
                self.onChange?()
            } catch {
                let message = (error as? CaptureError)?.message ?? error.localizedDescription
                self.syncSummary = .offline(message)
                self.onChange?()
            }
        }
    }

    deinit {
        tasks.forEach { $0.cancel() }
        syncTask?.cancel()
    }
}
