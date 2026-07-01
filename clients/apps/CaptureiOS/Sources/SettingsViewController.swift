import UIKit
import CaptureCore

final class SettingsViewController: UIViewController {
    private let viewModel: CaptureViewModel
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let appearanceControl = UISegmentedControl(items: CaptureAppearanceMode.allCases.map(\.label))
    private let diagnosticsStatus = UILabel()
    private let diagnosticsDetail = UILabel()
    private let diagnosticsMeta = UILabel()
    private let diagnosticsRefresh = UIButton(type: .system)
    private let obsidianEnabled = UISwitch()
    private let obsidianVaultField = UITextField()
    private let obsidianFolderField = UITextField()
    private let obsidianCommandField = UITextField()
    private let obsidianEnvPreview = UILabel()
    private let categoriesStack = UIStackView()
    private let tagsStack = UIStackView()
    private let rulesStack = UIStackView()
    private let memoriesStack = UIStackView()
    private var taxonomyWatchTasks: [Task<Void, Never>] = []
    private var rules: [CategorisationRule] = []
    private var memories: [UserMemory] = []

    init(viewModel: CaptureViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    private func memoryRow(_ memory: UserMemory) -> UIView {
        let title = UILabel()
        title.text = memory.domain ?? "general"
        title.font = Theme.mono(11, .semibold)
        title.textColor = Theme.iris
        let body = UILabel()
        body.text = memory.content
        body.font = Theme.display(13, .regular)
        body.textColor = Theme.textPrimary
        body.numberOfLines = 3
        let meta = UILabel()
        let metaText = ([memory.source.rawValue] + memory.tags.map { "#\($0)" } + [memory.expiresAt.map { "expires \($0.formatted(date: .abbreviated, time: .omitted))" }].compactMap { $0 }).joined(separator: " · ")
        meta.text = metaText.isEmpty ? "agent context" : metaText
        meta.font = Theme.mono(11)
        meta.textColor = Theme.textTertiary
        let text = UIStackView(arrangedSubviews: [title, body, meta])
        text.axis = .vertical
        text.spacing = 3
        let edit = chipButton("Edit", color: Theme.signal) { [weak self] in self?.promptRenameMemory(memory) }
        let toggle = chipButton(memory.status == .disabled ? "Enable" : "Disable", color: Theme.textSecondary) { [weak self] in
            self?.viewModel.setUserMemoryStatus(memory.id, status: memory.status == .disabled ? .active : .disabled)
        }
        let delete = chipButton("Delete", color: Theme.danger) { [weak self] in
            self?.viewModel.setUserMemoryStatus(memory.id, status: .deleted)
        }
        let row = UIStackView(arrangedSubviews: [text, edit, toggle, delete])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        row.isLayoutMarginsRelativeArrangement = true
        row.backgroundColor = Theme.surfaceHi
        row.layer.cornerRadius = 12
        row.alpha = memory.status == .active ? 1 : 0.56
        return row
    }

    private func promptCreateRule() {
        promptRule(title: "New rule", rule: nil)
    }

    private func promptCreateMemory() {
        promptMemory(title: "New memory", memory: nil)
    }

    private func promptRenameMemory(_ memory: UserMemory) {
        promptMemory(title: "Edit memory", memory: memory)
    }

    private func promptMemory(title: String, memory: UserMemory?) {
        let alert = UIAlertController(title: title, message: "Facts and preferences guide agent research. Disable or delete stale context.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Preference or fact"
            field.text = memory?.content
        }
        alert.addTextField { field in
            field.placeholder = "Domain, e.g. shopping"
            field.text = memory?.domain
        }
        alert.addTextField { field in
            field.placeholder = "tags, comma-separated"
            field.text = memory?.tags.joined(separator: ", ")
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self, let alert else { return }
            let content = (alert.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return }
            let rawDomain = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let domain = rawDomain.isEmpty ? nil : rawDomain
            let tags = (alert.textFields?[2].text ?? "")
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let memory {
                self.viewModel.updateUserMemory(memory, content: content, domain: domain, tags: tags, expiresAt: memory.expiresAt, status: memory.status == .disabled ? .disabled : .active)
            } else {
                self.viewModel.createUserMemory(content: content, domain: domain, tags: tags, expiresAt: nil)
            }
        })
        present(alert, animated: true)
    }

