import UIKit
import CaptureCore

final class CaptureViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private let viewModel = CaptureViewModel()
    private let captureField = UITextField()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Capture"
        view.backgroundColor = .systemBackground
        setupCaptureBar()
        setupTable()

        viewModel.onChange = { [weak self] in self?.tableView.reloadData() }
        viewModel.start()
    }

    private func setupCaptureBar() {
        captureField.placeholder = "Capture anything…"
        captureField.borderStyle = .roundedRect
        captureField.returnKeyType = .done
        captureField.autocorrectionType = .no
        captureField.clearButtonMode = .whileEditing
        captureField.delegate = self
        captureField.font = .systemFont(ofSize: 18)
        captureField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureField)
        NSLayoutConstraint.activate([
            captureField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            captureField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            captureField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            captureField.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupTable() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: captureField.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Capture (instant)

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = textField.text ?? ""
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        textField.text = "" // instant clear = perceived speed
        viewModel.capture(text) // background, not awaited
        return false // keep keyboard up for rapid capture
    }

    // MARK: - Table

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return viewModel.proposed.isEmpty ? nil : "Needs confirming · \(viewModel.proposed.count)"
        }
        return "Active · \(viewModel.active.count)"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? viewModel.proposed.count : viewModel.active.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let item = viewModel.proposed[indexPath.row]
            config.text = item.title
            config.secondaryText = proposalHint(item)
            config.secondaryTextProperties.color = .systemBlue
            cell.accessoryType = .disclosureIndicator
        } else {
            let item = viewModel.active[indexPath.row]
            config.text = item.title
            config.secondaryText = activeSubtitle(item)
            cell.accessoryType = item.status == .done ? .checkmark : .none
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            let item = viewModel.proposed[indexPath.row]
            let vc = ConfirmViewController(item: item) { [weak self] action in
                switch action {
                case let .confirm(title, due, category):
                    self?.viewModel.confirm(item, title: title, dueAt: due, category: category)
                case .reject:
                    self?.viewModel.reject(item)
                }
            }
            present(UINavigationController(rootViewController: vc), animated: true)
        } else {
            let item = viewModel.active[indexPath.row]
            viewModel.setDone(item, true)
        }
    }

    private func proposalHint(_ item: TaskItem) -> String {
        var parts: [String] = []
        if let due = item.suggestedDueAt { parts.append(DueFormatter.short(due)) }
        if let cat = item.suggestedCategory { parts.append(cat) }
        return parts.isEmpty ? "tap to confirm" : "suggested: " + parts.joined(separator: " · ")
    }

    private func activeSubtitle(_ item: TaskItem) -> String? {
        var parts: [String] = []
        if let due = item.dueAt { parts.append(DueFormatter.short(due)) }
        if let cat = item.category { parts.append(cat) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
