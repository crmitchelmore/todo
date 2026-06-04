import AppKit
import CaptureCore

struct MacTaskDetailForm {
    let title: String
    let notes: String?
    let dueAt: Date?
    let category: String?
    let tags: [String]
    let priority: Int?
}

@MainActor
final class MacTaskDetailView: NSView, NSTextFieldDelegate, NSTextViewDelegate, NSComboBoxDelegate {
    private let emptyView = NSStackView()
    private let formView = NSStackView()
    private let stateLabel = NSTextField(labelWithString: "")
    private let titleField = NSTextField()
    private let notesView = NSTextView()
    private let dueEnabled = NSButton(checkboxWithTitle: "Due", target: nil, action: nil)
    private let duePicker = NSDatePicker()
    private let categoryBox = NSComboBox()
    private let priorityPopup = NSPopUpButton()
    private let tagsField = NSTextField()
    private let primaryButton = NSButton(title: "Save changes", target: nil, action: nil)
    private let secondaryButton = NSButton(title: "Mark done", target: nil, action: nil)
    private let rejectButton = NSButton(title: "Reject", target: nil, action: nil)
    private let rollupStack = NSStackView()
    private let rollupSummary = NSTextField(labelWithString: "")
    private let rollupProgress = NSProgressIndicator()
    private let historyStack = NSStackView()

    private var currentTask: TaskItem?
    private var currentTaskId: String?
    private var isDirty = false
    private var colourForTag: (String) -> String = { TagPalette.color(for: $0) }
    private var onSave: ((MacTaskDetailForm) -> Void)?
    private var onConfirm: ((MacTaskDetailForm) -> Void)?
    private var onReject: (() -> Void)?
    private var onDone: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func render(
        task: TaskItem?,
        events: [TaskEvent],
        rollup: TaskRollup,
        colourForTag: @escaping (String) -> String,
        onSave: @escaping (MacTaskDetailForm) -> Void,
        onConfirm: @escaping (MacTaskDetailForm) -> Void,
        onReject: @escaping () -> Void,
        onDone: @escaping (Bool) -> Void
    ) {
        self.currentTask = task
        self.colourForTag = colourForTag
        self.onSave = onSave
        self.onConfirm = onConfirm
        self.onReject = onReject
        self.onDone = onDone

        guard let task else {
            currentTaskId = nil
            isDirty = false
            emptyView.isHidden = false
            formView.isHidden = true
            updateRollup(.empty)
            rebuildHistory([])
            return
        }

        let changedTask = currentTaskId != task.id
        currentTaskId = task.id
        emptyView.isHidden = true
        formView.isHidden = false
        if changedTask || !isDirty {
            populate(task)
            isDirty = false
        }
        updateActions(task)
        updateRollup(rollup)
        rebuildHistory(events)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "\r" {
            primaryTapped()
            return
        }
        super.keyDown(with: event)
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = Theme.surface.cgColor
        layer?.cornerRadius = 20

        emptyView.orientation = .vertical
        emptyView.alignment = .centerX
        emptyView.spacing = 10
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        let orb = NSTextField(labelWithString: "⌁")
        orb.font = Theme.display(42, .bold)
        orb.textColor = Theme.signal
        let emptyTitle = NSTextField(labelWithString: "Select a task")
        emptyTitle.font = Theme.display(22, .bold)
        emptyTitle.textColor = Theme.textPrimary
        let emptyBody = NSTextField(wrappingLabelWithString: "Open any item to inspect its structure, edit properties, and watch AI work land in the history.")
        emptyBody.font = Theme.display(13, .regular)
        emptyBody.textColor = Theme.textSecondary
        emptyBody.alignment = .center
        emptyBody.maximumNumberOfLines = 4
        emptyView.addArrangedSubview(orb)
        emptyView.addArrangedSubview(emptyTitle)
        emptyView.addArrangedSubview(emptyBody)
        addSubview(emptyView)

        formView.orientation = .vertical
        formView.spacing = 14
        formView.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        formView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(formView)

        stateLabel.font = Theme.mono(11, .semibold)
        stateLabel.textColor = Theme.signal

        titleField.font = Theme.display(21, .semibold)
        titleField.textColor = Theme.textPrimary
        titleField.backgroundColor = Theme.surfaceHi
        titleField.delegate = self

        dueEnabled.target = self
        dueEnabled.action = #selector(markDirty)
        dueEnabled.contentTintColor = Theme.signal
        duePicker.datePickerStyle = .textFieldAndStepper
        duePicker.datePickerElements = [.yearMonthDay, .hourMinute]
        duePicker.target = self
        duePicker.action = #selector(markDirty)

        categoryBox.addItem(withObjectValue: "")
        categoryBox.addItems(withObjectValues: CAPTURE_CATEGORIES)
        categoryBox.completes = true
        categoryBox.delegate = self

        priorityPopup.addItems(withTitles: ["None", "P0 · immediate", "P1 · important", "P2 · normal", "P3 · someday", "P4 · reference"])
        priorityPopup.target = self
        priorityPopup.action = #selector(markDirty)

        tagsField.placeholderString = "engineering, home, project-name"
        tagsField.delegate = self

        notesView.font = Theme.display(13, .regular)
        notesView.textColor = Theme.textPrimary
        notesView.backgroundColor = Theme.surfaceHi
        notesView.insertionPointColor = Theme.signal
        notesView.delegate = self
        notesView.isVerticallyResizable = true
        let notesScroll = NSScrollView()
        notesScroll.documentView = notesView
        notesScroll.hasVerticalScroller = true
        notesScroll.drawsBackground = false
        notesScroll.heightAnchor.constraint(equalToConstant: 130).isActive = true

        primaryButton.target = self
        primaryButton.action = #selector(primaryTapped)
        Theme.primary(primaryButton)
        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryTapped)
        secondaryButton.bezelStyle = .rounded
        rejectButton.target = self
        rejectButton.action = #selector(rejectTapped)
        rejectButton.bezelStyle = .rounded
        rejectButton.contentTintColor = Theme.danger

