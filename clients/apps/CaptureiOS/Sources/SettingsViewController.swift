import UIKit
import CaptureCore

final class SettingsViewController: UIViewController {
    private let viewModel: CaptureViewModel
    private let stack = UIStackView()
    private let appearanceControl = UISegmentedControl(items: CaptureAppearanceMode.allCases.map(\.label))

    init(viewModel: CaptureViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        applyTheme()
        build()
        loadPreferences()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
    }

    private func build() {
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let header = UILabel()
        header.text = "Tune the capture surface without slowing capture down."
        header.font = Theme.display(17, .semibold)
        header.textColor = Theme.textSecondary
        header.numberOfLines = 0

        appearanceControl.selectedSegmentTintColor = Theme.signal
        appearanceControl.addTarget(self, action: #selector(appearanceChanged), for: .valueChanged)

        let accountNote = UILabel()
        accountNote.text = "Password changes use the emailed reset flow from the sign-in screen."
        accountNote.font = Theme.display(13, .regular)
        accountNote.textColor = Theme.textTertiary
        accountNote.numberOfLines = 0

        let signOutButton = UIButton(type: .system)
        signOutButton.setTitle("Sign Out", for: .normal)
        signOutButton.setTitleColor(Theme.danger, for: .normal)
        signOutButton.backgroundColor = Theme.surfaceHi
        signOutButton.layer.cornerRadius = 12
        signOutButton.addAction(UIAction { [weak self] _ in self?.signOut() }, for: .touchUpInside)

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(section(title: "Appearance", controls: [appearanceControl]))
        stack.addArrangedSubview(section(title: "Account", controls: [accountNote, signOutButton]))

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    private func loadPreferences() {
        let appearance = CapturePreferences.load().appearance
        appearanceControl.selectedSegmentIndex = CaptureAppearanceMode.allCases.firstIndex(of: appearance) ?? 1
    }

    @objc private func appearanceChanged() {
        let index = appearanceControl.selectedSegmentIndex
        guard CaptureAppearanceMode.allCases.indices.contains(index) else { return }
        let mode = CaptureAppearanceMode.allCases[index]
        CapturePreferences(appearance: mode).save()
        view.window?.overrideUserInterfaceStyle = mode.userInterfaceStyle
        view.window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        NotificationCenter.default.post(name: .captureAppearanceChanged, object: nil)
        applyTheme()
    }

    private func applyTheme() {
        view.backgroundColor = Theme.ink
        view.window?.tintColor = Theme.signal
        stack.backgroundColor = Theme.ink
    }

    private func signOut() {
        Task {
            await viewModel.auth.signOut()
            await viewModel.store.clearActiveUser()
        }
    }

    private func section(title: String, controls: [UIView]) -> UIView {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 10
        card.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        card.isLayoutMarginsRelativeArrangement = true
        card.backgroundColor = Theme.surface
        card.layer.cornerRadius = 18

        let label = UILabel()
        label.text = title.uppercased()
        label.font = Theme.mono(12, .semibold)
        label.textColor = Theme.textTertiary
        card.addArrangedSubview(label)
        controls.forEach { card.addArrangedSubview($0) }
        return card
    }
}

private extension CaptureAppearanceMode {
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .dark: return .dark
        case .light: return .light
        }
    }
}
