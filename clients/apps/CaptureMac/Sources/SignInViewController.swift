import AppKit
import CaptureCore

/// Full-window email + password gate shown before any capture UI. Toggles between signing in to an
/// existing account and creating a new one, then hands the credentials to `AuthStore`, which
/// exchanges them for an opaque session token. The owning AppDelegate observes `auth.onChange` to
/// swap this out for the capture UI.
@MainActor
final class SignInViewController: NSViewController {
    private enum Mode { case signIn, register }

    private let auth: AuthStore
    private let onSignedIn: () -> Void
    private var mode: Mode = .signIn

    private let segmented = NSSegmentedControl(labels: ["Sign In", "Create Account"],
                                               trackingMode: .selectOne, target: nil, action: nil)
    private let emailField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let submit = NSButton(title: "Sign In", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    init(auth: AuthStore, onSignedIn: @escaping () -> Void) {
        self.auth = auth
        self.onSignedIn = onSignedIn
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 620))

        let title = NSTextField(labelWithString: "Capture")
        title.font = .systemFont(ofSize: 34, weight: .bold)
        title.alignment = .center

        let subtitle = NSTextField(labelWithString: "Sign in to sync your todos across your devices.")
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        segmented.selectedSegment = 0
        segmented.target = self
        segmented.action = #selector(modeChanged)

        emailField.placeholderString = "Email"
        emailField.controlSize = .large
        emailField.font = .systemFont(ofSize: 15)
        emailField.delegate = self

        passwordField.placeholderString = "Password"
        passwordField.controlSize = .large
        passwordField.font = .systemFont(ofSize: 15)
        passwordField.target = self
        passwordField.action = #selector(submitTapped) // Enter in the password field submits.

        submit.bezelStyle = .rounded
        submit.controlSize = .large
        submit.keyEquivalent = "\r"
        submit.target = self
        submit.action = #selector(submitTapped)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        status.font = .systemFont(ofSize: 12)
        status.textColor = .systemRed
        status.alignment = .center
        status.maximumNumberOfLines = 3
        status.isHidden = true

        let stack = NSStackView(views: [title, subtitle, segmented, emailField, passwordField, submit, spinner, status])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            emailField.widthAnchor.constraint(equalToConstant: 300),
            passwordField.widthAnchor.constraint(equalToConstant: 300),
            submit.widthAnchor.constraint(equalToConstant: 300)
        ])
        self.view = container
    }

    @objc private func modeChanged() {
        mode = segmented.selectedSegment == 0 ? .signIn : .register
        submit.title = mode == .signIn ? "Sign In" : "Create Account"
        status.isHidden = true
    }

    @objc private func submitTapped() {
        let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue
        guard !email.isEmpty, !password.isEmpty else {
            show(error: "Enter your email and password.")
            return
        }
        if mode == .register, password.count < 8 {
            show(error: "Password must be at least 8 characters.")
            return
        }
        status.isHidden = true
        setBusy(true)
        let currentMode = mode
        Task {
            do {
                if currentMode == .register {
                    try await auth.register(email: email, password: password, client: "mac")
                } else {
                    try await auth.signIn(email: email, password: password, client: "mac")
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
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        submit.isEnabled = !busy
        segmented.isEnabled = !busy
        emailField.isEnabled = !busy
        passwordField.isEnabled = !busy
    }

    private func show(error: String) {
        setBusy(false)
        status.stringValue = error
        status.isHidden = false
    }
}

extension SignInViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // Tab/Enter from the email field moves focus to the password field.
        if control === emailField, selector == #selector(NSResponder.insertNewline(_:)) {
            view.window?.makeFirstResponder(passwordField)
            return true
        }
        return false
    }
}
