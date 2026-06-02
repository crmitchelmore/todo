import AppKit
import CaptureCore

/// A proposed-item row: title + on-device suggestion, with quick Accept / Reject.
final class ProposedRowView: NSTableCellView {
    private let onConfirm: () -> Void
    private let onReject: () -> Void

    init(item: TaskItem, onConfirm: @escaping () -> Void, onReject: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onReject = onReject
        super.init(frame: .zero)
        build(item)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build(_ item: TaskItem) {
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

    init(item: TaskItem, onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        super.init(frame: .zero)
        build(item)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build(_ item: TaskItem) {
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

        let row = NSStackView(views: [check, title, NSView(), metaLabel])
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
