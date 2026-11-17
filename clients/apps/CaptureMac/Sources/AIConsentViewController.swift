import AppKit
import CaptureCore

/// Asks for explicit permission before any task content is sent to the third-party AI provider.
/// Mirrors the iOS consent gate and is shown after sign-in or when consent is withdrawn.
@MainActor
final class AIConsentViewController: NSViewController {
    private let consent: AIDataConsent
    private let onAccept: () -> Void
    private let onSignOut: () -> Void
    private let status = NSTextField(wrappingLabelWithString: "")

    init(consent: AIDataConsent, onAccept: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.consent = consent
        self.onAccept = onAccept
        self.onSignOut = onSignOut
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 620))
        Theme.paintInk(container)

        let eyebrow = NSTextField(labelWithString: "AI DATA SHARING")
        eyebrow.font = Theme.mono(12, .semibold)
        eyebrow.textColor = Theme.iris

        let title = NSTextField(wrappingLabelWithString: AIDataConsent.title)
        title.font = Theme.display(28, .heavy)
        title.textColor = Theme.textPrimary

        let body = NSTextField(wrappingLabelWithString: AIDataConsent.summary)
        body.font = .systemFont(ofSize: 14)
        body.textColor = Theme.textSecondary

        let card = NSStackView(views: [eyebrow, title, body])
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 12
        card.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        card.wantsLayer = true
        Theme.panel(card)

        let accept = NSButton(title: "Allow AI processing", target: self, action: #selector(acceptTapped))
        Theme.primary(accept, fontSize: 14)
        accept.keyEquivalent = "\r"
        accept.setAccessibilityIdentifier("aiConsentAccept")

        let decline = NSButton(title: "Don't allow", target: self, action: #selector(declineTapped))
        Theme.quietButton(decline, fontSize: 13)
        decline.setAccessibilityIdentifier("aiConsentDecline")

        let policy = NSButton(title: "Read the privacy policy", target: self, action: #selector(policyTapped))
        Theme.quietButton(policy, fontSize: 12)

        let signOut = NSButton(title: "Sign out", target: self, action: #selector(signOutTapped))
        Theme.quietButton(signOut, fontSize: 12)
        signOut.contentTintColor = Theme.danger

        status.font = .systemFont(ofSize: 12)
        status.textColor = Theme.textSecondary
        status.isHidden = true

        let buttons = NSStackView(views: [accept, decline])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        let links = NSStackView(views: [policy, signOut])
        links.orientation = .horizontal
        links.spacing = 10

        let stack = NSStackView(views: [card, buttons, status, links])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.6),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
            stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),
            card.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            accept.heightAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])
        view = container
    }

    @objc private func acceptTapped() {
        consent.grant()
        onAccept()
    }

    @objc private func declineTapped() {
        consent.revoke()
        status.stringValue = AIDataConsent.declineExplanation
        status.isHidden = false
    }

    @objc private func policyTapped() {
        NSWorkspace.shared.open(AIDataConsent.privacyPolicyURL)
    }

    @objc private func signOutTapped() {
        onSignOut()
    }
}
