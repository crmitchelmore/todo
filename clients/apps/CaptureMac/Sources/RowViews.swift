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

/// An active-todo row: checkbox + title + due/category.
final class ActiveRowView: NSTableCellView {
    private let onToggle: (Bool) -> Void

    init(item: TaskItem, color: @escaping (String) -> String, onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
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

        var meta: [String] = []
        if let cat = item.category { meta.append(cat) }
        if let due = item.dueAt { meta.append(DueFormatter.short(due)) }
        let metaLabel = NSTextField(labelWithString: meta.joined(separator: " · "))
        metaLabel.font = .systemFont(ofSize: 11)
        metaLabel.textColor = .secondaryLabelColor

        var views: [NSView] = [check, title, NSView()]
        if let chips = tagChipRow(item.tags, color: color) { views.append(chips) }
        views.append(metaLabel)
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
}
