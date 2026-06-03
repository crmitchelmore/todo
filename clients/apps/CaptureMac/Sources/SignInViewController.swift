import AppKit
import AuthenticationServices
import CaptureCore

/// Full-window Sign in with Apple gate shown before any capture UI. On success it hands the Apple
/// identity token to `AuthStore`, which exchanges it for an opaque session token. The owning
/// AppDelegate observes `auth.onChange` to swap this out for the capture UI.
@MainActor
final class SignInViewController: NSViewController {
    private let auth: AuthStore
    private let onSignedIn: () -> Void
    private var currentNonce: AppleNonce?
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

        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        button.target = self
        button.action = #selector(startSignIn)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        status.font = .systemFont(ofSize: 12)
        status.textColor = .systemRed
        status.alignment = .center
        status.maximumNumberOfLines = 3
        status.isHidden = true

        let stack = NSStackView(views: [title, subtitle, button, spinner, status])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 240),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])
        self.view = container
    }

    @objc private func startSignIn() {
        let nonce = AppleNonce()
        currentNonce = nonce
        status.isHidden = true
        spinner.startAnimation(nil)

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        request.nonce = nonce.hashed

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    private func show(error: String) {
        spinner.stopAnimation(nil)
        status.stringValue = error
        status.isHidden = false
    }
}

extension SignInViewController: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            show(error: "Could not read the Apple credential. Please try again.")
            return
        }
        let raw = currentNonce?.raw
        Task {
            do {
                try await auth.signIn(appleIdentityToken: identityToken, rawNonce: raw, client: "mac")
                spinner.stopAnimation(nil)
                onSignedIn()
            } catch {
                show(error: "Sign in failed: \(error.localizedDescription)")
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            spinner.stopAnimation(nil)
            return
        }
        show(error: "Sign in failed: \(error.localizedDescription)")
    }
}

extension SignInViewController: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }
}
