import AppKit
import CaptureCore

/// Handles the two one-time-code auth flows on macOS — passwordless sign-in (`.login`) and
/// forgot-password reset (`.reset`) — presented as a sheet from the sign-in gate. Phase 1 collects
/// an email and requests a code; phase 2 collects the code (and a new password for `.reset`) and
/// exchanges it for a session.
@MainActor
final class CodeAuthViewController: NSViewController {
    enum Purpose { case login, reset }
    private enum Phase { case requestEmail, enterCode }

    private let auth: AuthStore
    private let purpose: Purpose
    private let onSignedIn: () -> Void
    private var phase: Phase = .requestEmail
    private var email = ""

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let emailField = NSTextField()
    private let codeField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let submit = NSButton(title: "", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    init(auth: AuthStore, purpose: Purpose, onSignedIn: @escaping () -> Void) {
        self.auth = auth
        self.purpose = purpose
        self.onSignedIn = onSignedIn
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 380))
        Theme.paintInk(container)

        titleLabel.font = Theme.display(26, .heavy)
        titleLabel.textColor = Theme.signal
        titleLabel.alignment = .center
        titleLabel.stringValue = purpose == .login ? "Sign in with a code" : "Reset password"

        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = Theme.textSecondary
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 3
        subtitle.preferredMaxLayoutWidth = 320

        for f in [emailField, codeField, passwordField] {
            f.controlSize = .large
            f.font = .systemFont(ofSize: 15)
        }
        emailField.placeholderString = "Email"
        emailField.target = self
        emailField.action = #selector(submitTapped)
        codeField.placeholderString = "6-digit code"
        codeField.target = self
        codeField.action = #selector(submitTapped)
        passwordField.placeholderString = "New password"
        passwordField.target = self
        passwordField.action = #selector(submitTapped)

        submit.bezelStyle = .rounded
        submit.controlSize = .large
        submit.keyEquivalent = "\r"
        submit.target = self
        submit.action = #selector(submitTapped)

        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.keyEquivalent = "\u{1b}" // Esc
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        status.font = Theme.mono(12)
        status.textColor = Theme.danger
        status.alignment = .center
        status.maximumNumberOfLines = 3
        status.preferredMaxLayoutWidth = 320
        status.isHidden = true

        let buttons = NSStackView(views: [cancelButton, submit])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        let stack = NSStackView(views: [titleLabel, subtitle, emailField, codeField, passwordField, buttons, spinner, status])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            emailField.widthAnchor.constraint(equalToConstant: 300),
            codeField.widthAnchor.constraint(equalToConstant: 300),
            passwordField.widthAnchor.constraint(equalToConstant: 300)
        ])
        self.view = container
        render()
    }

    private func render() {
        Theme.primary(submit, fontSize: 15)
        switch phase {
        case .requestEmail:
            subtitle.stringValue = purpose == .login
                ? "We'll email you a 6-digit code to sign in — no password needed."
                : "Enter your email and we'll send a code to reset your password."
            emailField.isHidden = false
            codeField.isHidden = true
            passwordField.isHidden = true
            submit.title = purpose == .login ? "Send me a code" : "Send reset code"
            view.window?.makeFirstResponder(emailField)
        case .enterCode:
            subtitle.stringValue = "Enter the code we sent to \(email)."
            emailField.isHidden = true
            codeField.isHidden = false
            passwordField.isHidden = purpose == .login
            submit.title = purpose == .login ? "Sign In" : "Reset & Sign In"
            view.window?.makeFirstResponder(codeField)
        }
    }

    @objc private func cancelTapped() {
        CaptureDiagnostics.record(category: "ui", name: "auth.code.cancel", message: "Code auth sheet cancelled", fields: ["purpose": purposeName])
        presentingViewController?.dismiss(self)
    }

    @objc private func submitTapped() {
        status.isHidden = true
        switch phase {
        case .requestEmail:
            let value = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return show("Enter your email.") }
            email = value
            CaptureDiagnostics.record(category: "ui", name: "auth.code.request.clicked", message: "Code request clicked", fields: ["purpose": purposeName])
            setBusy(true)
            Task {
                let context = CaptureDiagnostics.actionStarted("Request auth code", fields: ["purpose": purposeName])
                let startedAt = Date()
                do {
                    if purpose == .login { try await auth.requestEmailCode(email: email) }
                    else { try await auth.requestPasswordReset(email: email) }
                    CaptureDiagnostics.actionCompleted(context, startedAt: startedAt)
                    setBusy(false)
                    phase = .enterCode
                    render()
                    show("Code sent. Check your inbox.", isError: false)
                } catch {
                    CaptureDiagnostics.actionFailed(context, startedAt: startedAt, error: error)
                    fail(error)
                }
            }
        case .enterCode:
            let code = codeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { return show("Enter the code from your email.") }
            if purpose == .reset, passwordField.stringValue.count < 8 {
                return show("Password must be at least 8 characters.")
            }
            let password = passwordField.stringValue
            CaptureDiagnostics.record(category: "ui", name: "auth.code.verify.clicked", message: "Code verify clicked", fields: ["purpose": purposeName])
            setBusy(true)
            Task {
                let context = CaptureDiagnostics.actionStarted("Verify auth code", fields: ["purpose": purposeName, "client": "mac"])
                let startedAt = Date()
                do {
                    if purpose == .login {
                        try await auth.verifyEmailCode(email: email, code: code, client: "mac")
                    } else {
                        try await auth.resetPassword(email: email, code: code, password: password, client: "mac")
                    }
                    CaptureDiagnostics.actionCompleted(context, startedAt: startedAt)
                    setBusy(false)
                    presentingViewController?.dismiss(self)
                    onSignedIn()
                } catch {
                    CaptureDiagnostics.actionFailed(context, startedAt: startedAt, error: error)
                    fail(error)
                }
            }
        }
    }

    private func fail(_ error: Error) {
        let message = (error as? CaptureError)?.message ?? error.localizedDescription
        CaptureDiagnostics.record(severity: .error, category: "auth", name: "auth.code.failed", message: message, fields: ["purpose": purposeName])
        show(message)
    }

    private func setBusy(_ busy: Bool) {
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        submit.isEnabled = !busy
        emailField.isEnabled = !busy
        codeField.isEnabled = !busy
        passwordField.isEnabled = !busy
    }

    private func show(_ message: String, isError: Bool = true) {
        setBusy(false)
        status.stringValue = message
        status.textColor = isError ? Theme.danger : Theme.mint
        status.isHidden = false
    }

    private var purposeName: String {
        purpose == .login ? "login" : "reset"
    }
}