    private func promptRenameRule(_ rule: CategorisationRule) {
        promptRule(title: "Edit rule", rule: rule)
    }

    private func promptRule(title: String, rule: CategorisationRule?) {
        let alert = UIAlertController(title: title, message: "Rules guide AI suggestions only; you still confirm the task.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Rule title"
            field.text = rule?.title
        }
        alert.addTextField { field in
            field.placeholder = "When should this apply?"
            field.text = rule?.instructions
        }
        alert.addTextField { field in
            field.placeholder = "Category (optional)"
            field.text = rule?.category
        }
        alert.addTextField { field in
            field.placeholder = "tags, comma-separated"
            field.text = rule?.tags.joined(separator: ", ")
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let title = (alert.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let instructions = (alert.textFields?[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !instructions.isEmpty else { return }
            let rawCategory = alert.textFields?[2].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let category = rawCategory.isEmpty ? nil : rawCategory
            let tags = (alert.textFields?[3].text ?? "")
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let rule {
                self.viewModel.updateCategorisationRule(id: rule.id, title: title, instructions: instructions, category: category, tags: tags, enabled: rule.enabled)
            } else {
                self.viewModel.createCategorisationRule(title: title, instructions: instructions, category: category, tags: tags, enabled: true)
            }
        })
        present(alert, animated: true)
    }

    private func ruleRow(_ rule: CategorisationRule) -> UIView {
        let title = UILabel()
        title.text = rule.title
        title.font = Theme.display(14, .semibold)
        title.textColor = Theme.textPrimary
        let body = UILabel()
        body.text = rule.instructions
        body.font = Theme.display(12, .regular)
        body.textColor = Theme.textSecondary
        body.numberOfLines = 2
        let meta = UILabel()
        let metaText = ([rule.category].compactMap { $0 } + rule.tags.map { "#\($0)" }).joined(separator: " · ")
        meta.text = metaText.isEmpty ? "suggestion context only" : metaText
        meta.font = Theme.mono(11)
        meta.textColor = Theme.iris
        let text = UIStackView(arrangedSubviews: [title, body, meta])
        text.axis = .vertical
        text.spacing = 3
        let edit = chipButton("Edit", color: Theme.signal) { [weak self] in self?.promptRenameRule(rule) }
        let delete = chipButton("Delete", color: Theme.danger) { [weak self] in self?.viewModel.deleteCategorisationRule(rule.id) }
        let row = UIStackView(arrangedSubviews: [text, edit, delete])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        row.isLayoutMarginsRelativeArrangement = true
        row.backgroundColor = Theme.surfaceHi
        row.layer.cornerRadius = 12
        row.alpha = rule.enabled ? 1 : 0.56
        return row
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        applyTheme()
        build()
        loadPreferences()
        loadDiagnostics()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
    }

    deinit {
        taxonomyWatchTasks.forEach { $0.cancel() }
    }

    private func build() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let header = UILabel()
        header.text = "Tune the capture surface without slowing capture down."
        header.font = Theme.display(17, .semibold)
        header.textColor = Theme.textSecondary
        header.numberOfLines = 0

        appearanceControl.selectedSegmentTintColor = Theme.signal
        appearanceControl.addTarget(self, action: #selector(appearanceChanged), for: .valueChanged)

        let accountNote = UILabel()
        accountNote.text = "Password changes use the emailed reset flow from the sign-in screen.\nBuild \(Self.appVersion)."
        accountNote.font = Theme.display(13, .regular)
        accountNote.textColor = Theme.textTertiary
        accountNote.numberOfLines = 0

        let signOutButton = UIButton(type: .system)
        signOutButton.setTitle("Sign Out", for: .normal)
        signOutButton.setTitleColor(Theme.danger, for: .normal)
        signOutButton.backgroundColor = Theme.surfaceHi
        signOutButton.layer.cornerRadius = 12
        signOutButton.addAction(UIAction { [weak self] _ in self?.signOut() }, for: .touchUpInside)

        diagnosticsStatus.font = Theme.display(15, .semibold)
        diagnosticsStatus.textColor = Theme.textPrimary
        diagnosticsStatus.numberOfLines = 0
        diagnosticsDetail.font = Theme.display(13, .regular)
        diagnosticsDetail.textColor = Theme.textSecondary
        diagnosticsDetail.numberOfLines = 0
        diagnosticsMeta.font = Theme.mono(11, .regular)
        diagnosticsMeta.textColor = Theme.textTertiary
        diagnosticsMeta.numberOfLines = 0
        diagnosticsRefresh.setTitle("Refresh diagnostics", for: .normal)
        diagnosticsRefresh.setTitleColor(Theme.signal, for: .normal)
        diagnosticsRefresh.backgroundColor = Theme.surfaceHi
        diagnosticsRefresh.layer.cornerRadius = 12
        diagnosticsRefresh.addAction(UIAction { [weak self] _ in self?.loadDiagnostics() }, for: .touchUpInside)

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(section(title: "Appearance", controls: [appearanceControl]))
        stack.addArrangedSubview(section(title: "Obsidian URL Summaries", controls: obsidianControls()))
        stack.addArrangedSubview(section(title: "Categories", controls: [makeAddButton(title: "Add category", action: { [weak self] in self?.promptCreateCategory() }), categoriesStack]))
        stack.addArrangedSubview(section(title: "Agent Memory", controls: [makeAddButton(title: "Add memory", action: { [weak self] in self?.promptCreateMemory() }), memoriesStack]))
        stack.addArrangedSubview(section(title: "AI Categorisation Rules", controls: [makeAddButton(title: "Add rule", action: { [weak self] in self?.promptCreateRule() }), rulesStack]))
        stack.addArrangedSubview(section(title: "Tags", controls: [makeAddButton(title: "Add tag", action: { [weak self] in self?.promptCreateTag() }), tagsStack]))
        stack.addArrangedSubview(section(title: "Sync Diagnostics", controls: [diagnosticsStatus, diagnosticsDetail, diagnosticsMeta, diagnosticsRefresh]))
        stack.addArrangedSubview(section(title: "Account", controls: [accountNote, signOutButton]))
        categoriesStack.axis = .vertical
        categoriesStack.spacing = 8
        tagsStack.axis = .vertical
        tagsStack.spacing = 8
        rulesStack.axis = .vertical
        rulesStack.spacing = 8
        memoriesStack.axis = .vertical
        memoriesStack.spacing = 8
        rebuildTaxonomy()

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -18),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
            diagnosticsRefresh.heightAnchor.constraint(equalToConstant: 44),
            signOutButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func loadPreferences() {
        let appearance = CapturePreferences.load().appearance
        appearanceControl.selectedSegmentIndex = CaptureAppearanceMode.allCases.firstIndex(of: appearance) ?? 1
        let preferences = CapturePreferences.load()
        obsidianEnabled.isOn = preferences.obsidianEnabled
        obsidianVaultField.text = preferences.obsidianVault
        obsidianFolderField.text = preferences.obsidianSummaryFolder
        obsidianCommandField.text = preferences.obsidianCLICommand
        refreshObsidianEnvPreview()
    }

    @objc private func appearanceChanged() {
        let index = appearanceControl.selectedSegmentIndex
        guard CaptureAppearanceMode.allCases.indices.contains(index) else { return }
        let mode = CaptureAppearanceMode.allCases[index]
        var preferences = CapturePreferences.load()
        preferences.appearance = mode
        preferences.save()
        view.window?.overrideUserInterfaceStyle = mode.userInterfaceStyle
        view.window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        NotificationCenter.default.post(name: .captureAppearanceChanged, object: nil)
        applyTheme()
    }

    @objc private func obsidianSettingsChanged() {
        let current = CapturePreferences.load()
        CapturePreferences(
            appearance: current.appearance,
            obsidianEnabled: obsidianEnabled.isOn,
            obsidianVault: obsidianVaultField.text ?? "",
            obsidianSummaryFolder: obsidianFolderField.text?.nilIfEmpty ?? "Capture/Summaries",
            obsidianCLICommand: obsidianCommandField.text?.nilIfEmpty ?? "obsidian"
        ).save()
        refreshObsidianEnvPreview()
    }

    private func applyTheme() {
        view.backgroundColor = Theme.ink
        view.window?.tintColor = Theme.signal
        scrollView.backgroundColor = Theme.ink
        stack.backgroundColor = Theme.ink
        rebuildTaxonomy()
    }

    private func loadDiagnostics() {
        diagnosticsStatus.text = "Checking sync state…"
        diagnosticsDetail.text = "Comparing this iPhone's local cache with the authenticated Railway account."
        diagnosticsMeta.text = ""
        diagnosticsRefresh.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                async let server = viewModel.auth.fetchSyncDiagnostics()
                async let local = viewModel.store.localSyncDiagnostics()
                let (serverDiagnostics, localDiagnostics) = try await (server, local)
                await updateDiagnostics(server: serverDiagnostics, local: localDiagnostics)
            } catch {
                await MainActor.run {
                    self.diagnosticsStatus.text = "Diagnostics unavailable"
                    self.diagnosticsDetail.text = (error as? CaptureError)?.message ?? error.localizedDescription
                    self.diagnosticsMeta.text = ""
                    self.diagnosticsRefresh.isEnabled = true
                }
            }
        }
    }

