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

@MainActor
final class TaxonomySettingsStore: ObservableObject {
    @Published var categories: [TaskCategory] = []
    @Published var tags: [Tag] = []
    @Published var rules: [CategorisationRule] = []
    @Published var memories: [UserMemory] = []
    @Published var agentDevices: [AgentDevice] = []
    @Published var notifications: [CaptureNotification] = []
    @Published var agentDeviceMessage: String?
    @Published var agentDeviceBusy = false

    private let taskStore: TaskStore
    private var watchers: [Task<Void, Never>] = []
    private static let agentDeviceIdKey = "capture.agentDeviceId"

    init(taskStore: TaskStore) {
        self.taskStore = taskStore
    }

    func start() {
        guard watchers.isEmpty else { return }
        watchers.append(Task { [weak self] in
            guard let store = self?.taskStore else { return }
            do {
                for try await rows in try store.watchCategories() {
                    guard let self else { break }
                    await MainActor.run { self.categories = rows }
                }
            } catch {
                NSLog("[Capture] Category settings watch failed: \(error)")
            }
        })
        watchers.append(Task { [weak self] in
            guard let store = self?.taskStore else { return }
            do {
                for try await rows in try store.watchTags() {
                    guard let self else { break }
                    await MainActor.run { self.tags = rows }
                }
            } catch {
                NSLog("[Capture] Tag settings watch failed: \(error)")
            }
        })
        watchers.append(Task { [weak self] in
            guard let store = self?.taskStore else { return }
            do {
                for try await rows in try store.watchCategorisationRules() {
                    guard let self else { break }
                    await MainActor.run { self.rules = rows }
                }
            } catch {
                NSLog("[Capture] Categorisation rule settings watch failed: \(error)")
            }
        })
        watchers.append(Task { [weak self] in
            guard let store = self?.taskStore else { return }
            do {
                for try await rows in try store.watchUserMemories() {
                    guard let self else { break }
                    await MainActor.run { self.memories = rows }
                }
            } catch {
                NSLog("[Capture] Memory settings watch failed: \(error)")
            }
        })
        watchers.append(Task { [weak self] in
            guard let store = self?.taskStore else { return }
            do {
                for try await rows in try store.watchAgentDevices() {
                    guard let self else { break }
                    await MainActor.run { self.agentDevices = rows }
                }
            } catch {
                NSLog("[Capture] Agent device settings watch failed: \(error)")
            }
        })
        watchers.append(Task { [weak self] in
            guard let store = self?.taskStore else { return }
            do {
                for try await rows in try store.watchNotifications() {
                    guard let self else { break }
                    await MainActor.run { self.notifications = rows }
                }
            } catch {
                NSLog("[Capture] Notification settings watch failed: \(error)")
            }
        })
    }

