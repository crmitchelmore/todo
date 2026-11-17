import UIKit
import CaptureCore

/// Asks for explicit permission before any task content is sent to the third-party AI provider
/// (Guideline 5.1.2(i)). Shown after sign-in and whenever consent is withdrawn in Settings.
final class AIConsentViewController: UIViewController {
    private let consent: AIDataConsent
    private let onAccept: () -> Void
    private let onSignOut: () -> Void
    private let status = UILabel()

    init(consent: AIDataConsent, onAccept: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.consent = consent
        self.onAccept = onAccept
        self.onSignOut = onSignOut
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.ink

        let eyebrow = UILabel()
        eyebrow.text = "AI DATA SHARING"
        eyebrow.font = Theme.mono(12, .semibold)
        eyebrow.textColor = Theme.iris
        eyebrow.adjustsFontForContentSizeCategory = true

        let title = UILabel()
        title.text = AIDataConsent.title
        title.font = Theme.display(28, .heavy)
        title.textColor = Theme.textPrimary
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityTraits.insert(.header)

        let body = UILabel()
        body.text = AIDataConsent.summary
        body.font = UIFont.preferredFont(forTextStyle: .body)
        body.textColor = Theme.textSecondary
        body.numberOfLines = 0
        body.adjustsFontForContentSizeCategory = true

        let card = UIStackView(arrangedSubviews: [eyebrow, title, body])
        card.axis = .vertical
        card.spacing = 12
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        Theme.panel(card)

        let accept = UIButton(type: .system)
        accept.setTitle("Allow AI processing", for: .normal)
        accept.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        accept.titleLabel?.adjustsFontForContentSizeCategory = true
        Theme.primary(accept)
        accept.accessibilityIdentifier = "aiConsentAccept"
        accept.addAction(UIAction { [weak self] _ in self?.acceptTapped() }, for: .touchUpInside)

        let decline = UIButton(type: .system)
        decline.setTitle("Don't allow", for: .normal)
        decline.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        decline.titleLabel?.adjustsFontForContentSizeCategory = true
        Theme.quiet(decline)
        decline.accessibilityIdentifier = "aiConsentDecline"
        decline.addAction(UIAction { [weak self] _ in self?.declineTapped() }, for: .touchUpInside)

        let policy = UIButton(type: .system)
        policy.setTitle("Read the privacy policy", for: .normal)
        policy.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
        policy.titleLabel?.adjustsFontForContentSizeCategory = true
        policy.setTitleColor(Theme.textSecondary, for: .normal)
        policy.addAction(UIAction { _ in UIApplication.shared.open(AIDataConsent.privacyPolicyURL) }, for: .touchUpInside)

        let signOut = UIButton(type: .system)
        signOut.setTitle("Sign out", for: .normal)
        signOut.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
        signOut.titleLabel?.adjustsFontForContentSizeCategory = true
        signOut.setTitleColor(Theme.danger, for: .normal)
        signOut.addAction(UIAction { [weak self] _ in self?.onSignOut() }, for: .touchUpInside)

        status.font = UIFont.preferredFont(forTextStyle: .footnote)
        status.textColor = Theme.textSecondary
        status.numberOfLines = 0
        status.adjustsFontForContentSizeCategory = true
        status.isHidden = true

        let stack = UIStackView(arrangedSubviews: [card, accept, decline, status, policy, signOut])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(20, after: card)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        scroll.addSubview(stack)

        let readable = view.readableContentGuide
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: readable.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: readable.trailingAnchor),
            accept.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            decline.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    private func acceptTapped() {
        consent.grant()
        Haptics.success()
        onAccept()
    }

    private func declineTapped() {
        consent.revoke()
        status.text = AIDataConsent.declineExplanation
        status.isHidden = false
    }
}
