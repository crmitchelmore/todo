import UIKit
import CaptureCore

final class NotificationHistoryViewController: UIViewController, UITableViewDataSource {
    private let viewModel: CaptureViewModel
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(viewModel: CaptureViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Notifications"
        view.backgroundColor = Theme.ink
        tableView.backgroundColor = Theme.ink
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "notification")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(viewModel.notifications.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "notification", for: indexPath)
        cell.backgroundColor = Theme.surfaceHi
        cell.textLabel?.numberOfLines = 0
        if viewModel.notifications.isEmpty {
            cell.textLabel?.text = "No notifications yet.\nResearch and attempt updates will stay here."
            cell.textLabel?.textColor = Theme.textSecondary
            return cell
        }
        let notification = viewModel.notifications[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = notification.title
        content.secondaryText = [
            notification.kind.replacingOccurrences(of: "_", with: " "),
            notification.body,
            notification.createdAt?.formatted(date: .abbreviated, time: .shortened)
        ].compactMap { $0 }.joined(separator: "\n")
        content.textProperties.color = Theme.textPrimary
        content.secondaryTextProperties.color = Theme.textSecondary
        content.secondaryTextProperties.numberOfLines = 4
        cell.contentConfiguration = content
        return cell
    }
}
