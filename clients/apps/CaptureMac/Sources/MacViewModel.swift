import AppKit
import CaptureCore

@MainActor
final class MacViewModel {
    let store: TaskStore
    private(set) var proposed: [TaskItem] = []
    private(set) var active: [TaskItem] = []
    private(set) var tagColors: [String: String] = [:]   // lowercased name -> hex

    private var observers: [() -> Void] = []
    private var started = false
    private var tasks: [Task<Void, Never>] = []

    init(store: TaskStore = TaskStore(config: .fromEnvironment())) {
        self.store = store
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
                        self.tagColors = Dictionary(
                            rows.map { ($0.name.lowercased(), $0.color) },
                            uniquingKeysWith: { a, _ in a }
                        )
                        self.notify()
                    }
                }
            } catch {}
        }
        tasks.append(t)
    }

    /// Colour for a tag chip — user-chosen if known, else the deterministic palette colour
    /// (matches the web fallback) so chips look consistent before metadata syncs.
    func color(forTag name: String) -> String {
        tagColors[name.lowercased()] ?? TagPalette.color(for: name)
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
                        self.notify()
                    }
                }
            } catch {}
        }
        tasks.append(t)
    }

    func capture(_ text: String) {
        if ingestIfList(text) { return }
        store.capture(text)
    }

    /// If `text` is a markdown / checkbox list, ingest each line as its own item (nested lines
    /// become project tags; `[x]` items import as done). Returns true if it was a list.
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
        }
    }

    func reject(_ item: TaskItem) {
        Task { try? await store.reject(id: item.id) }
    }

    func setDone(_ item: TaskItem, _ done: Bool) {
        Task { try? await store.setDone(id: item.id, done: done) }
    }

    deinit { tasks.forEach { $0.cancel() } }
}
