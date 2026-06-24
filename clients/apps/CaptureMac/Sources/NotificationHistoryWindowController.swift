import AppKit
import SwiftUI
import CaptureCore

@MainActor
final class NotificationHistoryStore: ObservableObject {
    @Published var notifications: [CaptureNotification] = []
    private let taskStore: TaskStore
    private var watcher: Task<Void, Never>?

    init(taskStore: TaskStore) {
        self.taskStore = taskStore
    }

    func start() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try taskStore.watchNotifications(limit: 120) {
                    await MainActor.run { self.notifications = rows }
                }
            } catch {
                NSLog("[Capture] Notification history watch failed: \(error)")
            }
        }
    }

    deinit { watcher?.cancel() }
}

@MainActor
final class NotificationHistoryWindowController: NSWindowController {
    private let store: NotificationHistoryStore

    init(taskStore: TaskStore) {
        self.store = NotificationHistoryStore(taskStore: taskStore)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notifications"
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: NativeNotificationHistoryView(store: store))
        window.center()
        window.setFrameAutosaveName("CaptureNotificationsWindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func show() {
        store.start()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct NativeNotificationHistoryView: View {
    @ObservedObject var store: NotificationHistoryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Notifications")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text("Research, interview and attempt updates stay here even if the system banner was missed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if store.notifications.isEmpty {
                    Text("No notifications yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: Theme.surface))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ForEach(store.notifications.prefix(80)) { notification in
                        NotificationRow(notification: notification)
                    }
                }
            }
            .padding(18)
        }
        .frame(width: 520, height: 620)
        .background(Color(nsColor: Theme.ink))
    }
}

private struct NotificationRow: View {
    let notification: CaptureNotification

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(notification.kind.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 9, design: .monospaced).weight(.bold))
                    .foregroundStyle(tint)
                Spacer()
                Text(notification.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(notification.title)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Color(nsColor: Theme.textPrimary))
            if let body = notification.body, !body.isEmpty {
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: Theme.surface))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tint: Color {
        switch notification.severity {
        case "error": return Color(nsColor: Theme.danger)
        case "warning": return Color(nsColor: Theme.signal)
        case "success": return Color(nsColor: Theme.mint)
        default: return Color(nsColor: Theme.iris)
        }
    }
}
