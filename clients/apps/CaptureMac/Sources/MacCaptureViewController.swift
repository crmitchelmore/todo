import AppKit
import CaptureCore

final class MacCaptureViewController: NSViewController {
    private enum Layout {
        static let minListWidth: CGFloat = 540
        static let minDetailWidth: CGFloat = 560
        static let defaultDetailWidth: CGFloat = 680
        static let maxDefaultDetailWidth: CGFloat = 860
        static let minProposedHeight: CGFloat = 180
        static let defaultProposedHeight: CGFloat = 260
        static let minActiveHeight: CGFloat = 280
        static let dividerDefaultsKey = "capture.mac.detailPaneWidth"
    }

    private let viewModel: MacViewModel
    private let splitView = NSSplitView()
    private let captureField = AttachmentCaptureTextField()
    private let settingsButton = NSButton(title: "Settings", target: nil, action: nil)
    private let proposedTable = FastConfirmTableView()
    private let activeTable = NSTableView()
    private let proposedHeader = NSTextField(labelWithString: "")
    private let activeHeader = NSTextField(labelWithString: "ACTIVE")
    private let commandLabel = NSTextField(labelWithString: "COMMAND DECK")
    private let filterBar = NSStackView()
    private let listPane = NSView()
    private let proposedScroll = NSScrollView()
    private let activeScroll = NSScrollView()
    private let detailScroll = NSScrollView()
    private let detailView = MacTaskDetailView()
    private var didRestoreSplitPosition = false
    private var proposedHeightConstraint: NSLayoutConstraint?
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

    override func viewDidLayout() {
        super.viewDidLayout()
        restoreSplitPositionIfNeeded()
        updateProposedHeight()
        resizeDetailDocument()
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
        commandLabel.textColor = Theme.textTertiary
        proposedHeader.textColor = Theme.signal
        activeHeader.textColor = Theme.textTertiary
        styleScrollSurfaces()
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
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)

        listPane.translatesAutoresizingMaskIntoConstraints = false
        Theme.paintInk(listPane)
        splitView.addArrangedSubview(listPane)