    @MainActor
    private func updateDiagnostics(server: ServerSyncDiagnostics, local: LocalSyncDiagnostics) {
        if local.ownerId != server.owner.id {
            diagnosticsStatus.text = "Account mismatch"
            diagnosticsDetail.text = "This device is stamping local rows with a different owner ID than the server session."
        } else if local.ownerIds.contains(where: { $0 != server.owner.id }) {
            diagnosticsStatus.text = "Local cache has another owner"
            diagnosticsDetail.text = "Sign out and back in to force a clean local reset before trusting the visible task list."
        } else if local.counts.total != server.serverCounts.total {
            diagnosticsStatus.text = "Counts differ"
            diagnosticsDetail.text = "PowerSync may still be catching up, or this build may be pointed at a different endpoint."
        } else {
            diagnosticsStatus.text = "Sync looks aligned"
            diagnosticsDetail.text = "This device, PowerSync and the backend are looking at the same account."
        }
        diagnosticsMeta.text = """
        Account: \(server.owner.email ?? server.owner.id)
        Server/local tasks: \(server.serverCounts.total)/\(local.counts.total)
        Session: \(server.currentSession?.client ?? "unknown")
        Backend: \(local.endpoints.backendURL)
        PowerSync: \(local.endpoints.powersyncURL)
        Local owners: \(local.ownerIds.joined(separator: ", ").nilIfEmpty ?? "none")
        """
        diagnosticsRefresh.isEnabled = true
    }

