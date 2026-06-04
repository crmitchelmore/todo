import UIKit
import CaptureCore

struct IOSTaskDetailForm {
    let title: String
    let notes: String?
    let dueAt: Date?
    let category: String?
    let tags: [String]
    let priority: Int?
}

final class TaskDetailViewController: UIViewController, UITextFieldDelegate, UITextViewDelegate {
    private let viewModel: CaptureViewModel
    private let taskId: String
    private var currentTask: TaskItem
    private var events: [TaskEvent] = []
    private var rollup: TaskRollup = .empty
    private var watchTasks: [Task<Void, Never>] = []
    private var dirty = false

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let stateLabel = UILabel()
    private let titleField = UITextField()
    private let saveButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)
    private let rejectButton = UIButton(type: .system)
    private let dueSwitch = UISwitch()
    private let duePicker = UIDatePicker()
    private let categoryField = UITextField()
    private let priorityControl = UISegmentedControl(items: ["None", "P0", "P1", "P2", "P3", "P4"])
    private let tagsField = UITextField()
    private let notesView = UITextView()
    private let rollupStack = UIStackView()
    private let rollupSummaryLabel = UILabel()
    private let rollupProgress = UIProgressView(progressViewStyle: .bar)
    private let historyStack = UIStackView()

    init(viewModel: CaptureViewModel, item: TaskItem) {
        self.viewModel = viewModel
        self.taskId = item.id
        self.currentTask = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Task"
        view.backgroundColor = Theme.ink
        build()
        populate(currentTask)
        updateActions()
        startWatching()
    }

    deinit { watchTasks.forEach { $0.cancel() } }

    private func build() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        stateLabel.font = Theme.mono(12, .semibold)
        stateLabel.textColor = Theme.signal

        titleField.font = Theme.display(24, .semibold)
        titleField.textColor = Theme.textPrimary
        titleField.backgroundColor = Theme.surfaceHi
        titleField.layer.cornerRadius = 12
        titleField.layer.masksToBounds = true
        titleField.clearButtonMode = .whileEditing
        titleField.returnKeyType = .done
        titleField.delegate = self
        titleField.addTarget(self, action: #selector(markDirty), for: .editingChanged)

        Theme.primary(saveButton)
        saveButton.addAction(UIAction { [weak self] _ in self?.primaryTapped() }, for: .touchUpInside)
        secondaryButton.setTitleColor(Theme.textPrimary, for: .normal)
        secondaryButton.backgroundColor = Theme.surfaceHi
        secondaryButton.layer.cornerRadius = 12
        secondaryButton.addAction(UIAction { [weak self] _ in self?.secondaryTapped() }, for: .touchUpInside)
        rejectButton.setTitleColor(Theme.danger, for: .normal)
        rejectButton.backgroundColor = Theme.surfaceHi
        rejectButton.layer.cornerRadius = 12
        rejectButton.addAction(UIAction { [weak self] _ in self?.rejectTapped() }, for: .touchUpInside)

        dueSwitch.onTintColor = Theme.signal
        dueSwitch.addTarget(self, action: #selector(markDirty), for: .valueChanged)
        duePicker.datePickerMode = .dateAndTime
        duePicker.preferredDatePickerStyle = .compact
        duePicker.tintColor = Theme.signal
        duePicker.addTarget(self, action: #selector(markDirty), for: .valueChanged)

        categoryField.placeholder = "engineering, home, inbox…"
        categoryField.textColor = Theme.textPrimary
        categoryField.backgroundColor = Theme.surfaceHi
        categoryField.layer.cornerRadius = 10
        categoryField.layer.masksToBounds = true
        categoryField.delegate = self
        categoryField.addTarget(self, action: #selector(markDirty), for: .editingChanged)

        priorityControl.selectedSegmentTintColor = Theme.signal
        priorityControl.addTarget(self, action: #selector(markDirty), for: .valueChanged)

        tagsField.placeholder = "project, person, context"
        tagsField.textColor = Theme.textPrimary
        tagsField.backgroundColor = Theme.surfaceHi
        tagsField.layer.cornerRadius = 10
        tagsField.layer.masksToBounds = true
        tagsField.delegate = self
        tagsField.addTarget(self, action: #selector(markDirty), for: .editingChanged)

        notesView.font = Theme.display(15, .regular)
        notesView.textColor = Theme.textPrimary
        notesView.backgroundColor = Theme.surfaceHi
        notesView.layer.cornerRadius = 12
        notesView.delegate = self
        notesView.heightAnchor.constraint(equalToConstant: 160).isActive = true

        rollupStack.axis = .vertical
        rollupStack.spacing = 8
        rollupSummaryLabel.font = Theme.display(14, .semibold)
        rollupSummaryLabel.textColor = Theme.textPrimary
        rollupProgress.trackTintColor = Theme.surfaceHi
        rollupProgress.progressTintColor = Theme.signal
        rollupStack.addArrangedSubview(section("Subtasks"))
        rollupStack.addArrangedSubview(rollupSummaryLabel)
        rollupStack.addArrangedSubview(rollupProgress)
        rollupStack.isHidden = true

        historyStack.axis = .vertical
        historyStack.spacing = 12

        let actions = UIStackView(arrangedSubviews: [saveButton, secondaryButton, rejectButton])
        actions.axis = .horizontal
        actions.spacing = 10
        actions.distribution = .fillEqually

        stack.addArrangedSubview(stateLabel)
        stack.addArrangedSubview(titleField)
        stack.addArrangedSubview(actions)
        stack.addArrangedSubview(rollupStack)
        stack.addArrangedSubview(section("Properties"))
        stack.addArrangedSubview(row(label: "Due", controls: [dueSwitch, duePicker]))
        stack.addArrangedSubview(row(label: "Category", controls: [categoryField]))
        stack.addArrangedSubview(row(label: "Priority", controls: [priorityControl]))
        stack.addArrangedSubview(row(label: "Tags", controls: [tagsField]))
        stack.addArrangedSubview(section("Expansion"))
        stack.addArrangedSubview(notesView)
        stack.addArrangedSubview(section("AI + activity history"))
        stack.addArrangedSubview(historyStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])
    }

    private func startWatching() {
        let taskWatch = Task { [weak self] in
            guard let self else { return }
            do {
                for try await task in try self.viewModel.store.watchTask(id: self.taskId) {
                    await MainActor.run {
                        guard let task else {
                            self.navigationController?.popViewController(animated: true)
                            return
                        }
                        self.currentTask = task
                        if !self.dirty { self.populate(task) }
                        self.updateActions()
                    }
                }
            } catch {}
        }
        let rollupWatch = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rollup in try self.viewModel.store.watchTaskRollup(taskId: self.taskId) {
                    await MainActor.run {
                        self.rollup = rollup
                        self.updateRollup()
                    }
                }
            } catch {}
        }
        let eventsWatch = Task { [weak self] in
            guard let self else { return }
            do {
                for try await events in try self.viewModel.store.watchTaskAndDescendantEvents(taskId: self.taskId) {
                    await MainActor.run {
                        self.events = events
                        self.rebuildHistory()
                    }
                }
            } catch {}
        }
        watchTasks.append(contentsOf: [taskWatch, rollupWatch, eventsWatch])
    }

    private func populate(_ task: TaskItem) {
        titleField.text = task.title
        notesView.text = task.notes ?? ""
        dueSwitch.isOn = task.dueAt != nil
        duePicker.date = task.dueAt ?? task.suggestedDueAt ?? Date()
        duePicker.isEnabled = dueSwitch.isOn
        categoryField.text = task.category ?? task.suggestedCategory
        let priority = task.priority.flatMap { (0...4).contains($0) ? $0 : nil }
        priorityControl.selectedSegmentIndex = (priority ?? -1) + 1
        tagsField.text = task.tags.joined(separator: ", ")
    }

    private func updateActions() {
        stateLabel.text = currentTask.status.rawValue.uppercased()
        let proposed = currentTask.status == .proposed
        saveButton.setTitle(proposed ? "Confirm structure" : (dirty ? "Save changes" : "Saved"), for: .normal)
        saveButton.isEnabled = proposed || dirty
        secondaryButton.isHidden = proposed
        secondaryButton.setTitle(currentTask.status == .done ? "Reopen" : "Mark done", for: .normal)
        rejectButton.isHidden = !proposed
        duePicker.isEnabled = dueSwitch.isOn
    }

    private func updateRollup() {
        guard rollup.total > 0 else {
            rollupStack.isHidden = true
            return
        }
        rollupStack.isHidden = false
        let completion = Float(rollup.done) / Float(rollup.total)
        let percent = Int((completion * 100).rounded())
        rollupSummaryLabel.text = "\(rollup.done)/\(rollup.total) complete · \(rollup.open) open · \(percent)%"
        rollupProgress.progress = completion
    }

    private func rebuildHistory() {
        historyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !events.isEmpty else {
            let empty = UILabel()
            empty.text = "No synced history yet. Capture, confirmation, edits and AI updates appear here."
            empty.font = Theme.display(13, .regular)
            empty.textColor = Theme.textTertiary
            empty.numberOfLines = 0
            historyStack.addArrangedSubview(empty)
            return
        }
        for event in events {
            historyStack.addArrangedSubview(historyRow(event))
        }
    }

    private func historyRow(_ event: TaskEvent) -> UIView {
        let icon = UILabel()
        icon.text = eventIcon(event)
        icon.font = Theme.display(18, .semibold)
        icon.textColor = event.actor == "worker" || event.actor == "agent" ? Theme.signal : Theme.textTertiary
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true

        let title = UILabel()
        title.text = event.title
        title.font = Theme.display(14, .semibold)
        title.textColor = Theme.textPrimary
        let meta = UILabel()
        meta.text = "\(event.actor) · \(eventTime(event.createdAt))"
        meta.font = Theme.mono(11)
        meta.textColor = Theme.textTertiary
        let body = UILabel()
        body.text = event.body
        body.font = Theme.display(13, .regular)
        body.textColor = Theme.textSecondary
        body.numberOfLines = 0
        body.isHidden = (event.body ?? "").isEmpty

        let text = UIStackView(arrangedSubviews: [title, meta, body])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [icon, text])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 8
        return row
    }

    private func section(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = Theme.mono(12, .semibold)
        label.textColor = Theme.textTertiary
        return label
    }

    private func row(label text: String, controls: [UIView]) -> UIStackView {
        let label = UILabel()
        label.text = text
        label.font = Theme.mono(12, .semibold)
        label.textColor = Theme.textTertiary
        label.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let controlStack = UIStackView(arrangedSubviews: controls)
        controlStack.axis = .horizontal
        controlStack.spacing = 10
        controlStack.alignment = .center
        let row = UIStackView(arrangedSubviews: [label, controlStack])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        return row
    }

    private func form() -> IOSTaskDetailForm {
        let title = (titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = notesView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = (categoryField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = (tagsField.text ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let priority = priorityControl.selectedSegmentIndex > 0 ? priorityControl.selectedSegmentIndex - 1 : nil
        return IOSTaskDetailForm(
            title: title.isEmpty ? currentTask.title : title,
            notes: notes.isEmpty ? nil : notes,
            dueAt: dueSwitch.isOn ? duePicker.date : nil,
            category: category.isEmpty ? nil : category,
            tags: tags,
            priority: priority
        )
    }

    @objc private func markDirty() {
        dirty = true
        updateActions()
    }

    func textViewDidChange(_ textView: UITextView) { markDirty() }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    private func primaryTapped() {
        let form = form()
        if currentTask.status == .proposed {
            viewModel.confirmDetail(currentTask, form: form)
        } else {
            dirty = false
            viewModel.saveDetail(currentTask, form: form)
            updateActions()
        }
    }

    private func secondaryTapped() {
        viewModel.setDone(currentTask, currentTask.status != .done)
    }

    private func rejectTapped() {
        viewModel.reject(currentTask)
        navigationController?.popViewController(animated: true)
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
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "h:mm a" : "d MMM"
        return formatter.string(from: date)
    }
}
