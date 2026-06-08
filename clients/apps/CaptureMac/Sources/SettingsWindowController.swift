import AppKit
import SwiftUI
import CaptureCore

@MainActor
final class MacPreferencesStore: ObservableObject {
    @Published var preferences: CapturePreferences {
        didSet { preferences.save() }
    }

    init() {
        self.preferences = CapturePreferences.load()
    }
}

/// Hosts the Settings UI (hotkey, appearance and account) in an AppKit window
/// via NSHostingController, since the app is otherwise pure AppKit.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let store: HotKeyStore
    private let preferences: MacPreferencesStore
    private let auth: AuthStore
    private let taskStore: TaskStore
    private let onChange: (HotKey) -> Void
    private let onAppearanceChange: (CaptureAppearanceMode) -> Void
    private let onSignOut: () -> Void

    init(
        store: HotKeyStore,
        preferences: MacPreferencesStore,
        auth: AuthStore,
        taskStore: TaskStore,
        onChange: @escaping (HotKey) -> Void,
        onAppearanceChange: @escaping (CaptureAppearanceMode) -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.store = store
        self.preferences = preferences
        self.auth = auth
        self.taskStore = taskStore
        self.onChange = onChange
        self.onAppearanceChange = onAppearanceChange
        self.onSignOut = onSignOut
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        super.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: SettingsView(
                store: store,
                preferences: preferences,
                auth: auth,
                taskStore: taskStore,
                onChange: onChange,
                onAppearanceChange: onAppearanceChange,
                onSignOut: onSignOut
            )
        )
        window.center()
        window.setFrameAutosaveName("CaptureSettingsWindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsView: View {
    @ObservedObject var store: HotKeyStore
    @ObservedObject var preferences: MacPreferencesStore
    let auth: AuthStore
    let taskStore: TaskStore
    let onChange: (HotKey) -> Void
    let onAppearanceChange: (CaptureAppearanceMode) -> Void
    let onSignOut: () -> Void
    @State private var serverDiagnostics: ServerSyncDiagnostics?
    @State private var localDiagnostics: LocalSyncDiagnostics?
    @State private var diagnosticsError: String?
    @State private var diagnosticsBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("Keep capture fast, tune the surface, and manage this account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox("Global Hotkey") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Press this combination anywhere to summon quick capture. Click the field, then press your shortcut — it needs at least one modifier (⌘ ⌥ ⌃ ⇧).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HotKeyRecorder(hotKey: Binding(
                        get: { store.hotKey },
                        set: { newValue in
                            // Let the app try to register it; it persists store.hotKey only on success,
                            // so a rejected combo leaves the recorder showing the previous shortcut.
                            onChange(newValue)
                        }
                    ))
                }
                .padding(.top, 4)
            }

            GroupBox("Appearance") {
                Picker("Mode", selection: Binding(
                    get: { preferences.preferences.appearance },
                    set: { mode in
                        preferences.preferences.appearance = mode
                        onAppearanceChange(mode)
                    }
                )) {
                    ForEach(CaptureAppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 4)
            }

            GroupBox("Sync Diagnostics") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(diagnosticsHeadline)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                            Text(diagnosticsSubhead)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button(diagnosticsBusy ? "Checking…" : "Refresh") {
                            Task { await loadDiagnostics() }
                        }
                        .disabled(diagnosticsBusy)
                    }

                    if let diagnosticsError {
                        Text(diagnosticsError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        DiagnosticMetric(label: "Account", value: serverDiagnostics?.owner.email ?? serverDiagnostics?.owner.id ?? "unknown")
                        DiagnosticMetric(label: "Session", value: serverDiagnostics?.currentSession?.client ?? "unknown")
                        DiagnosticMetric(label: "Server total", value: "\(serverDiagnostics?.serverCounts.total ?? 0)")
                        DiagnosticMetric(label: "Local total", value: "\(localDiagnostics?.counts.total ?? 0)")
                        DiagnosticMetric(label: "Server updated", value: Self.format(serverDiagnostics?.serverCounts.lastUpdatedAt))
                        DiagnosticMetric(label: "Local updated", value: Self.format(localDiagnostics?.counts.lastUpdatedAt))
                    }

                    DisclosureGroup("Endpoint details") {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Backend: \(localDiagnostics?.endpoints.backendURL ?? "unknown")")
                            Text("PowerSync: \(localDiagnostics?.endpoints.powersyncURL ?? "unknown")")
                            Text("Owner ID: \(serverDiagnostics?.owner.id ?? "unknown")")
                            Text("Local owners: \((localDiagnostics?.ownerIds ?? []).joined(separator: ", ").nilIfEmpty ?? "none")")
                            Text("Clients: \(clientSummary)")
                        }
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("Account") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Signed in")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                        Text("Password changes use the emailed reset flow from the sign-in screen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sign Out", role: .destructive, action: onSignOut)
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 560, height: 620, alignment: .topLeading)
        .task { await loadDiagnostics() }
    }

    private var diagnosticsHeadline: String {
        guard let serverDiagnostics, let localDiagnostics else {
            return diagnosticsBusy ? "Checking sync state" : "Not checked yet"
        }
        if localDiagnostics.ownerId != serverDiagnostics.owner.id { return "Account mismatch" }
        if localDiagnostics.ownerIds.contains(where: { $0 != serverDiagnostics.owner.id }) { return "Local cache has another owner" }
        if localDiagnostics.counts.total != serverDiagnostics.serverCounts.total { return "Counts differ" }
        return "Sync looks aligned"
    }

    private var diagnosticsSubhead: String {
        guard let serverDiagnostics, let localDiagnostics else {
            return "Compares this Mac's local SQLite cache with the authenticated Railway account."
        }
        if localDiagnostics.ownerId != serverDiagnostics.owner.id {
            return "This Mac is stamping local rows with a different owner ID than the current server session."
        }
        if localDiagnostics.ownerIds.contains(where: { $0 != serverDiagnostics.owner.id }) {
            return "Sign out and back in to force a clean local reset before trusting the visible task list."
        }
        if localDiagnostics.counts.total != serverDiagnostics.serverCounts.total {
            return "PowerSync may still be catching up, or this build may be pointed at a different endpoint."
        }
        return "This Mac, PowerSync and the backend are looking at the same account."
    }

    private var clientSummary: String {
        guard let sessions = serverDiagnostics?.sessions, !sessions.isEmpty else { return "none" }
        return sessions.map { "\($0.client) \($0.activeSessions)/\($0.sessions)" }.joined(separator: ", ")
    }

    @MainActor
    private func loadDiagnostics() async {
        diagnosticsBusy = true
        diagnosticsError = nil
        do {
            async let server = auth.fetchSyncDiagnostics()
            async let local = taskStore.localSyncDiagnostics()
            serverDiagnostics = try await server
            localDiagnostics = try await local
        } catch {
            diagnosticsError = (error as? CaptureError)?.message ?? error.localizedDescription
        }
        diagnosticsBusy = false
    }

    private static func format(_ date: Date?) -> String {
        guard let date else { return "none" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct DiagnosticMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: Theme.surface))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
