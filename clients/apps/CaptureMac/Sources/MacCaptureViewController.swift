import AppKit
import CaptureCore

final class MacCaptureViewController: NSViewController {
    private let viewModel: MacViewModel
    private let captureField = NSTextField()
    private let proposedTable = NSTableView()
    private let activeTable = NSTableView()
    private let proposedHeader = NSTextField(labelWithString: "")
    private let activeHeader = NSTextField(labelWithString: "ACTIVE")
    private let filterBar = NSStackView()

    init(viewModel: MacViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 620))
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

    /// Custom field editor that turns a pasted markdown / checkbox list into individual items.
    private lazy var pasteFieldEditor: CapturePasteTextView = {
        let tv = CapturePasteTextView()
        tv.isFieldEditor = true
        tv.onPasteList = { [weak self] text in
            guard let self, self.viewModel.ingestIfList(text) else { return false }
            self.captureField.stringValue = ""
            return true
        }
        return tv
    }()

    /// Called by the window delegate; returns our paste-aware editor for the capture field only.
    func fieldEditor(for client: Any?) -> NSText? {
        (client as AnyObject) === captureField ? pasteFieldEditor : nil
    }

    private func buildUI() {
        captureField.placeholderString = "Capture anything…  (⌥Space to summon)"
        captureField.font = .systemFont(ofSize: 18)
        captureField.target = self
        captureField.action = #selector(captureSubmit)
        captureField.bezelStyle = .roundedBezel
        captureField.translatesAutoresizingMaskIntoConstraints = false

        proposedHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        proposedHeader.textColor = .secondaryLabelColor
        proposedHeader.translatesAutoresizingMaskIntoConstraints = false

        activeHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        activeHeader.textColor = .secondaryLabelColor
        activeHeader.translatesAutoresizingMaskIntoConstraints = false

        filterBar.orientation = .horizontal
        filterBar.spacing = 6
        filterBar.translatesAutoresizingMaskIntoConstraints = false

        configure(table: proposedTable, identifier: "proposed")
        configure(table: activeTable, identifier: "active")
        let proposedScroll = scroll(proposedTable)
        let activeScroll = scroll(activeTable)

        [captureField, proposedHeader, proposedScroll, activeHeader, filterBar, activeScroll].forEach {
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            captureField.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            captureField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            captureField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            proposedHeader.topAnchor.constraint(equalTo: captureField.bottomAnchor, constant: 16),
            proposedHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),

            proposedScroll.topAnchor.constraint(equalTo: proposedHeader.bottomAnchor, constant: 4),
            proposedScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            proposedScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            proposedScroll.heightAnchor.constraint(equalToConstant: 180),

            activeHeader.topAnchor.constraint(equalTo: proposedScroll.bottomAnchor, constant: 16),
            activeHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),

            filterBar.topAnchor.constraint(equalTo: activeHeader.bottomAnchor, constant: 6),
            filterBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            filterBar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),

            activeScroll.topAnchor.constraint(equalTo: filterBar.bottomAnchor, constant: 6),
            activeScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            activeScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            activeScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
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
        let filtered = viewModel.filteredActiveCount
        activeHeader.stringValue = viewModel.tagFilter.isEmpty
            ? "ACTIVE · \(filtered)"
            : "ACTIVE · \(filtered) of \(viewModel.active.count)"
        rebuildFilterBar()
        proposedTable.reloadData()
        activeTable.reloadData()
    }

    @objc private func filterTapped(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue else { return }
        viewModel.toggleFilter(name)
    }

    @objc private func clearFilterTapped() { viewModel.clearFilter() }

    @objc private func captureSubmit() {
        let text = captureField.stringValue
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        captureField.stringValue = "" // instant clear
        viewModel.capture(text)
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
}
