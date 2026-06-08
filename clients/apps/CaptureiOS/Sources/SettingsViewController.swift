import UIKit
import CaptureCore

final class SettingsViewController: UIViewController {
    private let viewModel: CaptureViewModel
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let appearanceControl = UISegmentedControl(items: CaptureAppearanceMode.allCases.map(\.label))
    private let diagnosticsStatus = UILabel()
    private let diagnosticsDetail = UILabel()
    private let diagnosticsMeta = UILabel()
    private let diagnosticsRefresh = UIButton(type: .system)

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
        loadDiagnostics()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
    }

    private func build() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

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

        diagnosticsStatus.font = Theme.display(15, .semibold)
        diagnosticsStatus.textColor = Theme.textPrimary
        diagnosticsStatus.numberOfLines = 0
        diagnosticsDetail.font = Theme.display(13, .regular)
        diagnosticsDetail.textColor = Theme.textSecondary
        diagnosticsDetail.numberOfLines = 0
        diagnosticsMeta.font = Theme.mono(11, .regular)
        diagnosticsMeta.textColor = Theme.textTertiary
        diagnosticsMeta.numberOfLines = 0
        diagnosticsRefresh.setTitle("Refresh diagnostics", for: .normal)
        diagnosticsRefresh.setTitleColor(Theme.signal, for: .normal)
        diagnosticsRefresh.backgroundColor = Theme.surfaceHi
        diagnosticsRefresh.layer.cornerRadius = 12
        diagnosticsRefresh.addAction(UIAction { [weak self] _ in self?.loadDiagnostics() }, for: .touchUpInside)

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(section(title: "Appearance", controls: [appearanceControl]))
        stack.addArrangedSubview(section(title: "Sync Diagnostics", controls: [diagnosticsStatus, diagnosticsDetail, diagnosticsMeta, diagnosticsRefresh]))
        stack.addArrangedSubview(section(title: "Account", controls: [accountNote, signOutButton]))

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -18),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
            diagnosticsRefresh.heightAnchor.constraint(equalToConstant: 44),
            signOutButton.heightAnchor.constraint(equalToConstant: 44)
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
        scrollView.backgroundColor = Theme.ink
        stack.backgroundColor = Theme.ink
    }

    private func loadDiagnostics() {
        diagnosticsStatus.text = "Checking sync state…"
        diagnosticsDetail.text = "Comparing this iPhone's local cache with the authenticated Railway account."
        diagnosticsMeta.text = ""
        diagnosticsRefresh.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                async let server = viewModel.auth.fetchSyncDiagnostics()
                async let local = viewModel.store.localSyncDiagnostics()
                let (serverDiagnostics, localDiagnostics) = try await (server, local)
                await updateDiagnostics(server: serverDiagnostics, local: localDiagnostics)
            } catch {
                await MainActor.run {
                    self.diagnosticsStatus.text = "Diagnostics unavailable"
                    self.diagnosticsDetail.text = (error as? CaptureError)?.message ?? error.localizedDescription
                    self.diagnosticsMeta.text = ""
                    self.diagnosticsRefresh.isEnabled = true
                }
            }
        }
    }

    @MainActor
    private func updateDiagnostics(server: ServerSyncDiagnostics, local: LocalSyncDiagnostics) {
        if local.ownerId != server.owner.id {
            diagnosticsStatus.text = "Account mismatch"
            diagnosticsDetail.text = "This device is stamping local rows with a different owner ID than the server session."
        } else if local.ownerIds.contains(where: { $0 != server.owner.id }) {
            diagnosticsStatus.text = "Local cache has another owner"
            diagnosticsDetail.text = "Sign out and back in to force a clean local reset before trusting the visible task list."
        } else if local.counts.total != server.serverCounts.total {
            diagnosticsStatus.text = "Counts differ"
            diagnosticsDetail.text = "PowerSync may still be catching up, or this build may be pointed at a different endpoint."
        } else {
            diagnosticsStatus.text = "Sync looks aligned"
            diagnosticsDetail.text = "This device, PowerSync and the backend are looking at the same account."
        }
        diagnosticsMeta.text = """
        Account: \(server.owner.email ?? server.owner.id)
        Server/local tasks: \(server.serverCounts.total)/\(local.counts.total)
        Session: \(server.currentSession?.client ?? "unknown")
        Backend: \(local.endpoints.backendURL)
        PowerSync: \(local.endpoints.powersyncURL)
        Local owners: \(local.ownerIds.joined(separator: ", ").nilIfEmpty ?? "none")
        """
        diagnosticsRefresh.isEnabled = true
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