        detailView.frame = NSRect(x: 0, y: 0, width: Layout.defaultDetailWidth, height: 820)
        detailView.autoresizingMask = [.width]
        detailScroll.documentView = detailView
        detailScroll.hasVerticalScroller = true
        detailScroll.hasHorizontalScroller = false
        detailScroll.drawsBackground = false
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        detailScroll.scrollerStyle = .overlay
        detailScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollContentBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: detailScroll.contentView
        )
        splitView.addArrangedSubview(detailScroll)

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
        settingsButton.title = "⚙︎"
        settingsButton.bezelStyle = .rounded
        settingsButton.font = Theme.display(12, .semibold)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.toolTip = "Settings"

        commandLabel.font = Theme.mono(10, .bold)
        commandLabel.textColor = Theme.textTertiary
        commandLabel.translatesAutoresizingMaskIntoConstraints = false

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
        configure(scroll: proposedScroll, table: proposedTable)
        configure(scroll: activeScroll, table: activeTable)

        [commandLabel, captureField, settingsButton, proposedHeader, proposedScroll, activeHeader, filterBar, activeScroll].forEach {
            listPane.addSubview($0)
        }
        styleScrollSurfaces()
        let proposedHeight = proposedScroll.heightAnchor.constraint(equalToConstant: Layout.defaultProposedHeight)
        proposedHeightConstraint = proposedHeight

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            listPane.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.minListWidth),
            detailScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.minDetailWidth),

            commandLabel.topAnchor.constraint(equalTo: listPane.topAnchor, constant: 18),
            commandLabel.leadingAnchor.constraint(equalTo: listPane.leadingAnchor, constant: 22),

            captureField.topAnchor.constraint(equalTo: commandLabel.bottomAnchor, constant: 6),
            captureField.leadingAnchor.constraint(equalTo: listPane.leadingAnchor, constant: 18),
            captureField.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -10),

            settingsButton.centerYAnchor.constraint(equalTo: captureField.centerYAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: listPane.trailingAnchor, constant: -18),
            settingsButton.widthAnchor.constraint(equalToConstant: 44),

            proposedHeader.topAnchor.constraint(equalTo: captureField.bottomAnchor, constant: 18),
            proposedHeader.leadingAnchor.constraint(equalTo: listPane.leadingAnchor, constant: 22),

            proposedScroll.topAnchor.constraint(equalTo: proposedHeader.bottomAnchor, constant: 8),
            proposedScroll.leadingAnchor.constraint(equalTo: listPane.leadingAnchor, constant: 18),
            proposedScroll.trailingAnchor.constraint(equalTo: listPane.trailingAnchor, constant: -18),
            proposedHeight,

            activeHeader.topAnchor.constraint(equalTo: proposedScroll.bottomAnchor, constant: 18),
            activeHeader.leadingAnchor.constraint(equalTo: listPane.leadingAnchor, constant: 22),

            filterBar.topAnchor.constraint(equalTo: activeHeader.bottomAnchor, constant: 6),
            filterBar.leadingAnchor.constraint(equalTo: listPane.leadingAnchor, constant: 18),
            filterBar.trailingAnchor.constraint(lessThanOrEqualTo: listPane.trailingAnchor, constant: -18),

            activeScroll.topAnchor.constraint(equalTo: filterBar.bottomAnchor, constant: 8),
            activeScroll.leadingAnchor.constraint(equalTo: listPane.leadingAnchor, constant: 18),
            activeScroll.trailingAnchor.constraint(equalTo: listPane.trailingAnchor, constant: -18),
            activeScroll.bottomAnchor.constraint(equalTo: listPane.bottomAnchor, constant: -18)
        ])
        reload()
    }

    private func configure(table: NSTableView, identifier: String) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = identifier == "proposed" ? 92 : 44
        table.dataSource = self
        table.delegate = self
        table.identifier = NSUserInterfaceItemIdentifier(identifier)
        table.style = .inset
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.intercellSpacing = NSSize(width: 0, height: identifier == "proposed" ? 8 : 4)
    }

    private func configure(scroll: NSScrollView, table: NSTableView) {
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.scrollerStyle = .overlay
    }

    private func styleScrollSurfaces() {
        Theme.card(proposedScroll, color: Theme.surface)
        Theme.card(activeScroll, color: Theme.surface)
        Theme.card(detailScroll, color: Theme.surface)
        [proposedScroll, activeScroll, detailScroll].forEach { $0.layer?.masksToBounds = true }
    }

    @objc private func scrollContentBoundsChanged() {
        resizeDetailDocument()
    }

    private func resizeDetailDocument() {
        guard detailScroll.documentView === detailView else { return }
        let width = max(Layout.minDetailWidth, detailScroll.contentSize.width)
        detailView.frame.size.width = width
        detailView.layoutSubtreeIfNeeded()
        detailView.frame.size.height = max(detailScroll.contentSize.height, detailView.fittingSize.height)
    }

    private func restoreSplitPositionIfNeeded() {
        guard !didRestoreSplitPosition, splitView.bounds.width > 0 else { return }
        let saved = UserDefaults.standard.double(forKey: Layout.dividerDefaultsKey)
        let dynamicDefault = min(Layout.maxDefaultDetailWidth, max(Layout.defaultDetailWidth, splitView.bounds.width * 0.34))
        let detailWidth = saved > 0 ? saved : dynamicDefault
        let dividerPosition = splitView.bounds.width - min(max(detailWidth, Layout.minDetailWidth), splitView.bounds.width - Layout.minListWidth)
        splitView.setPosition(max(Layout.minListWidth, dividerPosition), ofDividerAt: 0)
        didRestoreSplitPosition = true
    }

    private func updateProposedHeight() {
        guard let proposedHeightConstraint, listPane.bounds.height > 0 else { return }
        let rowDrivenHeight = viewModel.proposed.isEmpty
            ? Layout.minProposedHeight
            : CGFloat(min(viewModel.proposed.count, 8)) * 96 + 18
        let maxByViewport = max(
            Layout.minProposedHeight,
            min(listPane.bounds.height * 0.55, listPane.bounds.height - Layout.minActiveHeight)
        )
        proposedHeightConstraint.constant = max(
            Layout.minProposedHeight,
            min(maxByViewport, max(Layout.defaultProposedHeight, rowDrivenHeight))
        )
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
        updateProposedHeight()
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
        resizeDetailDocument()
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
        if tableView == proposedTable { return 92 }
        if case .header = viewModel.activeRows[row] { return 24 }
        if case .rejected = viewModel.activeRows[row] { return 34 }
        return 44
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        CockpitRowView()
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
        case let .rejected(item):
            return RejectedRowView(item: item)
        }

    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if tableView == activeTable, case .header = viewModel.activeRows[row] { return false }
        if tableView == activeTable, case .rejected = viewModel.activeRows[row] { return false }
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

    private final class CockpitRowView: NSTableRowView {
        override func drawSelection(in dirtyRect: NSRect) {
            guard selectionHighlightStyle != .none else { return }
            let inset = bounds.insetBy(dx: 8, dy: 2)
            let path = NSBezierPath(roundedRect: inset, xRadius: 14, yRadius: 14)
            Theme.surfaceSelected.setFill()
            path.fill()
            Theme.signal.withAlphaComponent(0.28).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

extension MacCaptureViewController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        Layout.minListWidth
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(Layout.minListWidth, splitView.bounds.width - Layout.minDetailWidth)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard didRestoreSplitPosition, detailScroll.frame.width >= Layout.minDetailWidth else { return }
        UserDefaults.standard.set(detailScroll.frame.width, forKey: Layout.dividerDefaultsKey)
        resizeDetailDocument()
    }
}