    private func signOut() {
        Task {
            await viewModel.auth.signOut()
            await viewModel.store.clearActiveUser()
        }
    }

    private func rebuildTaxonomy() {
        startTaxonomyWatchersIfNeeded()
        categoriesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        tagsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rulesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        memoriesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let existingCategories = Set(viewModel.allCategories.map { CategoryPalette.key($0.name) })
        let missingDefaults = CAPTURE_CATEGORIES.filter { !existingCategories.contains(CategoryPalette.key($0)) }
        if !missingDefaults.isEmpty {
            let defaults = UIStackView()
            defaults.axis = .horizontal
            defaults.spacing = 6
            defaults.alignment = .leading
            for name in missingDefaults {
                defaults.addArrangedSubview(chipButton("+ \(name)", color: Theme.textSecondary) { [weak self] in
                    self?.viewModel.createCategory(name)
                    self?.reloadTaxonomySoon()
                })
            }
            categoriesStack.addArrangedSubview(defaults)
        }
        for category in viewModel.allCategories {
            categoriesStack.addArrangedSubview(taxonomyRow(
                name: category.name,
                color: category.color,
                onRename: { [weak self] in self?.promptRenameCategory(category) },
                onRecolor: { [weak self] in self?.presentColorPicker(current: category.color) { color in
                    self?.viewModel.recolorCategory(category.id, color: color)
                    self?.reloadTaxonomySoon()
                }},
                onDelete: { [weak self] in
                    self?.viewModel.deleteCategory(category.id)
                    self?.reloadTaxonomySoon()
                }
            ))
        }
        if viewModel.allCategories.isEmpty {
            categoriesStack.addArrangedSubview(emptyLabel("No categories yet. Add defaults or create your own."))
        }
        for memory in memories {
            memoriesStack.addArrangedSubview(memoryRow(memory))
        }
        if memories.isEmpty {
            memoriesStack.addArrangedSubview(emptyLabel("No memories yet. Add preferences the agent should use for research."))
        }
        for rule in rules {
            rulesStack.addArrangedSubview(ruleRow(rule))
        }
        if rules.isEmpty {
            rulesStack.addArrangedSubview(emptyLabel("No rules yet. Add one like “wok research → errands + shopping”."))
        }
        for tag in viewModel.allTags {
            tagsStack.addArrangedSubview(taxonomyRow(
                name: tag.name,
                color: tag.color,
                onRename: { [weak self] in self?.promptRenameTag(tag) },
                onRecolor: { [weak self] in self?.presentColorPicker(current: tag.color) { color in
                    self?.viewModel.recolorTag(tag.id, color: color)
                    self?.reloadTaxonomySoon()
                }},
                onDelete: { [weak self] in
                    self?.viewModel.deleteTag(tag.id)
                    self?.reloadTaxonomySoon()
                }
            ))
        }
        if viewModel.allTags.isEmpty {
            tagsStack.addArrangedSubview(emptyLabel("No tags yet. Create tags here, then apply them from task details."))
        }
    }

