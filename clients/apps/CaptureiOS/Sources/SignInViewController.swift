import UIKit
import CaptureCore

/// Email + password gate for iOS, shown before the capture UI. Mirrors the macOS gate: a segmented
/// control toggles between signing in and creating an account, then the credentials are handed to
/// `AuthStore`, which exchanges them for an opaque session token. The AppDelegate swaps in the
/// capture UI on success.
final class SignInViewController: UIViewController {
    private enum Mode: Int { case signIn, register }

    private let auth: AuthStore
    private let onSignedIn: () -> Void
    private var mode: Mode = .signIn

    private let segmented = UISegmentedControl(items: ["Sign In", "Create Account"])
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let submit = UIButton(type: .system)
    private let status = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(auth: AuthStore, onSignedIn: @escaping () -> Void) {
        self.auth = auth
        self.onSignedIn = onSignedIn
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.ink

        let title = UILabel()
        title.text = "Capture"
        title.font = Theme.display(40, .heavy)
        title.textColor = Theme.signal
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "An instrument for thought. Sign in to sync across your devices."
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = Theme.textSecondary
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        segmented.selectedSegmentIndex = 0
        segmented.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        configure(emailField, placeholder: "Email")
        emailField.keyboardType = .emailAddress
        emailField.textContentType = .username
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.returnKeyType = .next
        emailField.delegate = self

        configure(passwordField, placeholder: "Password")
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.returnKeyType = .go
        passwordField.delegate = self

        submit.setTitle("Sign In", for: .normal)
        submit.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        Theme.primary(submit)
        submit.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        submit.translatesAutoresizingMaskIntoConstraints = false

        status.font = Theme.mono(13)
        status.textColor = Theme.danger
        status.textAlignment = .center
        status.numberOfLines = 0
        status.isHidden = true

        spinner.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [title, subtitle, segmented, emailField, passwordField, submit, spinner, status])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.setCustomSpacing(28, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            emailField.heightAnchor.constraint(equalToConstant: 48),
            passwordField.heightAnchor.constraint(equalToConstant: 48),
            submit.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func configure(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 16)
    }

    @objc private func modeChanged() {
        mode = Mode(rawValue: segmented.selectedSegmentIndex) ?? .signIn
        submit.setTitle(mode == .signIn ? "Sign In" : "Create Account", for: .normal)
        status.isHidden = true
    }

    @objc private func submitTapped() {
        let email = (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.text ?? ""
        guard !email.isEmpty, !password.isEmpty else {
            show(error: "Enter your email and password.")
            return
        }
        if mode == .register, password.count < 8 {
            show(error: "Password must be at least 8 characters.")
            return
        }
        view.endEditing(true)
        status.isHidden = true
        setBusy(true)
        let currentMode = mode
        Task {
            do {
                if currentMode == .register {
                    try await auth.register(email: email, password: password, client: "ios")
                } else {
                    try await auth.signIn(email: email, password: password, client: "ios")
                }
                setBusy(false)
                onSignedIn()
            } catch {
                let message = (error as? CaptureError)?.message ?? error.localizedDescription
                show(error: message)
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
        submit.isEnabled = !busy
        segmented.isEnabled = !busy
        emailField.isEnabled = !busy
        passwordField.isEnabled = !busy
        submit.alpha = busy ? 0.6 : 1
    }

    private func show(error: String) {
        setBusy(false)
        status.text = error
        status.isHidden = false
    }
}

extension SignInViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === emailField {
            passwordField.becomeFirstResponder()
        } else {
            submitTapped()
        }
        return true
    }
}
