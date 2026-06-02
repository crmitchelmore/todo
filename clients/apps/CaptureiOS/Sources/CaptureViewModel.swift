import UIKit
import CaptureCore

/// Bridges CaptureCore's background watch streams onto the main actor so UIKit
/// can render reactively. Capture itself stays instant (fire-and-forget).
@MainActor
final class CaptureViewModel {
    let store: TaskStore
    private(set) var proposed: [TaskItem] = []
    private(set) var active: [TaskItem] = []

    var onChange: (() -> Void)?
    private var tasks: [Task<Void, Never>] = []

    init(store: TaskStore = TaskStore()) {
        self.store = store
    }

    func start() {
        Task { try? await store.connect() }
        watch({ try self.store.watchProposed() }, assign: { self.proposed = $0 })
        watch({ try self.store.watchActive() }, assign: { self.active = $0 })
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
        store.capture(text) // instant, non-blocking
    }

    func confirm(_ item: TaskItem, title: String, dueAt: Date?, category: String?) {
        Task { try? await store.confirm(id: item.id, title: title, dueAt: dueAt, category: category) }
    }

    func reject(_ item: TaskItem) {
        Task { try? await store.reject(id: item.id) }
    }

    func setDone(_ item: TaskItem, _ done: Bool) {
        Task { try? await store.setDone(id: item.id, done: done) }
    }

    deinit { tasks.forEach { $0.cancel() } }
}
