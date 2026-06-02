import UIKit
import CaptureCore

enum ConfirmAction {
    case confirm(title: String, due: Date?, category: String?)
    case reject
}

/// The mandatory quick human confirm: pre-filled with on-device suggestions,
/// editable, one tap to accept. Nothing becomes a real todo without this.
final class ConfirmViewController: UIViewController {
    private let item: TaskItem
    private let completion: (ConfirmAction) -> Void

    private let titleField = UITextField()
    private let datePicker = UIDatePicker()
    private let dueSwitch = UISwitch()
    private let categoryControl: UISegmentedControl

    init(item: TaskItem, completion: @escaping (ConfirmAction) -> Void) {
        self.item = item
        self.completion = completion
        self.categoryControl = UISegmentedControl(items: CAPTURE_CATEGORIES)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Confirm"
        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Reject", style: .plain, target: self, action: #selector(reject))
        navigationItem.leftBarButtonItem?.tintColor = .systemRed
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Confirm", style: .done, target: self, action: #selector(confirm))

        titleField.text = item.title
        titleField.borderStyle = .roundedRect
        titleField.font = .systemFont(ofSize: 18, weight: .semibold)

        datePicker.datePickerMode = .dateAndTime
        datePicker.preferredDatePickerStyle = .compact
        if let due = item.suggestedDueAt ?? item.dueAt {
            datePicker.date = due
            dueSwitch.isOn = true
        } else {
            dueSwitch.isOn = false
        }

        if let cat = item.suggestedCategory ?? item.category,
           let idx = CAPTURE_CATEGORIES.firstIndex(of: cat) {
            categoryControl.selectedSegmentIndex = idx
        }

        let dueRow = UIStackView(arrangedSubviews: [label("Due"), dueSwitch, datePicker])
        dueRow.spacing = 12
        dueRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [
            titleField,
            dueRow,
            label("Category"),
            categoryControl
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    private func label(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.textColor = .secondaryLabel
        return l
    }

    @objc private func confirm() {
        let title = titleField.text?.trimmingCharacters(in: .whitespaces) ?? item.title
        let due: Date? = dueSwitch.isOn ? datePicker.date : nil
        let category = categoryControl.selectedSegmentIndex >= 0
            ? CAPTURE_CATEGORIES[categoryControl.selectedSegmentIndex] : nil
        dismiss(animated: true) { [completion] in
            completion(.confirm(title: title, due: due, category: category))
        }
    }

    @objc private func reject() {
        dismiss(animated: true) { [completion] in completion(.reject) }
    }
}
