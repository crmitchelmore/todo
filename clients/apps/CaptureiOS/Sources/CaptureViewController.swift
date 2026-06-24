import UIKit
import CaptureCore

/// Capture field that intercepts paste: a pasted markdown / checkbox list is ingested as
/// individual items instead of pasting collapsed single-line text.
final class CapturePasteTextField: UITextField {
    var onPasteList: ((String) -> Bool)?
    var onPasteImages: (([UIImage]) -> Bool)?

    override func paste(_ sender: Any?) {
        if let s = UIPasteboard.general.string, onPasteList?(s) == true { return }
        if let images = UIPasteboard.general.images, !images.isEmpty, onPasteImages?(images) == true { return }
        if let image = UIPasteboard.general.image, onPasteImages?([image]) == true { return }
        super.paste(sender)
    }
}

final class CaptureViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIDropInteractionDelegate {
    private enum TaskSection {
        case proposed([TaskItem])
        case active(DateBucket, [TaskItem])
        case done([TaskItem])
        case rejected([TaskItem])

        var title: String {
            switch self {
            case let .proposed(items):
                return "NEEDS CONFIRMING · \(items.count)"
            case let .active(bucket, items):
                return "\(bucket.label.uppercased()) · \(items.count)"
            case let .done(items):
                return "DONE · \(items.count)"
            case let .rejected(items):
                return "REJECTED · \(items.count)"
            }
        }
    }

    private let viewModel: CaptureViewModel
    private let commandLabel = UILabel()
    private let syncPill = UIButton(type: .system)
    private let captureField = CapturePasteTextField()
    private let automationStack = UIStackView()
    private let attemptSwitch = UISwitch()
    private let confirmPlanSwitch = UISwitch()
    private let attemptLabel = UILabel()
    private let confirmPlanLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let filterBar = UIScrollView()
    private let filterStack = UIStackView()
    private let passkeys = NativePasskeyAuthorizer()
    private var filterHeightConstraint: NSLayoutConstraint?