    private func reloadTaxonomySoon() {
    }

    private func startTaxonomyWatchersIfNeeded() {
        guard taxonomyWatchTasks.isEmpty else { return }
        taxonomyWatchTasks.append(Task { [weak self] in
            guard let store = self?.viewModel.store else { return }
            do {
                for try await _ in try store.watchCategories() {
                    guard let self else { break }
                    await MainActor.run { self.rebuildTaxonomy() }
                }
            } catch {}
        })
        taxonomyWatchTasks.append(Task { [weak self] in
            guard let store = self?.viewModel.store else { return }
            do {
                for try await _ in try store.watchTags() {
                    guard let self else { break }
                    await MainActor.run { self.rebuildTaxonomy() }
                }
            } catch {}
        })
        taxonomyWatchTasks.append(Task { [weak self] in
            guard let store = self?.viewModel.store else { return }
            do {
                for try await rules in try store.watchCategorisationRules() {
                    guard let self else { break }
                    await MainActor.run {
                        self.rules = rules
                        self.rebuildTaxonomy()
                    }
                }
            } catch {}
        })
        taxonomyWatchTasks.append(Task { [weak self] in
            guard let store = self?.viewModel.store else { return }
            do {
                for try await memories in try store.watchUserMemories() {
                    guard let self else { break }
                    await MainActor.run {
                        self.memories = memories
                        self.rebuildTaxonomy()
                    }
                }
            } catch {}
        })
    }

