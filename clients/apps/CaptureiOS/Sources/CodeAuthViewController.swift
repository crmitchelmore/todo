import UIKit
import CaptureCore

/// Handles the two one-time-code auth flows on iOS — passwordless sign-in (`.login`) and
/// forgot-password reset (`.reset`) — as a single two-phase screen presented from the sign-in gate.
/// Phase 1 collects an email and asks the backend to send a code; phase 2 collects the code (and,
/// for `.reset`, a new password) and exchanges it for a session.
final class CodeAuthViewController: UIViewController {
    enum Purpose { case login, reset }
    private enum Phase { case requestEmail, enterCode }

    private let auth: AuthStore
    private let purpose: Purpose
    private let onSignedIn: () -> Void
    private var phase: Phase = .requestEmail
    private var email = ""
    private let keyboardSafeView = KeyboardAvoidingScrollView()

    private let titleLabel = UILabel()
    private let subtitle = UILabel()
    private let emailField = UITextField()
    private let codeField = UITextField()
    private let passwordField = UITextField()
    private let submit = UIButton(type: .system)
    private let resend = UIButton(type: .system)
    private let status = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var cooldownTask: Task<Void, Never>?
    private var cooldown = 0

    init(auth: AuthStore, purpose: Purpose, onSignedIn: @escaping () -> Void) {
        self.auth = auth
        self.purpose = purpose
        self.onSignedIn = onSignedIn
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.ink
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))

        titleLabel.font = Theme.display(30, .heavy)
        titleLabel.textColor = Theme.signal
        titleLabel.textAlignment = .center
        titleLabel.text = purpose == .login ? "Sign in with a code" : "Reset password"

        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = Theme.textSecondary
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        configure(emailField, placeholder: "Email")
        emailField.keyboardType = .emailAddress
        emailField.textContentType = .username
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no

        configure(codeField, placeholder: "6-digit code")
        codeField.keyboardType = .numberPad
        codeField.textContentType = .oneTimeCode
        codeField.isHidden = true

        configure(passwordField, placeholder: "New password")
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .newPassword
        passwordField.isHidden = true

        submit.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        Theme.primary(submit)
        submit.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        submit.translatesAutoresizingMaskIntoConstraints = false

        resend.titleLabel?.font = Theme.mono(13, .medium)
        resend.setTitleColor(Theme.textSecondary, for: .normal)
        resend.setTitleColor(Theme.textTertiary, for: .disabled)
        resend.addTarget(self, action: #selector(resendTapped), for: .touchUpInside)
        resend.isHidden = true

        status.font = Theme.mono(13)
        status.textColor = Theme.textSecondary
        status.textAlignment = .center
        status.numberOfLines = 0
        status.isHidden = true
        spinner.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitle, emailField, codeField, passwordField, submit, resend, spinner, status])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.layoutMargins = UIEdgeInsets(top: 24, left: 20, bottom: 24, right: 20)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.setCustomSpacing(28, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        Theme.card(stack, color: Theme.surface, radius: 24)
        keyboardSafeView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardSafeView)
        keyboardSafeView.contentView.addSubview(stack)
        let centreY = stack.centerYAnchor.constraint(equalTo: keyboardSafeView.scrollView.frameLayoutGuide.centerYAnchor)
        centreY.priority = .defaultLow
        NSLayoutConstraint.activate([
            keyboardSafeView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            keyboardSafeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardSafeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardSafeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: keyboardSafeView.contentView.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: keyboardSafeView.contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: keyboardSafeView.contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: keyboardSafeView.contentView.bottomAnchor, constant: -24),
            centreY,
            emailField.heightAnchor.constraint(equalToConstant: 48),
            codeField.heightAnchor.constraint(equalToConstant: 48),
            passwordField.heightAnchor.constraint(equalToConstant: 48),
            submit.heightAnchor.constraint(equalToConstant: 50)
        ])
        render()
    }

    private func configure(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.font = Theme.display(16, .regular)
        Theme.input(field)
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        field.rightViewMode = .always
    }

    private func render() {
        switch phase {
        case .requestEmail:
            subtitle.text = purpose == .login
                ? "We'll email you a 6-digit code to sign in — no password needed."
                : "Enter your email and we'll send a code to reset your password."
            emailField.isHidden = false
            codeField.isHidden = true
            passwordField.isHidden = true
            resend.isHidden = true
            submit.setTitle(purpose == .login ? "Send me a code" : "Send reset code", for: .normal)
            emailField.becomeFirstResponder()
        case .enterCode:
            subtitle.text = "Enter the code we sent to \(email)."
            emailField.isHidden = true
            codeField.isHidden = false
            passwordField.isHidden = purpose == .login
            resend.isHidden = false
            submit.setTitle(purpose == .login ? "Sign In" : "Reset & Sign In", for: .normal)
            codeField.becomeFirstResponder()
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    /// Re-issue the one-time code once the 60s cooldown elapses (a slow email shouldn't strand
    /// the user). The countdown matches the backend's per-ip+email issuance throttle window.
    private func startCooldown() {
        cooldown = 60
        updateResend()
        cooldownTask?.cancel()
        cooldownTask = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.cooldown = max(0, self.cooldown - 1)
                self.updateResend()
                if self.cooldown == 0 { return }
            }
        }
    }

    private func updateResend() {
        resend.setTitle(cooldown > 0 ? "Resend code in \(cooldown)s" : "Resend code", for: .normal)
        resend.isEnabled = cooldown == 0 && submit.isEnabled
    }

    @objc private func resendTapped() {
        guard cooldown == 0, !email.isEmpty else { return }
        setBusy(true)
        Task {
            do {
                if purpose == .login { try await auth.requestEmailCode(email: email) }
                else { try await auth.requestPasswordReset(email: email) }
                setBusy(false)
                startCooldown()
                show("A new code is on its way.", isError: false)
            } catch { fail(error) }
        }
    }

    @objc private func submitTapped() {
        view.endEditing(true)
        status.isHidden = true
        switch phase {
        case .requestEmail:
            let value = (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return show("Enter your email.") }
            email = value
            setBusy(true)
            Task {
                do {
                    if purpose == .login { try await auth.requestEmailCode(email: email) }
                    else { try await auth.requestPasswordReset(email: email) }
                    setBusy(false)
                    phase = .enterCode
                    render()
                    startCooldown()
                    show("Code sent. Check your inbox.", isError: false)
                } catch { fail(error) }
            }
        case .enterCode:
            let code = (codeField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { return show("Enter the code from your email.") }
            if purpose == .reset, (passwordField.text ?? "").count < 8 {
                return show("Password must be at least 8 characters.")
            }
            setBusy(true)
            let password = passwordField.text ?? ""
            Task {
                do {
                    if purpose == .login {
                        try await auth.verifyEmailCode(email: email, code: code, client: "ios")
                    } else {
                        try await auth.resetPassword(email: email, code: code, password: password, client: "ios")
                    }
                    setBusy(false)
                    dismiss(animated: true) { [onSignedIn] in onSignedIn() }
                } catch { fail(error) }
            }
        }
    }

    private func fail(_ error: Error) {
        let message = (error as? CaptureError)?.message ?? error.localizedDescription
        show(message)
    }

    private func setBusy(_ busy: Bool) {
        if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
        submit.isEnabled = !busy
        emailField.isEnabled = !busy
        codeField.isEnabled = !busy
        passwordField.isEnabled = !busy
        submit.alpha = busy ? 0.6 : 1
        updateResend()
    }

    private func show(_ message: String, isError: Bool = true) {
        setBusy(false)
        status.text = message
        status.textColor = isError ? Theme.danger : Theme.mint
        status.isHidden = false
    }
}
