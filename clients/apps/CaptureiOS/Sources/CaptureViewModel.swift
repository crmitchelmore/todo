import UIKit
import CaptureCore

/// Bridges CaptureCore's background watch streams onto the main actor so UIKit
/// can render reactively. Capture itself stays instant (fire-and-forget).
@MainActor
final class CaptureViewModel {
    let store: TaskStore
    private(set) var proposed: [TaskItem] = []
    private(set) var active: [TaskItem] = []
    private(set) var allTags: [Tag] = []
    private(set) var tagColors: [String: String] = [:]   // lowercased name -> hex
    private(set) var tagFilter: Set<String> = []          // lowercased; AND semantics

    var onChange: (() -> Void)?
    private var tasks: [Task<Void, Never>] = []

    init(store: TaskStore = TaskStore(config: .fromEnvironment())) {
        self.store = store
    }

    func start() {
        Task { try? await store.connect() }
        watch({ try self.store.watchProposed() }, assign: { self.proposed = $0 })
        watch({ try self.store.watchActive() }, assign: { self.active = $0 })
        watchTags()
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

    func capture(_ text: String) {
        if ingestIfList(text) { return }
        store.capture(text) // instant, non-blocking
    }

    /// If `text` is a markdown / checkbox list, ingest each line as its own item (nested lines
    /// become project tags; `[x]` items import as done). Returns true if it was a list.
    @discardableResult
    func ingestIfList(_ text: String) -> Bool {
        guard let items = store.detectList(text) else { return false }
        store.captureBatch(items)
        return true
    }

    func confirm(_ item: TaskItem, title: String, dueAt: Date?, category: String?, tags: [String]? = nil) {
        Task { try? await store.confirm(id: item.id, title: title, dueAt: dueAt, category: category, tags: tags) }
    }

    func reject(_ item: TaskItem) {
        Task { try? await store.reject(id: item.id) }
    }

    func setDone(_ item: TaskItem, _ done: Bool) {
        Task { try? await store.setDone(id: item.id, done: done) }
    }

    /// Set or clear an active task's due date (inline date editing).
    func setDue(_ item: TaskItem, _ date: Date?) {
        Task { try? await store.setDue(id: item.id, dueAt: date) }
    }

    deinit { tasks.forEach { $0.cancel() } }
}
