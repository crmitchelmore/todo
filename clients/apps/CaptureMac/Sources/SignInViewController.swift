import AppKit
import AuthenticationServices
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
    private let forgotButton = NSButton(title: "Forgot password?", target: nil, action: nil)
    private let codeButton = NSButton(title: "Email me a sign-in code", target: nil, action: nil)
    private let passkeyButton = NSButton(title: "Sign in with a passkey", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let passkeys = NativePasskeyAuthorizer()

    init(auth: AuthStore, onSignedIn: @escaping () -> Void) {
        self.auth = auth
        self.onSignedIn = onSignedIn
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 620))
        Theme.paintInk(container)

        let title = NSTextField(labelWithString: "Capture")
        title.font = Theme.display(40, .heavy)
        title.textColor = Theme.signal
        title.alignment = .center

        let subtitle = NSTextField(labelWithString: "An instrument for thought. Sign in to sync across your devices.")
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = Theme.textSecondary
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
        Theme.primary(submit, fontSize: 15)

        forgotButton.bezelStyle = .inline
        forgotButton.isBordered = false
        forgotButton.contentTintColor = Theme.textSecondary
        forgotButton.font = .systemFont(ofSize: 13, weight: .medium)
        forgotButton.target = self
        forgotButton.action = #selector(forgotTapped)

        codeButton.bezelStyle = .inline
        codeButton.isBordered = false
        codeButton.contentTintColor = Theme.signal
        codeButton.font = .systemFont(ofSize: 14, weight: .semibold)
        codeButton.target = self
        codeButton.action = #selector(codeTapped)

        passkeyButton.bezelStyle = .inline
        passkeyButton.isBordered = false
        passkeyButton.contentTintColor = Theme.mint
        passkeyButton.font = .systemFont(ofSize: 14, weight: .semibold)
        passkeyButton.target = self
        passkeyButton.action = #selector(passkeyTapped)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        status.font = Theme.mono(12)
        status.textColor = Theme.danger
        status.alignment = .center
        status.maximumNumberOfLines = 3
        status.isHidden = true

        let stack = NSStackView(views: [title, subtitle, segmented, emailField, passwordField, submit, forgotButton, passkeyButton, codeButton, spinner, status])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(20, after: submit)
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
        Theme.primary(submit, fontSize: 15)
        forgotButton.isHidden = mode != .signIn
        status.isHidden = true
    }

    @objc private func forgotTapped() { present(purpose: .reset) }
    @objc private func codeTapped() { present(purpose: .login) }

    @objc private func passkeyTapped() {
        guard let window = view.window else {
            show(error: "Passkeys are not available yet.")
            return
        }
        let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        status.isHidden = true
        setBusy(true)
        Task {
            do {
                let options = try await auth.beginPasskeySignIn(email: email.isEmpty ? nil : email)
                let assertion = try await passkeys.signIn(options: options, anchor: window)
                try await auth.finishPasskeySignIn(assertion, client: "mac")
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
        presentAsSheet(vc)
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
        forgotButton.isEnabled = !busy
        codeButton.isEnabled = !busy
        passkeyButton.isEnabled = !busy
    }

    private func show(error: String) {
        setBusy(false)
        status.stringValue = error
        status.isHidden = false
    }
}

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