    private func makeAddButton(title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(Theme.signal, for: .normal)
        button.backgroundColor = Theme.surfaceHi
        button.layer.cornerRadius = 12
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func obsidianControls() -> [UIView] {
        let help = UILabel()
        help.text = "URL-only captures generate an overview plus a 3-5 paragraph markdown summary. Mirror these local settings into the worker environment for CLI write-back."
        help.font = Theme.display(13, .regular)
        help.textColor = Theme.textSecondary
        help.numberOfLines = 0

        let toggleRow = UIStackView(arrangedSubviews: [settingLabel("Enable CLI write-back"), obsidianEnabled])
        toggleRow.axis = .horizontal
        toggleRow.alignment = .center
        toggleRow.spacing = 10
        obsidianEnabled.addTarget(self, action: #selector(obsidianSettingsChanged), for: .valueChanged)

        configureObsidianField(obsidianVaultField, placeholder: "Vault name")
        configureObsidianField(obsidianFolderField, placeholder: "Capture/Summaries")
        configureObsidianField(obsidianCommandField, placeholder: "obsidian")
        obsidianEnvPreview.font = Theme.mono(11, .regular)
        obsidianEnvPreview.textColor = Theme.textTertiary
        obsidianEnvPreview.numberOfLines = 0

        return [
            help,
            toggleRow,
            labelledField("Vault", obsidianVaultField),
            labelledField("Summary folder", obsidianFolderField),
            labelledField("CLI command", obsidianCommandField),
            obsidianEnvPreview,
        ]
    }

    private func configureObsidianField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.textColor = Theme.textPrimary
        field.backgroundColor = Theme.surfaceHi
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.addTarget(self, action: #selector(obsidianSettingsChanged), for: .editingChanged)
    }

    private func labelledField(_ title: String, _ field: UITextField) -> UIView {
        let stack = UIStackView(arrangedSubviews: [settingLabel(title), field])
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }

    private func settingLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Theme.mono(11, .semibold)
        label.textColor = Theme.textTertiary
        return label
    }

    private func refreshObsidianEnvPreview() {
        let enabled = obsidianEnabled.isOn ? "1" : "0"
        let vault = obsidianVaultField.text?.nilIfEmpty ?? "<vault>"
        let folder = obsidianFolderField.text?.nilIfEmpty ?? "Capture/Summaries"
        let command = obsidianCommandField.text?.nilIfEmpty ?? "obsidian"
        obsidianEnvPreview.text = "OBSIDIAN_CLI_ENABLED=\(enabled) OBSIDIAN_VAULT=\(vault) OBSIDIAN_SUMMARY_FOLDER=\(folder) OBSIDIAN_CLI_COMMAND=\(command)"
    }

    private func taxonomyRow(
        name: String,
        color: String,
        onRename: @escaping () -> Void,
        onRecolor: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> UIView {
        let dot = UIView()
        dot.backgroundColor = UIColor(hex: color) ?? Theme.textSecondary
        dot.layer.cornerRadius = 5
        dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 10).isActive = true

        let nameButton = UIButton(type: .system)
        nameButton.setTitle(name, for: .normal)
        nameButton.setTitleColor(Theme.textPrimary, for: .normal)
        nameButton.titleLabel?.font = Theme.display(14, .semibold)
        nameButton.contentHorizontalAlignment = .leading
        nameButton.addAction(UIAction { _ in onRename() }, for: .touchUpInside)

        let colorButton = chipButton("Colour", color: UIColor(hex: color) ?? Theme.iris, action: onRecolor)
        let deleteButton = chipButton("Delete", color: Theme.danger, action: onDelete)
        let row = UIStackView(arrangedSubviews: [dot, nameButton, colorButton, deleteButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        row.isLayoutMarginsRelativeArrangement = true
        row.backgroundColor = Theme.surfaceHi
        row.layer.cornerRadius = 12
        return row
    }

    private func chipButton(_ title: String, color: UIColor, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(color, for: .normal)
        button.backgroundColor = color.withAlphaComponent(0.12)
        button.layer.cornerRadius = 10
        button.titleLabel?.font = Theme.mono(11, .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func emptyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Theme.display(13, .regular)
        label.textColor = Theme.textTertiary
        label.numberOfLines = 0
        return label
    }

    private func promptCreateCategory() {
        promptText(title: "New category", placeholder: "engineering") { [weak self] value in
            self?.viewModel.createCategory(value)
            self?.reloadTaxonomySoon()
        }
    }

    private func promptCreateTag() {
        promptText(title: "New tag", placeholder: "project-name") { [weak self] value in
            self?.viewModel.createTag(value)
            self?.reloadTaxonomySoon()
        }
    }

    private func promptRenameCategory(_ category: TaskCategory) {
        promptText(title: "Rename category", placeholder: category.name, defaultValue: category.name) { [weak self] value in
            self?.viewModel.renameCategory(category.id, to: value)
            self?.reloadTaxonomySoon()
        }
    }

    private func promptRenameTag(_ tag: Tag) {
        promptText(title: "Rename tag", placeholder: tag.name, defaultValue: tag.name) { [weak self] value in
            self?.viewModel.renameTag(tag.id, to: value)
            self?.reloadTaxonomySoon()
        }
    }

    private func promptText(title: String, placeholder: String, defaultValue: String = "", onSave: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = placeholder
            field.text = defaultValue
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let value = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { return }
            onSave(value)
        })
        present(alert, animated: true)
    }

    private func presentColorPicker(current: String, onPick: @escaping (String) -> Void) {
        let sheet = UIAlertController(title: "Colour", message: nil, preferredStyle: .actionSheet)
        for color in TagPalette.colors {
            sheet.addAction(UIAlertAction(title: color == current ? "✓ \(color)" : color, style: .default) { _ in onPick(color) })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        present(sheet, animated: true)
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version) (\(build))"
    }

    private func section(title: String, controls: [UIView]) -> UIView {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 10
        card.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        card.isLayoutMarginsRelativeArrangement = true
        card.backgroundColor = Theme.surface
        card.layer.cornerRadius = 18

        let label = UILabel()
        label.text = title.uppercased()
        label.font = Theme.mono(12, .semibold)
        label.textColor = Theme.textTertiary
        card.addArrangedSubview(label)
        controls.forEach { card.addArrangedSubview($0) }
        return card
    }
}

private extension CaptureAppearanceMode {
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .dark: return .dark
        case .light: return .light
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
