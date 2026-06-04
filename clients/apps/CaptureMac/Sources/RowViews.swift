import AppKit
import CaptureCore

/// Field editor for the capture box that intercepts paste: if the clipboard holds a markdown /
/// checkbox list, it ingests each line as its own item instead of pasting collapsed text.
final class CapturePasteTextView: NSTextView {
    var onPasteList: ((String) -> Bool)?
    var onPasteImages: (([NSImage]) -> Bool)?

    override func paste(_ sender: Any?) {
        if let s = NSPasteboard.general.string(forType: .string), onPasteList?(s) == true { return }
        if let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           !images.isEmpty,
           onPasteImages?(images) == true { return }
        super.paste(sender)
    }
}

final class AttachmentCaptureTextField: NSTextField {
    var onDroppedImages: (([NSImage]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.tiff, .png, .fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.tiff, .png, .fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        images(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let imgs = images(from: sender.draggingPasteboard)
        guard !imgs.isEmpty else { return false }
        onDroppedImages?(imgs)
        return true
    }

    private func images(from pasteboard: NSPasteboard) -> [NSImage] {
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage], !images.isEmpty {
            return images
        }
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return [] }
        return urls.compactMap { NSImage(contentsOf: $0) }
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
        title.font = Theme.display(14, .semibold)
        title.textColor = Theme.textPrimary
        title.lineBreakMode = .byTruncatingTail

        var hintParts: [String] = []
        if let due = item.suggestedDueAt { hintParts.append(DueFormatter.short(due)) }
        if let cat = item.suggestedCategory { hintParts.append(cat) }
        let hint = NSTextField(labelWithString: hintParts.isEmpty ? "no suggestion yet" : "suggested · " + hintParts.joined(separator: " · "))
        hint.font = Theme.mono(11)
        hint.textColor = hintParts.isEmpty ? Theme.textTertiary : Theme.signal

        let textStack = NSStackView(views: [title, hint])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        if let chips = tagChipRow(item.tags, color: color) { textStack.addArrangedSubview(chips) }

        let confirm = NSButton(title: "Confirm", target: self, action: #selector(confirmTapped))
        confirm.keyEquivalent = "\r"
        Theme.primary(confirm)
        let reject = NSButton(title: "✕", target: self, action: #selector(rejectTapped))
        reject.contentTintColor = Theme.textTertiary

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
        check.contentTintColor = Theme.mint

        let title = NSTextField(labelWithString: item.title)
        title.font = Theme.display(13, .regular)
        title.textColor = item.status == .done ? Theme.textTertiary : Theme.textPrimary
        title.lineBreakMode = .byTruncatingTail

        let cat = NSTextField(labelWithString: item.category ?? "")
        cat.font = Theme.mono(11)
        cat.textColor = Theme.textTertiary

        // Editable due: click to open presets + a date picker.
        let dueTitle = item.dueAt.map { DueFormatter.short($0) } ?? "+ date"
        let due = NSButton(title: dueTitle, target: self, action: #selector(editDue(_:)))
        due.bezelStyle = .inline
        due.controlSize = .small
        due.font = Theme.mono(11)
        due.contentTintColor = item.dueAt == nil ? Theme.textTertiary : Theme.signal

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
        title.font = Theme.mono(11, .semibold)
        title.textColor = label == "Overdue" ? Theme.danger : Theme.textTertiary
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