    init(viewModel: CaptureViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func focusCaptureField() {
        loadViewIfNeeded()
        captureField.becomeFirstResponder()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Capture"
        applyTheme()
        setupCaptureBar()
        setupFilterBar()
        setupTable()
        setupNavigation()

        viewModel.onChange = { [weak self] in
            self?.rebuildFilterBar()
            self?.updateSyncPill()
            self?.tableView.reloadData()
        }
        viewModel.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: .captureAppearanceChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
    }

    private func setupNavigation() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: self, action: #selector(openSettings)),
            UIBarButtonItem(image: UIImage(systemName: "bell"), style: .plain, target: self, action: #selector(openNotifications)),
            UIBarButtonItem(image: UIImage(systemName: "key"), style: .plain, target: self, action: #selector(addPasskey))
        ]
    }

    @objc private func openSettings() {
        navigationController?.pushViewController(SettingsViewController(viewModel: viewModel), animated: true)
    }

    @objc private func openNotifications() {
        navigationController?.pushViewController(NotificationHistoryViewController(viewModel: viewModel), animated: true)
    }

    @objc private func signOut() {
        Task {
            await viewModel.auth.signOut()
            await viewModel.store.clearActiveUser()
        }
    }

    @objc private func addPasskey() {
        guard let anchor = view.window else { return }
        Task {
            do {
                let options = try await viewModel.auth.beginPasskeyRegistration()
                let registration = try await passkeys.register(options: options, anchor: anchor)
                try await viewModel.auth.finishPasskeyRegistration(registration)
                showBanner("Passkey added.", isError: false)
            } catch {
                showBanner((error as? CaptureError)?.message ?? error.localizedDescription, isError: true)
            }
        }
    }

    private func showBanner(_ message: String, isError: Bool) {
        let alert = UIAlertController(title: isError ? "Passkey unavailable" : "Account security",
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func applyTheme() {
        view.backgroundColor = Theme.ink
        view.window?.tintColor = Theme.signal
        commandLabel.textColor = Theme.textTertiary
        syncPill.layer.borderColor = syncBorderColor.cgColor
        captureField.textColor = Theme.textPrimary
        captureField.backgroundColor = Theme.surfaceHi
        tableView.backgroundColor = Theme.ink
        tableView.reloadData()
        rebuildFilterBar()
    }

    private func setupCaptureBar() {
        commandLabel.text = "COMMAND DECK"
        commandLabel.font = Theme.mono(11, .bold)
        commandLabel.textColor = Theme.textTertiary
        commandLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(commandLabel)

        syncPill.titleLabel?.font = Theme.mono(11, .semibold)
        syncPill.layer.cornerRadius = 14
        syncPill.layer.borderWidth = 1
        syncPill.contentEdgeInsets = UIEdgeInsets(top: 6, left: 11, bottom: 6, right: 11)
        syncPill.addAction(UIAction { [weak self] _ in self?.viewModel.refreshSyncSummary() }, for: .touchUpInside)
        syncPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(syncPill)
        updateSyncPill()

        captureField.placeholder = "Capture anything…"
        captureField.returnKeyType = .done
        captureField.autocorrectionType = .no
        captureField.clearButtonMode = .whileEditing
        captureField.delegate = self
        captureField.font = Theme.display(18, .medium)
        Theme.input(captureField)
        captureField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        captureField.leftViewMode = .always
        captureField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        captureField.rightViewMode = .always
        captureField.onPasteList = { [weak self] text in
            guard let self, self.viewModel.ingestIfList(text, options: self.captureOptions()) else { return false }
            self.captureField.text = ""
            return true
        }
        captureField.onPasteImages = { [weak self] images in
            self?.capture(images: images, suggestedName: nil)
            return true
        }
        captureField.addInteraction(UIDropInteraction(delegate: self))
        captureField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureField)

        attemptLabel.text = "Attempt after research"
        attemptLabel.font = Theme.display(12, .medium)
        attemptLabel.textColor = Theme.iris
        confirmPlanLabel.text = "Confirm plan"
        confirmPlanLabel.font = Theme.display(12, .medium)
        confirmPlanLabel.textColor = Theme.textSecondary
        attemptSwitch.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
        confirmPlanSwitch.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
        confirmPlanSwitch.isOn = true
        confirmPlanSwitch.isHidden = true
        confirmPlanLabel.isHidden = true
        attemptSwitch.addAction(UIAction { [weak self] _ in
            let enabled = self?.attemptSwitch.isOn == true
            self?.confirmPlanSwitch.isHidden = !enabled
            self?.confirmPlanLabel.isHidden = !enabled
        }, for: .valueChanged)
        automationStack.axis = .horizontal
        automationStack.spacing = 8
        automationStack.alignment = .center
        [attemptSwitch, attemptLabel, confirmPlanSwitch, confirmPlanLabel].forEach(automationStack.addArrangedSubview)
        automationStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(automationStack)
        NSLayoutConstraint.activate([
            commandLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            commandLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            syncPill.centerYAnchor.constraint(equalTo: commandLabel.centerYAnchor),
            syncPill.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            commandLabel.trailingAnchor.constraint(lessThanOrEqualTo: syncPill.leadingAnchor, constant: -10),

            captureField.topAnchor.constraint(equalTo: commandLabel.bottomAnchor, constant: 8),
            captureField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            captureField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            captureField.heightAnchor.constraint(equalToConstant: 54),
            automationStack.topAnchor.constraint(equalTo: captureField.bottomAnchor, constant: 6),
            automationStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            automationStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16)
        ])
    }

    private var syncBorderColor: UIColor {
        switch viewModel.syncSummary.state {
        case .aligned: return Theme.mint.withAlphaComponent(0.45)
        case .warning: return Theme.signal.withAlphaComponent(0.45)
        case .offline: return Theme.textTertiary.withAlphaComponent(0.45)
        case .checking: return Theme.iris.withAlphaComponent(0.45)
        }
    }

    private func updateSyncPill() {
        let summary = viewModel.syncSummary
        let color: UIColor
        switch summary.state {
        case .aligned: color = Theme.mint
        case .warning: color = Theme.signal
        case .offline: color = Theme.textTertiary
        case .checking: color = Theme.iris
        }
        syncPill.setTitle("● \(summary.title)", for: .normal)
        syncPill.setTitleColor(color, for: .normal)
        syncPill.backgroundColor = color.withAlphaComponent(0.12)
        syncPill.layer.borderColor = syncBorderColor.cgColor
        syncPill.accessibilityLabel = "\(summary.title). \(summary.detail). Double tap to refresh sync diagnostics."
    }

    /// Horizontal scrolling chip bar to "slice by tag or multiple tags" (AND filter).
    private func setupFilterBar() {
        filterBar.showsHorizontalScrollIndicator = false
        filterBar.translatesAutoresizingMaskIntoConstraints = false
        filterStack.axis = .horizontal
        filterStack.spacing = 8
        filterStack.translatesAutoresizingMaskIntoConstraints = false
        filterBar.addSubview(filterStack)
        view.addSubview(filterBar)
        let heightConstraint = filterBar.heightAnchor.constraint(equalToConstant: 34)
        filterHeightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            filterBar.topAnchor.constraint(equalTo: automationStack.bottomAnchor, constant: 8),
            filterBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            filterBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            heightConstraint,
            filterStack.topAnchor.constraint(equalTo: filterBar.topAnchor),
            filterStack.bottomAnchor.constraint(equalTo: filterBar.bottomAnchor),
            filterStack.leadingAnchor.constraint(equalTo: filterBar.leadingAnchor),
            filterStack.trailingAnchor.constraint(equalTo: filterBar.trailingAnchor),
            filterStack.heightAnchor.constraint(equalTo: filterBar.heightAnchor)
        ])
        rebuildFilterBar()
    }

    private func rebuildFilterBar() {
        filterStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let tags = viewModel.allTags
        filterBar.isHidden = tags.isEmpty
        filterHeightConstraint?.constant = tags.isEmpty ? 0 : 34
        guard !tags.isEmpty else { return }
        for tag in tags {
            let on = viewModel.isFiltering(tag.name)
            let tint = UIColor(hex: viewModel.color(forTag: tag.name)) ?? .systemGray
            var cfg = on ? UIButton.Configuration.filled() : UIButton.Configuration.tinted()
            cfg.title = tag.name
            cfg.buttonSize = .small
            cfg.baseBackgroundColor = tint
            cfg.baseForegroundColor = on ? .white : tint
            let b = UIButton(configuration: cfg)
            b.addAction(UIAction { [weak self] _ in self?.viewModel.toggleFilter(tag.name) }, for: .touchUpInside)
            filterStack.addArrangedSubview(b)
        }
        if !viewModel.tagFilter.isEmpty {
            let clear = UIButton(configuration: .plain())
            clear.configuration?.title = "Clear"
            clear.configuration?.buttonSize = .small
            clear.addAction(UIAction { [weak self] _ in self?.viewModel.clearFilter() }, for: .touchUpInside)
            filterStack.addArrangedSubview(clear)
        }
    }

    private func setupTable() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.ink
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 96
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(CaptureTaskCell.self, forCellReuseIdentifier: CaptureTaskCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 24, right: 0)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: filterBar.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Capture (instant)

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = textField.text ?? ""
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        textField.text = "" // instant clear = perceived speed
        viewModel.capture(text, options: captureOptions()) // background, not awaited
        return false // keep keyboard up for rapid capture
    }

    private func capture(images: [UIImage], suggestedName: String?) {
        let drafts = images.prefix(4).compactMap { ImageAttachmentEncoder.draft(from: $0, filename: suggestedName) }
        guard !drafts.isEmpty else {
            showBanner("That image was too large to attach.", isError: true)
            return
        }
        let text = (captureField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        captureField.text = ""
        viewModel.capture(text.isEmpty ? (drafts.first?.filename ?? "Image attachment") : text, attachments: drafts, options: captureOptions())
    }

    private func captureOptions() -> TaskStore.CaptureOptions {
        TaskStore.CaptureOptions(agentMode: attemptSwitch.isOn ? .attempt : .research, agentPlanConfirmation: confirmPlanSwitch.isOn)
    }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.canLoadObjects(ofClass: UIImage.self)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        session.loadObjects(ofClass: UIImage.self) { [weak self] objects in
            let images = objects.compactMap { $0 as? UIImage }
            guard !images.isEmpty else { return }
            DispatchQueue.main.async {
                self?.capture(images: images, suggestedName: nil)
            }
        }
    }

    // MARK: - Table (section 0 = proposed; sections 1… = active date buckets)

    private var sections: [TaskSection] {
        var sections: [TaskSection] = []
        if !viewModel.proposed.isEmpty { sections.append(.proposed(viewModel.proposed)) }
        sections.append(contentsOf: viewModel.activeGroups.map { .active($0.bucket, $0.items) })
        let done = viewModel.filteredDone
        if !done.isEmpty { sections.append(.done(done)) }
        let rejected = viewModel.filteredRejected
        if !rejected.isEmpty { sections.append(.rejected(rejected)) }
        return sections
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        max(sections.count, 1)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard !sections.isEmpty else { return nil }
        let label = UILabel()
        label.text = sections[section].title
        label.font = Theme.mono(11, .semibold)
        label.textColor = sectionColor(sections[section])
        label.layoutMargins = UIEdgeInsets(top: 12, left: 18, bottom: 6, right: 18)
        let container = UIView()
        container.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        sections.isEmpty ? 0 : 36
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard !sections.isEmpty else { return 1 }
        switch sections[section] {
        case let .proposed(items), let .done(items), let .rejected(items): return items.count
        case let .active(_, items): return items.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard !sections.isEmpty else {
            let cell = tableView.dequeueReusableCell(withIdentifier: CaptureTaskCell.reuseIdentifier, for: indexPath) as! CaptureTaskCell
            cell.configureEmpty()
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: CaptureTaskCell.reuseIdentifier, for: indexPath) as! CaptureTaskCell
        let color: (String) -> String = { [weak self] in self?.viewModel.color(forTag: $0) ?? TagPalette.color(for: $0) }
        switch sections[indexPath.section] {
        case let .proposed(items):
            let item = items[indexPath.row]
            cell.configure(
                item,
                kind: .proposed,
                meta: proposalHint(item),
                colourForTag: color,
                onPrimary: { [weak self] in
                    self?.viewModel.confirm(item, title: item.title, dueAt: item.suggestedDueAt, category: item.suggestedCategory, tags: item.tags)
                },
                onSecondary: { [weak self] in self?.viewModel.reject(item) }
            )
        case let .active(_, items):
            let item = items[indexPath.row]
            cell.configure(
                item,
                kind: .active,
                meta: activeSubtitle(item),
                colourForTag: color,
                onPrimary: { [weak self] in self?.viewModel.setDone(item, true) },
                onSecondary: nil
            )
        case let .done(items):
            let item = items[indexPath.row]
            cell.configure(
                item,
                kind: .done,
                meta: activeSubtitle(item),
                colourForTag: color,
                onPrimary: { [weak self] in self?.viewModel.setDone(item, false) },
                onSecondary: nil
            )
        case let .rejected(items):
            let item = items[indexPath.row]
            cell.configure(
                item,
                kind: .rejected,
                meta: rejectedSubtitle(item),
                colourForTag: color,
                onPrimary: nil,
                onSecondary: nil
            )
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if case .rejected? = sections[safe: indexPath.section] { return }
        guard let item = item(at: indexPath) else { return }
        navigationController?.pushViewController(TaskDetailViewController(viewModel: viewModel, item: item), animated: true)
    }

    /// Trailing swipe on an active row: edit its due date (presets + a picker), or mark done.
    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        if case .proposed? = sections[safe: indexPath.section], let item = item(at: indexPath) {
            let reject = UIContextualAction(style: .destructive, title: "Reject") { [weak self] _, _, done in
                self?.viewModel.reject(item)
                done(true)
            }
            let confirm = UIContextualAction(style: .normal, title: "Confirm") { [weak self] _, _, done in
                self?.viewModel.confirm(item, title: item.title, dueAt: item.suggestedDueAt, category: item.suggestedCategory, tags: item.tags)
                done(true)
            }
            confirm.backgroundColor = Theme.signal
            return UISwipeActionsConfiguration(actions: [reject, confirm])
        }
        guard let item = item(at: indexPath), item.status != .done, item.status != .cancelled else { return nil }
        let date = UIContextualAction(style: .normal, title: "Date") { [weak self] _, _, done in
            self?.presentDateEditor(for: item)
            done(true)
        }
        date.backgroundColor = Theme.iris
        let complete = UIContextualAction(style: .normal, title: item.status == .done ? "Reopen" : "Done") { [weak self] _, _, done in
            self?.viewModel.setDone(item, item.status != .done)
            done(true)
        }
        complete.backgroundColor = Theme.mint
        return UISwipeActionsConfiguration(actions: [complete, date])
    }

    func tableView(_ tableView: UITableView,
                   leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard case .proposed? = sections[safe: indexPath.section], let item = item(at: indexPath) else { return nil }
        let confirm = UIContextualAction(style: .normal, title: "Confirm") { [weak self] _, _, done in
            self?.viewModel.confirm(item, title: item.title, dueAt: item.suggestedDueAt, category: item.suggestedCategory, tags: item.tags)
            done(true)
        }
        confirm.backgroundColor = Theme.signal
        let config = UISwipeActionsConfiguration(actions: [confirm])
        config.performsFirstActionWithFullSwipe = true
        return config
    }

    private func presentDateEditor(for item: TaskItem) {
        let sheet = UIAlertController(title: "Set due date", message: nil, preferredStyle: .actionSheet)
        for preset in DatePreset.settable {
            sheet.addAction(UIAlertAction(title: preset.label, style: .default) { [weak self] _ in
                self?.viewModel.setDue(item, preset.date())
            })
        }
        sheet.addAction(UIAlertAction(title: "Pick date…", style: .default) { [weak self] _ in
            self?.presentDatePicker(for: item)
        })
        if item.dueAt != nil {
            sheet.addAction(UIAlertAction(title: "Clear date", style: .destructive) { [weak self] _ in
                self?.viewModel.setDue(item, nil)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        present(sheet, animated: true)
    }

    private func presentDatePicker(for item: TaskItem) {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .inline
        picker.date = item.dueAt ?? Date()
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        picker.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            picker.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])
        let nav = UINavigationController(rootViewController: vc)
        vc.title = "Due date"
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .save, primaryAction: UIAction { [weak self, weak nav] _ in
            self?.viewModel.setDue(item, picker.date)
            nav?.dismiss(animated: true)
        })
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak nav] _ in
            nav?.dismiss(animated: true)
        })
        present(nav, animated: true)
    }

    private func proposalHint(_ item: TaskItem) -> String {
        var parts: [String] = []
        if let due = item.suggestedDueAt { parts.append(DueFormatter.short(due)) }
        if let cat = item.suggestedCategory { parts.append(cat) }
        parts.append(contentsOf: item.tags.map { "#\($0)" })
        return parts.isEmpty ? "tap to confirm" : "suggested: " + parts.joined(separator: " · ")
    }

    private func activeSubtitle(_ item: TaskItem) -> String? {
        var parts: [String] = []
        if let due = item.dueAt { parts.append(DueFormatter.short(due)) }
        if let cat = item.category { parts.append(cat) }
        parts.append(contentsOf: item.tags.map { "#\($0)" })
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func item(at indexPath: IndexPath) -> TaskItem? {
        guard let section = sections[safe: indexPath.section] else { return nil }
        switch section {
        case let .proposed(items), let .done(items), let .rejected(items):
            return items[safe: indexPath.row]
        case let .active(_, items):
            return items[safe: indexPath.row]
        }
    }

    private func sectionColor(_ section: TaskSection) -> UIColor {
        switch section {
        case .proposed: return Theme.signal
        case let .active(bucket, _):
            if bucket == .overdue { return Theme.danger }
            if bucket == .today { return Theme.iris }
            return Theme.textTertiary
        case .done: return Theme.mint
        case .rejected: return Theme.textTertiary
        }
    }

    private func rejectedSubtitle(_ item: TaskItem) -> String? {
        item.updatedAt.map { "Rejected \(DueFormatter.short($0))" } ?? "Rejected"
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private final class CaptureTaskCell: UITableViewCell {
    enum Kind { case proposed, active, done, rejected }

    static let reuseIdentifier = "CaptureTaskCell"

    private let card = UIView()
    private let statusLabel = UILabel()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let chips = UIStackView()
    private let primary = UIButton(type: .system)
    private let secondary = UIButton(type: .system)
    private let textStack = UIStackView()
    private let actionStack = UIStackView()
    private var onPrimary: (() -> Void)?
    private var onSecondary: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onPrimary = nil
        onSecondary = nil
        chips.arrangedSubviews.forEach { $0.removeFromSuperview() }
        secondary.isHidden = true
        actionStack.isHidden = false
    }

    private func build() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        card.translatesAutoresizingMaskIntoConstraints = false
        Theme.card(card, color: Theme.surface)
        contentView.addSubview(card)

        statusLabel.font = Theme.mono(10, .bold)
        statusLabel.numberOfLines = 1

        titleLabel.font = Theme.display(16, .semibold)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.numberOfLines = 2

        metaLabel.font = Theme.mono(11, .semibold)
        metaLabel.textColor = Theme.textTertiary
        metaLabel.numberOfLines = 2

        chips.axis = .horizontal
        chips.spacing = 5
        chips.alignment = .leading

        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.alignment = .leading
        textStack.addArrangedSubview(statusLabel)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(metaLabel)
        textStack.addArrangedSubview(chips)

        primary.addAction(UIAction { [weak self] _ in self?.onPrimary?() }, for: .touchUpInside)
        secondary.addAction(UIAction { [weak self] _ in self?.onSecondary?() }, for: .touchUpInside)

        actionStack.axis = .vertical
        actionStack.spacing = 8
        actionStack.alignment = .fill
        actionStack.addArrangedSubview(primary)
        actionStack.addArrangedSubview(secondary)
        primary.widthAnchor.constraint(greaterThanOrEqualToConstant: 86).isActive = true

        let row = UIStackView(arrangedSubviews: [textStack, actionStack])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),

            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
    }

    func configureEmpty() {
        Theme.card(card, color: Theme.surface)
        statusLabel.text = "READY"
        statusLabel.textColor = Theme.textTertiary
        titleLabel.text = "Nothing active yet"
        titleLabel.textColor = Theme.textPrimary
        metaLabel.text = "Capture a thought above. It will land as a proposal before it becomes real work."
        metaLabel.textColor = Theme.textSecondary
        actionStack.isHidden = true
    }

    func configure(
        _ item: TaskItem,
        kind: Kind,
        meta: String?,
        colourForTag: (String) -> String,
        onPrimary: (() -> Void)?,
        onSecondary: (() -> Void)?
    ) {
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
        let done = kind == .done
        let rejected = kind == .rejected
        let proposed = kind == .proposed

        Theme.card(card, color: proposed ? Theme.surfaceRaised : Theme.surface)
        card.layer.borderColor = (proposed ? Theme.signal.withAlphaComponent(0.45) : Theme.hairline).cgColor

        statusLabel.text = proposed ? "STRUCTURE CHECK" : done ? "DONE" : rejected ? "REJECTED" : "ACTIVE"
        statusLabel.textColor = proposed ? Theme.signal : done ? Theme.mint : Theme.textTertiary
        titleLabel.text = item.title
        titleLabel.textColor = (done || rejected) ? Theme.textTertiary : Theme.textPrimary
        metaLabel.text = meta ?? (proposed ? "awaiting signal" : "no metadata")
        metaLabel.textColor = proposed ? Theme.iris : Theme.textTertiary

        chips.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tag in item.tags.prefix(4) {
            chips.addArrangedSubview(chip(text: tag, hex: colourForTag(tag)))
        }
        chips.isHidden = item.tags.isEmpty

        primary.isHidden = onPrimary == nil
        secondary.isHidden = onSecondary == nil
        primary.setTitle(proposed ? "Confirm" : done ? "Reopen" : "Done", for: .normal)
        if proposed {
            Theme.primary(primary)
        } else {
            Theme.quiet(primary, colour: done ? Theme.textSecondary : Theme.mint)
        }
        secondary.setTitle("Reject", for: .normal)
        Theme.quiet(secondary, colour: Theme.danger)
        actionStack.isHidden = onPrimary == nil && onSecondary == nil
    }

    private func chip(text: String, hex: String) -> UILabel {
        let label = PaddedLabel()
        label.text = text
        label.font = Theme.mono(10, .semibold)
        let colour = UIColor(hex: hex) ?? Theme.textSecondary
        label.textColor = colour
        label.backgroundColor = colour.withAlphaComponent(0.16)
        label.layer.cornerRadius = 7
        label.layer.borderWidth = 1
        label.layer.borderColor = colour.withAlphaComponent(0.36).cgColor
        label.layer.masksToBounds = true
        return label
    }
}

private final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }
}

extension UIColor {
    /// Parse a `#rrggbb` (or `rrggbb`) hex string into a colour; nil if malformed.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
