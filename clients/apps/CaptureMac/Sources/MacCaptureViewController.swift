import AppKit
import CaptureCore

final class MacCaptureViewController: NSViewController {
    private let viewModel: MacViewModel
    private let captureField = AttachmentCaptureTextField()
    private let settingsButton = NSButton(title: "Settings", target: nil, action: nil)
    private let proposedTable = FastConfirmTableView()
    private let activeTable = NSTableView()
    private let proposedHeader = NSTextField(labelWithString: "")
    private let activeHeader = NSTextField(labelWithString: "ACTIVE")
    private let filterBar = NSStackView()
    private let listPane = NSView()
    private let detailScroll = NSScrollView()
    private let detailView = MacTaskDetailView()
    var onOpenSettings: (() -> Void)?

    init(viewModel: MacViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1180, height: 760))
        Theme.paintInk(view)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        viewModel.addObserver { [weak self] in self?.reload() }
        viewModel.start()
    }

    func focusCapture() {
        view.window?.makeFirstResponder(captureField)
    }

    func applyTheme() {
        Theme.paintInk(view)
        Theme.paintInk(listPane)
        view.window?.backgroundColor = Theme.ink
        captureField.textColor = Theme.textPrimary
        settingsButton.contentTintColor = Theme.textSecondary
        proposedHeader.textColor = Theme.signal
        activeHeader.textColor = Theme.textTertiary
        detailView.applyTheme()
        proposedTable.reloadData()
        activeTable.reloadData()
        rebuildFilterBar()
    }

    /// Custom field editor that turns a pasted markdown / checkbox list into individual items.
    private lazy var pasteFieldEditor: CapturePasteTextView = {
        let tv = CapturePasteTextView()
        tv.isFieldEditor = true
        tv.onPasteList = { [weak self] text in
            guard let self, self.viewModel.ingestIfList(text) else { return false }
            self.captureField.stringValue = ""
            return true
        }
        tv.onPasteImages = { [weak self] images in
            self?.capture(images: images)
            return true
        }
        return tv
    }()

    /// Called by the window delegate; returns our paste-aware editor for the capture field only.
    func fieldEditor(for client: Any?) -> NSText? {
        (client as AnyObject) === captureField ? pasteFieldEditor : nil
    }

    private func buildUI() {
        listPane.translatesAutoresizingMaskIntoConstraints = false
        Theme.paintInk(listPane)
        view.addSubview(listPane)

        detailView.frame = NSRect(x: 0, y: 0, width: 410, height: 820)
        detailView.autoresizingMask = [.width]
        detailScroll.documentView = detailView
        detailScroll.hasVerticalScroller = true
        detailScroll.drawsBackground = false
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(detailScroll)

        captureField.placeholderString = "Capture anything…  (⌥Space to summon)"
        captureField.font = Theme.display(18, .medium)
        captureField.textColor = Theme.textPrimary
        captureField.target = self
        captureField.action = #selector(captureSubmit)
        captureField.bezelStyle = .roundedBezel
        captureField.focusRingType = .none
        captureField.translatesAutoresizingMaskIntoConstraints = false
        captureField.onDroppedImages = { [weak self] images in self?.capture(images: images) }

        settingsButton.target = self
        settingsButton.action = #selector(settingsTapped)
        settingsButton.bezelStyle = .rounded
        settingsButton.font = Theme.display(12, .semibold)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        proposedHeader.font = Theme.mono(11, .semibold)
        proposedHeader.textColor = Theme.signal
        proposedHeader.translatesAutoresizingMaskIntoConstraints = false

        activeHeader.font = Theme.mono(11, .semibold)
        activeHeader.textColor = Theme.textTertiary
        activeHeader.translatesAutoresizingMaskIntoConstraints = false

        filterBar.orientation = .horizontal
        filterBar.spacing = 6
        filterBar.translatesAutoresizingMaskIntoConstraints = false

        configure(table: proposedTable, identifier: "proposed")
        configure(table: activeTable, identifier: "active")
        proposedTable.onConfirmSelected = { [weak self] in self?.confirmSelectedProposal() }
        proposedTable.onRejectSelected = { [weak self] in self?.rejectSelectedProposal() }
        proposedTable.onEditSelected = { [weak self] in self?.selectProposedForEditing() }
        let proposedScroll = scroll(proposedTable)
        let activeScroll = scroll(activeTable)

        [captureField, settingsButton, proposedHeader, proposedScroll, activeHeader, filterBar, activeScroll].forEach {
            listPane.addSubview($0)
        }

        NSLayoutConstraint.activate([
            listPane.topAnchor.constraint(equalTo: view.topAnchor),
            listPane.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listPane.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            listPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 540),

            detailScroll.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            detailScroll.leadingAnchor.constraint(equalTo: listPane.trailingAnchor, constant: 10),
            detailScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            detailScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            detailScroll.widthAnchor.constraint(equalToConstant: 410),

            captureField.topAnchor.constraint(equalTo: listPane.topAnchor, constant: 16),
            captureField.leadingAnchor.constraint(equalTo: listPane.leadingAnchor, constant: 16),
            captureField.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -10),

            settingsButton.centerYAnchor.constraint(equalTo: captureField.centerYAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: listPane.trailingAnchor, constant: -16),
            settingsButton.widthAnchor.constraint(equalToConstant: 92),

            proposedHeader.topAnchor.constraint(equalTo: captureField.bottomAnchor, constant: 16),
            proposedHeader.leadingAnchor.constraint(equalTo: listPane.leadingAnchor, constant: 18),

            proposedScroll.topAnchor.constraint(equalTo: proposedHeader.bottomAnchor, constant: 4),
            proposedScroll.leadingAnchor.constraint(equalTo: listPane.leadingAnchor, constant: 16),
            proposedScroll.trailingAnchor.constraint(equalTo: listPane.trailingAnchor, constant: -16),
            proposedScroll.heightAnchor.constraint(equalToConstant: 180),

            activeHeader.topAnchor.constraint(equalTo: proposedScroll.bottomAnchor, constant: 16),
            activeHeader.leadingAnchor.constraint(equalTo: listPane.leadingAnchor, constant: 18),

            filterBar.topAnchor.constraint(equalTo: activeHeader.bottomAnchor, constant: 6),
            filterBar.leadingAnchor.constraint(equalTo: listPane.leadingAnchor, constant: 16),
            filterBar.trailingAnchor.constraint(lessThanOrEqualTo: listPane.trailingAnchor, constant: -16),

            activeScroll.topAnchor.constraint(equalTo: filterBar.bottomAnchor, constant: 6),
            activeScroll.leadingAnchor.constraint(equalTo: listPane.leadingAnchor, constant: 16),
            activeScroll.trailingAnchor.constraint(equalTo: listPane.trailingAnchor, constant: -16),
            activeScroll.bottomAnchor.constraint(equalTo: listPane.bottomAnchor, constant: -16)
        ])
        reload()
    }

    private func configure(table: NSTableView, identifier: String) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = identifier == "proposed" ? 78 : 36
        table.dataSource = self
        table.delegate = self
        table.identifier = NSUserInterfaceItemIdentifier(identifier)
        table.style = .inset
    }

    private func scroll(_ table: NSTableView) -> NSScrollView {
        let s = NSScrollView()
        s.documentView = table
        s.hasVerticalScroller = true
        s.drawsBackground = false
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    /// Rebuild the tag filter chip row from the synced tags ("slice by tag or multiple tags").
    private func rebuildFilterBar() {
        filterBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !viewModel.allTags.isEmpty else { filterBar.isHidden = true; return }
        filterBar.isHidden = false
        let label = NSTextField(labelWithString: "Filter")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        filterBar.addArrangedSubview(label)
        for tag in viewModel.allTags {
            let on = viewModel.isFiltering(tag.name)
            let b = NSButton(title: tag.name, target: self, action: #selector(filterTapped(_:)))
            b.bezelStyle = .badge
            b.controlSize = .small
            b.font = .systemFont(ofSize: 11, weight: on ? .semibold : .regular)
            b.contentTintColor = on ? NSColor(hex: viewModel.color(forTag: tag.name)) : .secondaryLabelColor
            b.state = on ? .on : .off
            b.identifier = NSUserInterfaceItemIdentifier(tag.name)
            filterBar.addArrangedSubview(b)
        }
        if !viewModel.tagFilter.isEmpty {
            let clear = NSButton(title: "Clear", target: self, action: #selector(clearFilterTapped))
            clear.bezelStyle = .inline
            clear.controlSize = .small
            filterBar.addArrangedSubview(clear)
        }
    }

    private func reload() {
        proposedHeader.stringValue = viewModel.proposed.isEmpty
            ? "NOTHING TO CONFIRM"
            : "NEEDS CONFIRMING · \(viewModel.proposed.count)"
        proposedHeader.textColor = viewModel.proposed.isEmpty ? Theme.textTertiary : Theme.signal
        let filtered = viewModel.filteredActiveCount
        activeHeader.stringValue = viewModel.tagFilter.isEmpty
            ? "ACTIVE · \(filtered)"
            : "ACTIVE · \(filtered) of \(viewModel.active.count)"
        rebuildFilterBar()
        proposedTable.reloadData()
        activeTable.reloadData()
        let color: (String) -> String = { [weak self] in self?.viewModel.color(forTag: $0) ?? TagPalette.color(for: $0) }
        detailView.render(
            task: viewModel.selectedTask,
            events: viewModel.selectedEvents,
            attachments: viewModel.selectedAttachments,
            rollup: viewModel.selectedRollup,
            colourForTag: color,
            onSave: { [weak self] form in self?.viewModel.saveDetail(form) },
            onConfirm: { [weak self] form in self?.viewModel.confirmDetail(form) },
            onReject: { [weak self] in self?.viewModel.rejectSelected() },
            onDone: { [weak self] done in
                guard let item = self?.viewModel.selectedTask else { return }
                self?.viewModel.setDone(item, done)
            }
        )
    }

    @objc private func filterTapped(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue else { return }
        viewModel.toggleFilter(name)
    }

    @objc private func clearFilterTapped() { viewModel.clearFilter() }

    @objc private func settingsTapped() { onOpenSettings?() }

    @objc private func captureSubmit() {
        let text = captureField.stringValue
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        captureField.stringValue = "" // instant clear
        viewModel.capture(text)
    }

    private func capture(images: [NSImage]) {
        let drafts = images.prefix(4).compactMap { MacImageAttachmentEncoder.draft(from: $0) }
        guard !drafts.isEmpty else { return }
        let text = captureField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        captureField.stringValue = ""
        viewModel.capture(text.isEmpty ? (drafts.first?.filename ?? "Image attachment") : text, attachments: drafts)
    }

    private func selectedProposal() -> TaskItem? {
        let row = proposedTable.selectedRow
        guard row >= 0, row < viewModel.proposed.count else { return nil }
        return viewModel.proposed[row]
    }

    private func confirmSelectedProposal() {
        guard let item = selectedProposal() else { return }
        viewModel.confirm(item)
    }

    private func rejectSelectedProposal() {
        guard let item = selectedProposal() else { return }
        viewModel.reject(item)
    }

    private func selectProposedForEditing() {
        guard let item = selectedProposal() else { return }
        viewModel.select(item)
    }
}

private final class FastConfirmTableView: NSTableView {
    var onConfirmSelected: (() -> Void)?
    var onRejectSelected: (() -> Void)?
    var onEditSelected: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        guard selectedRow >= 0,
              let chars = event.charactersIgnoringModifiers?.lowercased() else {
            super.keyDown(with: event)
            return
        }
        switch chars {
        case "\r", "y":
            onConfirmSelected?()
        case "\u{1b}", "n", "\u{7f}":
            onRejectSelected?()
        case "e":
            onEditSelected?()
        default:
            super.keyDown(with: event)
        }
    }
}

extension MacCaptureViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView == proposedTable ? viewModel.proposed.count : viewModel.activeRows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView == proposedTable { return 78 }
        if case .header = viewModel.activeRows[row] { return 24 }
        return 36
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let color: (String) -> String = { [weak self] in self?.viewModel.color(forTag: $0) ?? TagPalette.color(for: $0) }
        if tableView == proposedTable {
            let item = viewModel.proposed[row]
            return ProposedRowView(item: item, color: color) { [weak self] in
                self?.viewModel.confirm(item)
            } onReject: { [weak self] in
                self?.viewModel.reject(item)
            }
        }
        switch viewModel.activeRows[row] {
        case let .header(label, count):
            return DateBucketHeaderView(label: label, count: count)
        case let .task(item):
            return ActiveRowView(item: item, color: color) { [weak self] done in
                self?.viewModel.setDone(item, done)
            } onSetDue: { [weak self] date in
                self?.viewModel.setDue(item, date)
            }
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if tableView == activeTable, case .header = viewModel.activeRows[row] { return false }
        return true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        let row = table.selectedRow
        guard row >= 0 else { return }
        if table == proposedTable {
            viewModel.select(viewModel.proposed[row])
        } else if table == activeTable, case let .task(item) = viewModel.activeRows[row] {
            viewModel.select(item)
        }
    }
}