        rollupStack.orientation = .vertical
        rollupStack.spacing = 8
        rollupStack.alignment = .leading
        rollupSummary.font = Theme.display(13, .semibold)
        rollupSummary.textColor = Theme.textPrimary
        rollupProgress.isIndeterminate = false
        rollupProgress.style = .bar
        rollupProgress.minValue = 0
        rollupProgress.maxValue = 1
        rollupProgress.controlSize = .small
        rollupStack.addArrangedSubview(sectionTitle("Subtasks"))
        rollupStack.addArrangedSubview(rollupSummary)
        rollupStack.addArrangedSubview(rollupProgress)
        rollupProgress.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        historyStack.orientation = .vertical
        historyStack.spacing = 10
        historyStack.alignment = .leading

        let actionRow = NSStackView(views: [primaryButton, secondaryButton, rejectButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 8
        actionRow.distribution = .fillProportionally

        formView.addArrangedSubview(stateLabel)
        formView.addArrangedSubview(titleField)
        formView.addArrangedSubview(actionRow)
        formView.addArrangedSubview(rollupStack)
        formView.addArrangedSubview(sectionTitle("Properties"))
        formView.addArrangedSubview(row(label: "Due", views: [dueEnabled, duePicker]))
        formView.addArrangedSubview(row(label: "Category", views: [categoryBox]))
        formView.addArrangedSubview(row(label: "Priority", views: [priorityPopup]))
        formView.addArrangedSubview(row(label: "Tags", views: [tagsField]))
        formView.addArrangedSubview(sectionTitle("Expansion"))
        formView.addArrangedSubview(notesScroll)
        formView.addArrangedSubview(sectionTitle("AI + activity history"))
        formView.addArrangedSubview(historyStack)

        NSLayoutConstraint.activate([
            emptyView.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),
            formView.leadingAnchor.constraint(equalTo: leadingAnchor),
            formView.trailingAnchor.constraint(equalTo: trailingAnchor),
            formView.topAnchor.constraint(equalTo: topAnchor),
            formView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            categoryBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            tagsField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
    }

    private func populate(_ task: TaskItem) {
        titleField.stringValue = task.title
        notesView.string = task.notes ?? ""
        dueEnabled.state = task.dueAt == nil ? .off : .on
        duePicker.dateValue = task.dueAt ?? task.suggestedDueAt ?? Date()
        duePicker.isEnabled = dueEnabled.state == .on
        categoryBox.stringValue = task.category ?? task.suggestedCategory ?? ""
        let priority = task.priority.flatMap { (0...4).contains($0) ? $0 : nil }
        priorityPopup.selectItem(at: (priority ?? -1) + 1)
        tagsField.stringValue = task.tags.joined(separator: ", ")
    }

    private func updateActions(_ task: TaskItem) {
        stateLabel.stringValue = task.status.rawValue.uppercased()
        let proposed = task.status == .proposed
        primaryButton.title = proposed ? "Confirm structure" : (isDirty ? "Save changes" : "Saved")
        Theme.primary(primaryButton)
        primaryButton.isEnabled = proposed || isDirty
        secondaryButton.isHidden = proposed
        secondaryButton.title = task.status == .done ? "Reopen" : "Mark done"
        rejectButton.isHidden = !proposed
        duePicker.isEnabled = dueEnabled.state == .on
    }

    private func updateRollup(_ rollup: TaskRollup) {
        guard rollup.total > 0 else {
            rollupStack.isHidden = true
            return
        }
        rollupStack.isHidden = false
        let completion = Double(rollup.done) / Double(rollup.total)
        let percent = Int((completion * 100).rounded())
        rollupSummary.stringValue = "\(rollup.done)/\(rollup.total) complete · \(rollup.open) open · \(percent)%"
        rollupProgress.doubleValue = completion
    }

    private func rebuildHistory(_ events: [TaskEvent]) {
        historyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !events.isEmpty else {
            let empty = NSTextField(wrappingLabelWithString: "No synced history yet. Capture, confirmation, edits and AI updates appear here.")
            empty.font = Theme.display(12, .regular)
            empty.textColor = Theme.textTertiary
            historyStack.addArrangedSubview(empty)
            return
        }
        for event in events {
            historyStack.addArrangedSubview(historyRow(event))
        }
    }

    private func historyRow(_ event: TaskEvent) -> NSView {
        let icon = NSTextField(labelWithString: eventIcon(event))
        icon.font = Theme.display(16, .semibold)
        icon.textColor = event.actor == "worker" || event.actor == "agent" ? Theme.signal : Theme.textTertiary

        let title = NSTextField(labelWithString: event.title)
        title.font = Theme.display(13, .semibold)
        title.textColor = Theme.textPrimary
        let meta = NSTextField(labelWithString: "\(event.actor) · \(eventTime(event.createdAt))")
        meta.font = Theme.mono(10)
        meta.textColor = Theme.textTertiary
        let head = NSStackView(views: [title, meta])
        head.orientation = .horizontal
        head.spacing = 8

        let body = NSTextField(wrappingLabelWithString: event.body ?? "")
        body.font = Theme.display(12, .regular)
        body.textColor = Theme.textSecondary
        body.isHidden = (event.body ?? "").isEmpty

        let text = NSStackView(views: [head, body])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        return row
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = Theme.mono(11, .semibold)
        label.textColor = Theme.textTertiary
        return label
    }

    private func row(label text: String, views: [NSView]) -> NSStackView {
        let label = NSTextField(labelWithString: text)
        label.font = Theme.mono(11, .semibold)
        label.textColor = Theme.textTertiary
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let controls = NSStackView(views: views)
        controls.orientation = .horizontal
        controls.spacing = 8
        let row = NSStackView(views: [label, controls])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10
        return row
    }

    private func form() -> MacTaskDetailForm {
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = notesView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = categoryBox.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = tagsField.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let priorityIndex = priorityPopup.indexOfSelectedItem
        return MacTaskDetailForm(
            title: title.isEmpty ? (currentTask?.title ?? "") : title,
            notes: notes.isEmpty ? nil : notes,
            dueAt: dueEnabled.state == .on ? duePicker.dateValue : nil,
            category: category.isEmpty ? nil : category,
            tags: tags,
            priority: priorityIndex > 0 ? priorityIndex - 1 : nil
        )
    }

    @objc private func markDirty() {
        isDirty = true
        duePicker.isEnabled = dueEnabled.state == .on
        if let task = currentTask { updateActions(task) }
    }

    func controlTextDidChange(_ obj: Notification) { markDirty() }
    func textDidChange(_ notification: Notification) { markDirty() }
    func comboBoxSelectionDidChange(_ notification: Notification) { markDirty() }

    @objc private func primaryTapped() {
        guard let task = currentTask else { return }
        if task.status == .proposed {
            onConfirm?(form())
        } else {
            isDirty = false
            onSave?(form())
            updateActions(task)
        }
    }

    @objc private func secondaryTapped() {
        guard let task = currentTask else { return }
        onDone?(task.status != .done)
    }

    @objc private func rejectTapped() {
        onReject?()
    }

    private func eventIcon(_ event: TaskEvent) -> String {
        if event.actor == "worker" || event.actor == "agent" { return "◇" }
        if event.eventType == "completed" { return "✓" }
        if event.eventType == "captured" { return "⌁" }
        if event.eventType == "confirmed" { return "→" }
        return "•"
    }

    private func eventTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "d MMM"
        }
        return formatter.string(from: date)
    }
}
