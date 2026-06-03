import UIKit
import CaptureCore

/// Capture field that intercepts paste: a pasted markdown / checkbox list is ingested as
/// individual items instead of pasting collapsed single-line text.
final class CapturePasteTextField: UITextField {
    var onPasteList: ((String) -> Bool)?

    override func paste(_ sender: Any?) {
        if let s = UIPasteboard.general.string, onPasteList?(s) == true { return }
        super.paste(sender)
    }
}

final class CaptureViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private let viewModel: CaptureViewModel
    private let captureField = CapturePasteTextField()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let filterBar = UIScrollView()
    private let filterStack = UIStackView()

    init(viewModel: CaptureViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Capture"
        view.backgroundColor = Theme.ink
        setupCaptureBar()
        setupFilterBar()
        setupTable()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Sign Out", style: .plain, target: self, action: #selector(signOut))

        viewModel.onChange = { [weak self] in
            self?.rebuildFilterBar()
            self?.tableView.reloadData()
        }
        viewModel.start()
    }

    @objc private func signOut() {
        Task {
            await viewModel.auth.signOut()
            await viewModel.store.clearActiveUser()
        }
    }

    private func setupCaptureBar() {
        captureField.placeholder = "Capture anything…"
        captureField.borderStyle = .roundedRect
        captureField.returnKeyType = .done
        captureField.autocorrectionType = .no
        captureField.clearButtonMode = .whileEditing
        captureField.delegate = self
        captureField.font = .systemFont(ofSize: 18)
        captureField.onPasteList = { [weak self] text in
            guard let self, self.viewModel.ingestIfList(text) else { return false }
            self.captureField.text = ""
            return true
        }
        captureField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureField)
        NSLayoutConstraint.activate([
            captureField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            captureField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            captureField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            captureField.heightAnchor.constraint(equalToConstant: 44)
        ])
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
        NSLayoutConstraint.activate([
            filterBar.topAnchor.constraint(equalTo: captureField.bottomAnchor, constant: 8),
            filterBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            filterBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
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
        viewModel.capture(text) // background, not awaited
        return false // keep keyboard up for rapid capture
    }

    // MARK: - Table (section 0 = proposed; sections 1… = active date buckets)

    private func activeGroup(for section: Int) -> (bucket: DateBucket, items: [TaskItem]) {
        viewModel.activeGroups[section - 1]
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        1 + viewModel.activeGroups.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return viewModel.proposed.isEmpty ? nil : "Needs confirming · \(viewModel.proposed.count)"
        }
        let group = activeGroup(for: section)
        return "\(group.bucket.label) · \(group.items.count)"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? viewModel.proposed.count : activeGroup(for: section).items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.backgroundColor = Theme.surface
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let item = viewModel.proposed[indexPath.row]
            config.text = item.title
            config.textProperties.font = Theme.display(16, .semibold)
            config.secondaryText = proposalHint(item)
            config.secondaryTextProperties.color = Theme.signal
            config.secondaryTextProperties.font = Theme.mono(12)
            cell.accessoryType = .disclosureIndicator
            cell.tintColor = Theme.signal
        } else {
            let item = activeGroup(for: indexPath.section).items[indexPath.row]
            config.text = item.title
            config.textProperties.font = Theme.display(16, .regular)
            config.secondaryText = activeSubtitle(item)
            config.secondaryTextProperties.color = Theme.textTertiary
            config.secondaryTextProperties.font = Theme.mono(12)
            cell.accessoryType = item.status == .done ? .checkmark : .none
            cell.tintColor = Theme.mint
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            let item = viewModel.proposed[indexPath.row]
            let vc = ConfirmViewController(item: item) { [weak self] action in
                switch action {
                case let .confirm(title, due, category):
                    self?.viewModel.confirm(item, title: title, dueAt: due, category: category, tags: item.tags)
                case .reject:
                    self?.viewModel.reject(item)
                }
            }
            present(UINavigationController(rootViewController: vc), animated: true)
        } else {
            let item = activeGroup(for: indexPath.section).items[indexPath.row]
            viewModel.setDone(item, true)
        }
    }

    /// Trailing swipe on an active row: edit its due date (presets + a picker), or mark done.
    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section > 0 else { return nil }
        let item = activeGroup(for: indexPath.section).items[indexPath.row]
        let date = UIContextualAction(style: .normal, title: "Date") { [weak self] _, _, done in
            self?.presentDateEditor(for: item)
            done(true)
        }
        date.backgroundColor = Theme.iris
        return UISwipeActionsConfiguration(actions: [date])
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
