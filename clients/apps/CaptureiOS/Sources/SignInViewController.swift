import UIKit
import AuthenticationServices
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
    private let forgotButton = UIButton(type: .system)
    private let codeButton = UIButton(type: .system)
    private let passkeyButton = UIButton(type: .system)
    private let status = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let passkeys = NativePasskeyAuthorizer()

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

        forgotButton.setTitle("Forgot password?", for: .normal)
        forgotButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        forgotButton.setTitleColor(Theme.textSecondary, for: .normal)
        forgotButton.addTarget(self, action: #selector(forgotTapped), for: .touchUpInside)

        codeButton.setTitle("Email me a sign-in code", for: .normal)
        codeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        codeButton.setTitleColor(Theme.signal, for: .normal)
        codeButton.addTarget(self, action: #selector(codeTapped), for: .touchUpInside)

        passkeyButton.setTitle("Sign in with a passkey", for: .normal)
        passkeyButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        passkeyButton.setTitleColor(Theme.mint, for: .normal)
        passkeyButton.addTarget(self, action: #selector(passkeyTapped), for: .touchUpInside)

        status.font = Theme.mono(13)
        status.textColor = Theme.danger
        status.textAlignment = .center
        status.numberOfLines = 0
        status.isHidden = true

        spinner.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [title, subtitle, segmented, emailField, passwordField, submit, forgotButton, passkeyButton, codeButton, spinner, status])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.setCustomSpacing(28, after: subtitle)
        stack.setCustomSpacing(20, after: submit)
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
        forgotButton.isHidden = mode != .signIn
        status.isHidden = true
    }

    @objc private func forgotTapped() {
        present(purpose: .reset)
    }

    @objc private func codeTapped() {
        present(purpose: .login)
    }

    @objc private func passkeyTapped() {
        guard let anchor = view.window else {
            show(error: "Passkeys are not available yet.")
            return
        }
        setBusy(true)
        status.isHidden = true
        let email = (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let options = try await auth.beginPasskeySignIn(email: email.isEmpty ? nil : email)
                let assertion = try await passkeys.signIn(options: options, anchor: anchor)
                try await auth.finishPasskeySignIn(assertion, client: "ios")
                setBusy(false)
                onSignedIn()
            } catch {
                let message = (error as? CaptureError)?.message ?? error.localizedDescription
                show(error: message)
            }
        }
    }

    private func present(purpose: CodeAuthViewController.Purpose) {
        let vc = CodeAuthViewController(auth: auth, purpose: purpose, onSignedIn: onSignedIn)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
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
        forgotButton.isEnabled = !busy
        codeButton.isEnabled = !busy
        passkeyButton.isEnabled = !busy
        submit.alpha = busy ? 0.6 : 1
    }

    private func show(error: String) {
        setBusy(false)
        status.text = error
        status.isHidden = false
    }
}

@available(iOS 16.0, *)
final class NativePasskeyAuthorizer: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        private var anchor: ASPresentationAnchor?
        private var registrationContinuation: CheckedContinuation<PasskeyRegistrationResult, Error>?
        private var assertionContinuation: CheckedContinuation<PasskeyAuthenticationResult, Error>?

        func register(options: PasskeyRegistrationOptions, anchor: ASPresentationAnchor) async throws -> PasskeyRegistrationResult {
            try await withCheckedThrowingContinuation { continuation in
                self.anchor = anchor
                self.registrationContinuation = continuation
                let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.relyingPartyId)
                let request = provider.createCredentialRegistrationRequest(
                    challenge: options.challenge,
                    name: options.userName,
                    userID: options.userId
                )
                request.userVerificationPreference = .required
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }
        }

        func signIn(options: PasskeyAuthenticationOptions, anchor: ASPresentationAnchor) async throws -> PasskeyAuthenticationResult {
            try await withCheckedThrowingContinuation { continuation in
                self.anchor = anchor
                self.assertionContinuation = continuation
                let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.relyingPartyId)
                let request = provider.createCredentialAssertionRequest(challenge: options.challenge)
                request.userVerificationPreference = .required
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            anchor ?? ASPresentationAnchor()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
                guard let attestationObject = credential.rawAttestationObject else {
                    registrationContinuation?.resume(throwing: CaptureError.auth("Passkey attestation was incomplete."))
                    registrationContinuation = nil
                    return
                }
                registrationContinuation?.resume(returning: PasskeyRegistrationResult(
                    credentialId: credential.credentialID,
                    clientDataJSON: credential.rawClientDataJSON,
                    attestationObject: attestationObject
                ))
                registrationContinuation = nil
                return
            }
            if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
                assertionContinuation?.resume(returning: PasskeyAuthenticationResult(
                    credentialId: credential.credentialID,
                    clientDataJSON: credential.rawClientDataJSON,
                    authenticatorData: credential.rawAuthenticatorData,
                    signature: credential.signature,
                    userHandle: credential.userID
                ))
                assertionContinuation = nil
            }
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            registrationContinuation?.resume(throwing: error)
            assertionContinuation?.resume(throwing: error)
            registrationContinuation = nil
            assertionContinuation = nil
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
