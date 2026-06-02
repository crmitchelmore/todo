import AppKit
import CaptureCore

final class MacCaptureViewController: NSViewController {
    private let viewModel: MacViewModel
    private let captureField = NSTextField()
    private let proposedTable = NSTableView()
    private let activeTable = NSTableView()
    private let proposedHeader = NSTextField(labelWithString: "")

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

        let activeHeader = NSTextField(labelWithString: "ACTIVE")
        activeHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        activeHeader.textColor = .secondaryLabelColor
        activeHeader.translatesAutoresizingMaskIntoConstraints = false

        configure(table: proposedTable, identifier: "proposed")
        configure(table: activeTable, identifier: "active")
        let proposedScroll = scroll(proposedTable)
        let activeScroll = scroll(activeTable)

        [captureField, proposedHeader, proposedScroll, activeHeader, activeScroll].forEach {
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

            activeScroll.topAnchor.constraint(equalTo: activeHeader.bottomAnchor, constant: 4),
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
        table.rowHeight = identifier == "proposed" ? 56 : 32
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

    private func reload() {
        proposedHeader.stringValue = viewModel.proposed.isEmpty
            ? "NOTHING TO CONFIRM"
            : "NEEDS CONFIRMING · \(viewModel.proposed.count)"
        proposedTable.reloadData()
        activeTable.reloadData()
    }

    @objc private func captureSubmit() {
        let text = captureField.stringValue
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        captureField.stringValue = "" // instant clear
        viewModel.capture(text)
    }
}

extension MacCaptureViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView == proposedTable ? viewModel.proposed.count : viewModel.active.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == proposedTable {
            let item = viewModel.proposed[row]
            return ProposedRowView(item: item) { [weak self] in
                self?.viewModel.confirm(item)
            } onReject: { [weak self] in
                self?.viewModel.reject(item)
            }
        } else {
            let item = viewModel.active[row]
            return ActiveRowView(item: item) { [weak self] done in
                self?.viewModel.setDone(item, done)
            }
        }
    }
}