    func createCategory(_ name: String) { runSettingsAction("Create category", fields: ["name_chars": "\(name.count)"]) { try await self.taskStore.createCategory(name: name) } }
    func renameCategory(_ id: String, to name: String) { runSettingsAction("Rename category", fields: ["category_id": id, "name_chars": "\(name.count)"]) { try await self.taskStore.renameCategory(id: id, to: name) } }
    func recolorCategory(_ id: String, color: String) { runSettingsAction("Recolour category", fields: ["category_id": id, "color": color]) { try await self.taskStore.recolorCategory(id: id, color: color) } }
    func deleteCategory(_ id: String) { runSettingsAction("Delete category", fields: ["category_id": id]) { try await self.taskStore.deleteCategory(id: id) } }
    func createTag(_ name: String) { runSettingsAction("Create tag", fields: ["name_chars": "\(name.count)"]) { try await self.taskStore.createTag(name: name) } }
    func renameTag(_ id: String, to name: String) { runSettingsAction("Rename tag", fields: ["tag_id": id, "name_chars": "\(name.count)"]) { try await self.taskStore.renameTag(id: id, to: name) } }
    func recolorTag(_ id: String, color: String) { runSettingsAction("Recolour tag", fields: ["tag_id": id, "color": color]) { try await self.taskStore.recolorTag(id: id, color: color) } }
    func deleteTag(_ id: String) { runSettingsAction("Delete tag", fields: ["tag_id": id]) { try await self.taskStore.deleteTag(id: id) } }
    func createRule(title: String, instructions: String, category: String?, tags: [String], enabled: Bool) {
        runSettingsAction("Create categorisation rule", fields: ["title_chars": "\(title.count)", "tag_count": "\(tags.count)", "enabled": enabled ? "true" : "false"]) {
            try await self.taskStore.createCategorisationRule(title: title, instructions: instructions, category: category, tags: tags, enabled: enabled)
        }
    }
    func updateRule(id: String, title: String, instructions: String, category: String?, tags: [String], enabled: Bool) {
        runSettingsAction("Update categorisation rule", fields: ["rule_id": id, "title_chars": "\(title.count)", "tag_count": "\(tags.count)", "enabled": enabled ? "true" : "false"]) {
            try await self.taskStore.updateCategorisationRule(id: id, title: title, instructions: instructions, category: category, tags: tags, enabled: enabled)
        }
    }
    func deleteRule(_ id: String) { runSettingsAction("Delete categorisation rule", fields: ["rule_id": id]) { try await self.taskStore.deleteCategorisationRule(id: id) } }
    func createMemory(content: String, domain: String?, tags: [String], expiresAt: Date?) {
        runSettingsAction("Create memory", fields: ["content_chars": "\(content.count)", "tag_count": "\(tags.count)", "has_expiry": expiresAt == nil ? "false" : "true"]) {
            try await self.taskStore.createUserMemory(content: content, domain: domain, tags: tags, expiresAt: expiresAt)
        }
    }
    func updateMemory(_ memory: UserMemory, content: String, domain: String?, tags: [String], expiresAt: Date?, status: UserMemoryStatus) {
        runSettingsAction("Update memory", fields: ["memory_id": memory.id, "content_chars": "\(content.count)", "tag_count": "\(tags.count)", "status": status.rawValue]) {
            try await self.taskStore.updateUserMemory(
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
    func setMemoryStatus(_ id: String, status: UserMemoryStatus) {
        runSettingsAction("Set memory status", fields: ["memory_id": id, "status": status.rawValue]) { try await self.taskStore.setUserMemoryStatus(id: id, status: status) }
    }
    func registerCurrentMac(harnessKind: AgentHarnessKind, harnessLabel: String?, capabilities: [String], selectedBackend: Bool) {
        Task {
            agentDeviceBusy = true
            agentDeviceMessage = "Registering this Mac…"
            let deviceName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            let deviceId = currentAgentDeviceId()
            let fields = [
                "device_id": deviceId,
                "harness_kind": harnessKind.rawValue,
                "selected_backend": selectedBackend ? "true" : "false",
                "capability_count": "\(capabilities.count)"
            ]
            let context = CaptureDiagnostics.actionStarted("Register this Mac", fields: fields)
            let startedAt = Date()
            do {
                try await taskStore.upsertAgentDevice(
                    id: deviceId,
                    deviceName: deviceName,
                    harnessKind: harnessKind,
                    harnessLabel: harnessLabel,
                    capabilities: capabilities,
                    selectedBackend: selectedBackend
                )
                CaptureDiagnostics.actionCompleted(context, startedAt: startedAt)
                agentDeviceMessage = selectedBackend ? "Registered \(deviceName) as backend." : "Registered \(deviceName)."
                CaptureObservability.wideEvent("mac.agent_device.registered", fields: [
                    "device_id": deviceId,
                    "harness_kind": harnessKind.rawValue,
                    "selected_backend": selectedBackend ? "true" : "false"
                ])
            } catch {
                CaptureDiagnostics.actionFailed(context, startedAt: startedAt, error: error)
                let message = (error as? CaptureError)?.message ?? error.localizedDescription
                agentDeviceMessage = "Registration failed: \(message)"
                CaptureObservability.capture(error, operation: "mac_agent_device_register", fields: [
                    "device_id": deviceId,
                    "harness_kind": harnessKind.rawValue
                ])
            }
            agentDeviceBusy = false
        }
    }
    func selectAgentDevice(_ id: String) {
        Task {
            let context = CaptureDiagnostics.actionStarted("Select backend Mac", fields: ["device_id": id])
            let startedAt = Date()
            do {
                try await taskStore.selectAgentBackendDevice(id: id)
                CaptureDiagnostics.actionCompleted(context, startedAt: startedAt)
                agentDeviceMessage = "Backend device selected."
                CaptureObservability.wideEvent("mac.agent_device.selected", fields: ["device_id": id])
            } catch {
                CaptureDiagnostics.actionFailed(context, startedAt: startedAt, error: error)
                agentDeviceMessage = "Selection failed: \((error as? CaptureError)?.message ?? error.localizedDescription)"
                CaptureObservability.capture(error, operation: "mac_agent_device_select", fields: ["device_id": id])
            }
        }
    }
    func disableAgentDevice(_ id: String) {
        Task {
            let context = CaptureDiagnostics.actionStarted("Disable backend Mac", fields: ["device_id": id])
            let startedAt = Date()
            do {
                try await taskStore.disableAgentDevice(id: id)
                CaptureDiagnostics.actionCompleted(context, startedAt: startedAt)
                agentDeviceMessage = "Device disabled."
                CaptureObservability.wideEvent("mac.agent_device.disabled", fields: ["device_id": id])
            } catch {
                CaptureDiagnostics.actionFailed(context, startedAt: startedAt, error: error)
                agentDeviceMessage = "Disable failed: \((error as? CaptureError)?.message ?? error.localizedDescription)"
                CaptureObservability.capture(error, operation: "mac_agent_device_disable", fields: ["device_id": id])
            }
        }
    }

    private func runSettingsAction<T>(
        _ name: String,
        fields: [String: String] = [:],
        operation: @escaping () async throws -> T
    ) {
        Task {
            let context = CaptureDiagnostics.actionStarted(name, fields: fields)
            let startedAt = Date()
            do {
                _ = try await operation()
                CaptureDiagnostics.actionCompleted(context, startedAt: startedAt)
            } catch {
                CaptureDiagnostics.actionFailed(context, startedAt: startedAt, error: error)
                CaptureDiagnostics.record(
                    severity: .error,
                    category: "settings",
                    name: "settings.action.failed",
                    message: error.localizedDescription,
                    fields: fields.merging(["action": name, "error_type": String(describing: type(of: error))]) { first, _ in first }
                )
            }
        }
    }

    private func currentAgentDeviceId() -> String {
        if let id = UserDefaults.standard.string(forKey: Self.agentDeviceIdKey), !id.isEmpty { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: Self.agentDeviceIdKey)
        return id
    }

    deinit { watchers.forEach { $0.cancel() } }
}

/// Hosts the Settings UI (hotkey, appearance and account) in an AppKit window
/// via NSHostingController, since the app is otherwise pure AppKit.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let store: HotKeyStore
    private let preferences: MacPreferencesStore
    private let taxonomy: TaxonomySettingsStore
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
        self.taxonomy = TaxonomySettingsStore(taskStore: taskStore)
        self.auth = auth
        self.taskStore = taskStore
        self.onChange = onChange
        self.onAppearanceChange = onAppearanceChange
        self.onSignOut = onSignOut
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 920),
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
                taxonomy: taxonomy,
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
    @ObservedObject var taxonomy: TaxonomySettingsStore
    let auth: AuthStore
    let taskStore: TaskStore
    let onChange: (HotKey) -> Void
    let onAppearanceChange: (CaptureAppearanceMode) -> Void
    let onSignOut: () -> Void
    @State private var serverDiagnostics: ServerSyncDiagnostics?
    @State private var localDiagnostics: LocalSyncDiagnostics?
    @State private var diagnosticsError: String?
    @State private var diagnosticsBusy = false
    @ObservedObject private var appDiagnostics = CaptureDiagnostics.shared

    var body: some View {
        ScrollView {
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

                GroupBox("Diagnostics & Debug") {
                    DiagnosticsDebugView(diagnostics: appDiagnostics)
                        .padding(.top, 4)
                }

                GroupBox("Notification History") {
                    NativeNotificationHistoryView(notifications: taxonomy.notifications)
                        .padding(.top, 4)
                }

                GroupBox("Agent Backend Computer") {
                    AgentBackendSettingsView(taxonomy: taxonomy)
                        .padding(.top, 4)
                }

                GroupBox("Categories & Tags") {
                    TaxonomyManagerView(taxonomy: taxonomy)
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
        }
        .frame(width: 760, height: 920, alignment: .topLeading)
        .task { taxonomy.start() }
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

private struct DiagnosticsDebugView: View {
    @ObservedObject var diagnostics: CaptureDiagnostics
    @State private var errorsOnly = false
    @State private var expanded: Set<String> = []

    private var filteredGroups: [CaptureDiagnosticActionGroup] {
        diagnostics.actionGroups.filter { group in
            !errorsOnly || group.events.contains { $0.severity == .error || $0.severity == .warning }
        }
    }

    private var errorCount: Int {
        diagnostics.events.filter { $0.severity == .error }.count
    }

    private var warningCount: Int {
        diagnostics.events.filter { $0.severity == .warning }.count
    }

    private var networkCount: Int {
        diagnostics.events.filter { $0.category == "network" }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Local event stream with remote-observability shape.")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text("Captures app actions, button clicks, local SQLite writes, PowerSync activity, outbound requests, inbound responses and errors. Secrets and raw payloads are redacted at source.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                DiagnosticMetric(label: "Events", value: "\(diagnostics.events.count)")
                DiagnosticMetric(label: "Errors", value: "\(errorCount)")
                DiagnosticMetric(label: "Warnings", value: "\(warningCount)")
                DiagnosticMetric(label: "Network", value: "\(networkCount)")
            }

            HStack {
                Toggle("Errors and warnings only", isOn: $errorsOnly)
                    .onChange(of: errorsOnly) { enabled in
                        CaptureDiagnostics.record(
                            category: "ui",
                            name: "settings.diagnostics.filter_toggled",
                            message: enabled ? "Diagnostics filter enabled" : "Diagnostics filter disabled",
                            fields: ["errors_only": enabled ? "true" : "false"]
                        )
                    }
                Spacer()
                Button("Copy JSON") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diagnostics.exportJSON(), forType: .string)
                    CaptureDiagnostics.record(category: "ui", name: "settings.diagnostics.copy_json", message: "Diagnostics JSON copied")
                }
                Button("Clear") {
                    diagnostics.clear()
                    CaptureDiagnostics.record(category: "ui", name: "settings.diagnostics.cleared", message: "Diagnostics stream cleared")
                }
            }
            .font(.caption)

            if filteredGroups.isEmpty {
                Text("No diagnostic events yet. Use the app, then return here to inspect the action timeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: Theme.surface))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredGroups) { group in
                        DisclosureGroup(isExpanded: expansionBinding(for: group.id)) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(group.events) { event in
                                    DiagnosticEventRow(event: event)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            DiagnosticActionHeader(group: group)
                        }
                        .padding(10)
                        .background(Color(nsColor: Theme.surface))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOpen in
                if isOpen {
                    expanded.insert(id)
                } else {
                    expanded.remove(id)
                }
                CaptureDiagnostics.record(
                    category: "ui",
                    name: "settings.diagnostics.group_toggled",
                    message: isOpen ? "Diagnostics group expanded" : "Diagnostics group collapsed",
                    fields: ["group_id": id, "expanded": isOpen ? "true" : "false"]
                )
            }
        )
    }
}

private struct NativeNotificationHistoryView: View {
    let notifications: [CaptureNotification]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Research, interview and attempt updates stay here even if the system banner was missed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if notifications.isEmpty {
                Text("No notifications yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: Theme.surface))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(notifications.prefix(30)) { notification in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(notification.kind.replacingOccurrences(of: "_", with: " ").uppercased())
                                    .font(.system(size: 9, design: .monospaced).weight(.bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(notification.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Text(notification.title)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                            if let body = notification.body, !body.isEmpty {
                                Text(body)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: Theme.surface))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }
}

private struct DiagnosticActionHeader: View {
    let group: CaptureDiagnosticActionGroup

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DiagnosticSeverityPill(severity: group.severity)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(group.events.count) events · \(group.startedAt.formatted(date: .omitted, time: .standard)) → \(group.updatedAt.formatted(date: .omitted, time: .standard))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct DiagnosticEventRow: View {
    let event: CaptureDiagnosticEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                DiagnosticSeverityPill(severity: event.severity)
                Text("#\(event.sequence)")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(event.name)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(event.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !event.fields.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(event.fields.keys.sorted(), id: \.self) { key in
                        Text("\(key)=\(event.fields[key] ?? "")")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: Theme.surfaceHi))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DiagnosticSeverityPill: View {
    let severity: CaptureDiagnosticSeverity

    var body: some View {
        Text(severity.rawValue.uppercased())
            .font(.system(size: 9, design: .monospaced).weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colour)
            .clipShape(Capsule())
    }

    private var colour: Color {
        switch severity {
        case .debug: return Color.gray
        case .info: return Color.mint
        case .warning: return Color.orange
        case .error: return Color.red
        }
    }
}

private struct AgentBackendSettingsView: View {
    @ObservedObject var taxonomy: TaxonomySettingsStore
    @State private var harnessKind: AgentHarnessKind = .openclaw
    @State private var harnessLabel = "OpenClaw"
    @State private var capabilities = "research, attempt"
    @State private var selectThisMac = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose which Mac runs approved local harness work.")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text("Register every Mac that has Capture installed, then select one backend computer. The actual CLI path and secrets stay local on that machine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Picker("Harness", selection: $harnessKind) {
                    ForEach(AgentHarnessKind.allCases, id: \.rawValue) { kind in
                        Text(label(for: kind)).tag(kind)
                    }
                }
                .frame(width: 210)
                TextField("Harness label", text: $harnessLabel)
                    .textFieldStyle(.roundedBorder)
                TextField("Capabilities", text: $capabilities)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Toggle("Use this Mac as backend", isOn: $selectThisMac)
                Spacer()
                Button("Register this Mac") {
                    taxonomy.registerCurrentMac(
                        harnessKind: harnessKind,
                        harnessLabel: harnessLabel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                        capabilities: parsedCapabilities,
                        selectedBackend: selectThisMac
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(taxonomy.agentDeviceBusy)
            }
            if let message = taxonomy.agentDeviceMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.localizedCaseInsensitiveContains("failed") ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if taxonomy.agentDevices.isEmpty {
                Text("No backend devices registered yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(taxonomy.agentDevices) { device in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(device.deviceName)
                                        .font(.system(.body, design: .rounded).weight(.semibold))
                                    if device.isSelectedBackend {
                                        Text("backend")
                                            .font(.system(size: 10, design: .monospaced).weight(.bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.purple)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text([
                                    device.platform,
                                    device.harnessKind.map(label(for:)),
                                    device.harnessLabel,
                                    device.lastSeenAt.map { "seen \($0.formatted(date: .abbreviated, time: .shortened))" }
                                ].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !device.capabilities.isEmpty {
                                    Text(device.capabilities.map { "#\($0)" }.joined(separator: " "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .opacity(device.status == .active ? 1 : 0.55)
                            Spacer()
                            if !device.isSelectedBackend && device.status == .active {
                                Button("Use as backend") { taxonomy.selectAgentDevice(device.id) }
                            }
                            Button(device.status == .disabled ? "Disabled" : "Disable") {
                                taxonomy.disableAgentDevice(device.id)
                            }
                            .disabled(device.status == .disabled)
                        }
                        .padding(8)
                        .background(Color(nsColor: Theme.surface))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    private var parsedCapabilities: [String] {
        capabilities
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func label(for kind: AgentHarnessKind) -> String {
        switch kind {
        case .copilotCLI: return "Copilot CLI"
        case .hermes: return "Hermes"
        case .openclaw: return "OpenClaw"
        case .custom: return "Custom"
        }
    }
}

private struct TaxonomyManagerView: View {
    @ObservedObject var taxonomy: TaxonomySettingsStore
    @State private var newCategory = ""
    @State private var newTag = ""

    private var missingDefaults: [String] {
        let existing = Set(taxonomy.categories.map { CategoryPalette.key($0.name) })
        return CAPTURE_CATEGORIES.filter { !existing.contains(CategoryPalette.key($0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TaxonomySection(
                title: "Categories",
                subtitle: "Primary lanes for work. Renaming one moves existing tasks with it.",
                newName: $newCategory,
                placeholder: "New category",
                items: taxonomy.categories.map { TaxonomyItem(id: $0.id, name: $0.name, color: $0.color) },
                onCreate: taxonomy.createCategory,
                onRename: taxonomy.renameCategory,
                onRecolor: taxonomy.recolorCategory,
                onDelete: taxonomy.deleteCategory
            )
            if !missingDefaults.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(missingDefaults, id: \.self) { name in
                        Button("+ \(name)") { taxonomy.createCategory(name) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
            Divider()
            MemorySettingsView(taxonomy: taxonomy)
            Divider()
            CategorisationRulesSettingsView(taxonomy: taxonomy)
            Divider()
            TaxonomySection(
                title: "Tags",
                subtitle: "Lightweight labels for people, projects and contexts. Renaming updates task chips.",
                newName: $newTag,
                placeholder: "New tag",
                items: taxonomy.tags.map { TaxonomyItem(id: $0.id, name: $0.name, color: $0.color) },
                onCreate: taxonomy.createTag,
                onRename: taxonomy.renameTag,
                onRecolor: taxonomy.recolorTag,
                onDelete: taxonomy.deleteTag
            )
        }
    }
}

private struct RuleDraft {
            var title = ""
            var instructions = ""
            var category = ""
            var tags = ""
            var enabled = true

            static func from(_ rule: CategorisationRule) -> RuleDraft {
                RuleDraft(
                    title: rule.title,
                    instructions: rule.instructions,
                    category: rule.category ?? "",
                    tags: rule.tags.joined(separator: ", "),
                    enabled: rule.enabled
                )
            }

            var parsedTags: [String] {
                tags.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
        }

        private struct MemoryDraft {
            var content = ""
            var domain = ""
            var tags = ""
            var expiresAt = Date()
            var hasExpiry = false
            var status: UserMemoryStatus = .active

            static func from(_ memory: UserMemory) -> MemoryDraft {
                MemoryDraft(
                    content: memory.content,
                    domain: memory.domain ?? "",
                    tags: memory.tags.joined(separator: ", "),
                    expiresAt: memory.expiresAt ?? Date(),
                    hasExpiry: memory.expiresAt != nil,
                    status: memory.status == .disabled ? .disabled : .active
                )
            }

            var parsedTags: [String] {
                tags.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }

            var parsedExpiry: Date? { hasExpiry ? expiresAt : nil }
        }

        private struct MemorySettingsView: View {
            @ObservedObject var taxonomy: TaxonomySettingsStore
            @State private var draft = MemoryDraft()
            @State private var editing: UserMemory?

            var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Agent memory")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                        Text("Facts and preferences the agent can use for research. Disable or delete anything stale.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextEditor(text: $draft.content)
                        .frame(minHeight: 72)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.22)))
                    HStack {
                        TextField("domain, e.g. shopping", text: $draft.domain)
                            .textFieldStyle(.roundedBorder)
                        TextField("tags, comma-separated", text: $draft.tags)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Toggle("Expires", isOn: $draft.hasExpiry)
                        if draft.hasExpiry {
                            DatePicker("Expiry", selection: $draft.expiresAt, displayedComponents: .date)
                        }
                        Picker("Status", selection: $draft.status) {
                            Text("Active").tag(UserMemoryStatus.active)
                            Text("Disabled").tag(UserMemoryStatus.disabled)
                        }
                    }
                    HStack {
                        Button(editing == nil ? "Add memory" : "Save memory", action: save)
                            .disabled(draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if editing != nil {
                            Button("Cancel") {
                                editing = nil
                                draft = MemoryDraft()
                            }
                        }
                    }
                    if taxonomy.memories.isEmpty {
                        Text("No memories yet. Add a preference like “For cookware I prefer buy-it-for-life quality around £80–£150.”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(taxonomy.memories) { memory in
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(memory.domain ?? "general")
                                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                                            .foregroundStyle(.purple)
                                        Text(memory.content)
                                            .font(.system(.body, design: .rounded))
                                        Text(([memory.source.rawValue] + memory.tags.map { "#\($0)" } + [memory.expiresAt.map { "expires \($0.formatted(date: .abbreviated, time: .omitted))" }].compactMap { $0 }).joined(separator: " · "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .opacity(memory.status == .active ? 1 : 0.55)
                                    Spacer()
                                    Button("Edit") {
                                        editing = memory
                                        draft = .from(memory)
                                    }
                                    Button(memory.status == .disabled ? "Enable" : "Disable") {
                                        taxonomy.setMemoryStatus(memory.id, status: memory.status == .disabled ? .active : .disabled)
                                    }
                                    Button(role: .destructive) {
                                        taxonomy.setMemoryStatus(memory.id, status: .deleted)
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                }
                                .padding(8)
                                .background(Color(nsColor: Theme.surface))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
            }

            private func save() {
                let content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return }
                let domain = draft.domain.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                if let editing {
                    taxonomy.updateMemory(editing, content: content, domain: domain, tags: draft.parsedTags, expiresAt: draft.parsedExpiry, status: draft.status)
                } else {
                    taxonomy.createMemory(content: content, domain: domain, tags: draft.parsedTags, expiresAt: draft.parsedExpiry)
                }
                editing = nil
                draft = MemoryDraft()
            }
        }

        private struct CategorisationRulesSettingsView: View {
            @ObservedObject var taxonomy: TaxonomySettingsStore
            @State private var draft = RuleDraft()
            @State private var editingId: String?

            private var categoryOptions: [String] {
                var seen = Set<String>()
                var out: [String] = []
                for name in taxonomy.categories.map(\.name) + CAPTURE_CATEGORIES {
                    let key = CategoryPalette.key(name)
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    out.append(name)
                }
                return out.sorted()
            }

            var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AI categorisation rules")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                        Text("Rules guide worker/LLM suggestions only; confirmation still stays human-gated.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Rule title", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                    TextEditor(text: $draft.instructions)
                        .frame(minHeight: 74)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.22)))
                    HStack {
                        Picker("Category", selection: $draft.category) {
                            Text("No category").tag("")
                            ForEach(categoryOptions, id: \.self) { name in Text(name).tag(name) }
                        }
                        TextField("tags, comma-separated", text: $draft.tags)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Enabled", isOn: $draft.enabled)
                    }
                    HStack {
                        Button(editingId == nil ? "Add rule" : "Save rule", action: save)
                            .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                      draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if editingId != nil {
                            Button("Cancel") {
                                editingId = nil
                                draft = RuleDraft()
                            }
                        }
                    }

                    if taxonomy.rules.isEmpty {
                        Text("No rules yet. Add one like “wok research → errands + shopping”.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(taxonomy.rules) { rule in
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(rule.title)
                                            .font(.system(.body, design: .rounded).weight(.semibold))
                                        Text(rule.instructions)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(([rule.category].compactMap { $0 } + rule.tags.map { "#\($0)" }).joined(separator: " · "))
                                            .font(.caption2)
                                            .foregroundStyle(.purple)
                                    }
                                    .opacity(rule.enabled ? 1 : 0.55)
                                    Spacer()
                                    Button("Edit") {
                                        editingId = rule.id
                                        draft = .from(rule)
                                    }
                                    Button(role: .destructive) {
                                        taxonomy.deleteRule(rule.id)
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                }
                                .padding(8)
                                .background(Color(nsColor: Theme.surface))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
            }

            private func save() {
                let category = draft.category.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                if let editingId {
                    taxonomy.updateRule(id: editingId, title: draft.title, instructions: draft.instructions, category: category, tags: draft.parsedTags, enabled: draft.enabled)
                } else {
                    taxonomy.createRule(title: draft.title, instructions: draft.instructions, category: category, tags: draft.parsedTags, enabled: draft.enabled)
                }
                editingId = nil
                draft = RuleDraft()
            }
    }

private struct TaxonomyItem: Identifiable {
    let id: String
    let name: String
    let color: String
}

private struct TaxonomySection: View {
    let title: String
    let subtitle: String
    @Binding var newName: String
    let placeholder: String
    let items: [TaxonomyItem]
    let onCreate: (String) -> Void
    let onRename: (String, String) -> Void
    let onRecolor: (String, String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField(placeholder, text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { create() }
                Button("Add", action: create)
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if items.isEmpty {
                Text("No \(title.lowercased()) yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        TaxonomyRow(item: item, onRename: onRename, onRecolor: onRecolor, onDelete: onDelete)
                    }
                }
            }
        }
    }

    private func create() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newName = ""
        onCreate(trimmed)
    }
}

private struct TaxonomyRow: View {
    let item: TaxonomyItem
    let onRename: (String, String) -> Void
    let onRecolor: (String, String) -> Void
    let onDelete: (String) -> Void
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: NSColor(hex: item.color) ?? Theme.textSecondary))
                .frame(width: 10, height: 10)

            if editing {
                TextField("Name", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename() }
                    .onExitCommand { editing = false }
            } else {
                Button(item.name) {
                    draft = item.name
                    editing = true
                }
                .buttonStyle(.plain)
                .font(.system(.body, design: .rounded).weight(.semibold))
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(TagPalette.colors, id: \.self) { color in
                    Button {
                        onRecolor(item.id, color)
                    } label: {
                        Circle()
                            .fill(Color(nsColor: NSColor(hex: color) ?? Theme.textSecondary))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(color == item.color ? Color.primary : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(role: .destructive) {
                onDelete(item.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(Color(nsColor: Theme.surface))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func commitRename() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = false
        guard !trimmed.isEmpty else { return }
        onRename(item.id, trimmed)
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: spacing) { content }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
