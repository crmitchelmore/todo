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

    private let taskStore: TaskStore
    private var watchers: [Task<Void, Never>] = []

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
    }

    func createCategory(_ name: String) { Task { try? await taskStore.createCategory(name: name) } }
    func renameCategory(_ id: String, to name: String) { Task { try? await taskStore.renameCategory(id: id, to: name) } }
    func recolorCategory(_ id: String, color: String) { Task { try? await taskStore.recolorCategory(id: id, color: color) } }
    func deleteCategory(_ id: String) { Task { try? await taskStore.deleteCategory(id: id) } }
    func createTag(_ name: String) { Task { try? await taskStore.createTag(name: name) } }
    func renameTag(_ id: String, to name: String) { Task { try? await taskStore.renameTag(id: id, to: name) } }
    func recolorTag(_ id: String, color: String) { Task { try? await taskStore.recolorTag(id: id, color: color) } }
    func deleteTag(_ id: String) { Task { try? await taskStore.deleteTag(id: id) } }
    func createRule(title: String, instructions: String, category: String?, tags: [String], enabled: Bool) {
        Task { try? await taskStore.createCategorisationRule(title: title, instructions: instructions, category: category, tags: tags, enabled: enabled) }
    }
    func updateRule(id: String, title: String, instructions: String, category: String?, tags: [String], enabled: Bool) {
        Task { try? await taskStore.updateCategorisationRule(id: id, title: title, instructions: instructions, category: category, tags: tags, enabled: enabled) }
    }
    func deleteRule(_ id: String) { Task { try? await taskStore.deleteCategorisationRule(id: id) } }

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
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 760),
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
        .frame(width: 620, height: 760, alignment: .topLeading)
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
