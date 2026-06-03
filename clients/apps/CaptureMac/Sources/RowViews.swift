import AppKit
import CaptureCore

/// Field editor for the capture box that intercepts paste: if the clipboard holds a markdown /
/// checkbox list, it ingests each line as its own item instead of pasting collapsed text.
final class CapturePasteTextView: NSTextView {
    var onPasteList: ((String) -> Bool)?

    override func paste(_ sender: Any?) {
        if let s = NSPasteboard.general.string(forType: .string), onPasteList?(s) == true { return }
        super.paste(sender)
    }
}

/// A small coloured tag chip.
final class TagChipView: NSView {
    init(text: String, hex: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: hex)?.cgColor ?? NSColor.systemGray.cgColor
        layer?.cornerRadius = 6
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

func tagChipRow(_ tags: [String], color: (String) -> String) -> NSStackView? {
    guard !tags.isEmpty else { return nil }
    let chips = tags.map { TagChipView(text: $0, hex: color($0)) }
    let stack = NSStackView(views: chips)
    stack.orientation = .horizontal
    stack.spacing = 4
    return stack
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// A proposed-item row: title + on-device suggestion, with quick Accept / Reject.
final class ProposedRowView: NSTableCellView {
    private let onConfirm: () -> Void
    private let onReject: () -> Void

    init(item: TaskItem, color: @escaping (String) -> String, onConfirm: @escaping () -> Void, onReject: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onReject = onReject
        super.init(frame: .zero)
        build(item, color: color)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build(_ item: TaskItem, color: @escaping (String) -> String) {
        let title = NSTextField(labelWithString: item.title)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail

        var hintParts: [String] = []
        if let due = item.suggestedDueAt { hintParts.append(DueFormatter.short(due)) }
        if let cat = item.suggestedCategory { hintParts.append(cat) }
        let hint = NSTextField(labelWithString: hintParts.isEmpty ? "no suggestion yet" : "suggested: " + hintParts.joined(separator: " · "))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .systemBlue

        let textStack = NSStackView(views: [title, hint])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        if let chips = tagChipRow(item.tags, color: color) { textStack.addArrangedSubview(chips) }

        let confirm = NSButton(title: "Confirm", target: self, action: #selector(confirmTapped))
        confirm.keyEquivalent = "\r"
        confirm.bezelColor = .controlAccentColor
        let reject = NSButton(title: "✕", target: self, action: #selector(rejectTapped))

        let row = NSStackView(views: [textStack, NSView(), reject, confirm])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @objc private func confirmTapped() { onConfirm() }
    @objc private func rejectTapped() { onReject() }
}

/// An active-todo row: checkbox + title + category + an editable due-date button.
final class ActiveRowView: NSTableCellView {
    private let onToggle: (Bool) -> Void
    private let onSetDue: (Date?) -> Void
    private let item: TaskItem

    init(item: TaskItem, color: @escaping (String) -> String,
         onToggle: @escaping (Bool) -> Void, onSetDue: @escaping (Date?) -> Void) {
        self.onToggle = onToggle
        self.onSetDue = onSetDue
        self.item = item
        super.init(frame: .zero)
        build(item, color: color)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build(_ item: TaskItem, color: @escaping (String) -> String) {
        let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggled(_:)))
        check.state = item.status == .done ? .on : .off

        let title = NSTextField(labelWithString: item.title)
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail

        let cat = NSTextField(labelWithString: item.category ?? "")
        cat.font = .systemFont(ofSize: 11)
        cat.textColor = .secondaryLabelColor

        // Editable due: click to open presets + a date picker.
        let dueTitle = item.dueAt.map { DueFormatter.short($0) } ?? "+ date"
        let due = NSButton(title: dueTitle, target: self, action: #selector(editDue(_:)))
        due.bezelStyle = .inline
        due.controlSize = .small
        due.font = .systemFont(ofSize: 11)
        if item.dueAt == nil { due.contentTintColor = .tertiaryLabelColor }

        var views: [NSView] = [check, title, NSView()]
        if !(item.category ?? "").isEmpty { views.append(cat) }
        if let chips = tagChipRow(item.tags, color: color) { views.append(chips) }
        views.append(due)
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @objc private func toggled(_ sender: NSButton) { onToggle(sender.state == .on) }

    @objc private func editDue(_ sender: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = DuePopoverController(current: item.dueAt) { [weak popover] date in
            self.onSetDue(date)
            popover?.performClose(nil)
        }
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }
}

/// A section header row marking a date bucket (Overdue / Today / …) in the active list.
final class DateBucketHeaderView: NSTableCellView {
    init(label: String, count: Int) {
        super.init(frame: .zero)
        let title = NSTextField(labelWithString: "\(label.uppercased())  ·  \(count)")
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = label == "Overdue" ? .systemRed : .secondaryLabelColor
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            title.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Popover content for editing a due date: quick presets + a precise date picker + Clear.
final class DuePopoverController: NSViewController {
    private let current: Date?
    private let onPick: (Date?) -> Void
    private let picker = NSDatePicker()

    init(current: Date?, onPick: @escaping (Date?) -> Void) {
        self.current = current
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 150)) }

    override func viewDidLoad() {
        super.viewDidLoad()
        let presetButtons = DatePreset.settable.map { preset -> NSButton in
            let b = NSButton(title: preset.label, target: self, action: #selector(presetTapped(_:)))
            b.tag = DatePreset.settable.firstIndex(of: preset) ?? 0
            b.bezelStyle = .rounded
            b.controlSize = .small
            return b
        }
        let presetRow1 = NSStackView(views: Array(presetButtons.prefix(2)))
        let presetRow2 = NSStackView(views: Array(presetButtons.suffix(from: min(2, presetButtons.count))))
        [presetRow1, presetRow2].forEach { $0.orientation = .horizontal; $0.spacing = 6; $0.distribution = .fillEqually }

        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.dateValue = current ?? Date()
        picker.target = self
        picker.action = #selector(pickerChanged)

        let clear = NSButton(title: "Clear date", target: self, action: #selector(clearTapped))
        clear.bezelStyle = .inline
        clear.controlSize = .small

        let stack = NSStackView(views: [presetRow1, presetRow2, picker, clear])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func presetTapped(_ sender: NSButton) {
        onPick(DatePreset.settable[sender.tag].date())
    }
    @objc private func pickerChanged() { onPick(picker.dateValue) }
    @objc private func clearTapped() { onPick(nil) }
}
