import UIKit
import AuthenticationServices
import CaptureCore

/// Sign in with Apple gate for iOS, shown before the capture UI. Mirrors the macOS gate: runs
/// `ASAuthorizationController`, hands the identity token to `AuthStore`, and lets the SceneDelegate
/// swap in the capture UI on success.
final class SignInViewController: UIViewController {
    private let auth: AuthStore
    private let onSignedIn: () -> Void
    private var currentNonce: AppleNonce?
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
        view.backgroundColor = .systemBackground

        let title = UILabel()
        title.text = "Capture"
        title.font = .systemFont(ofSize: 34, weight: .bold)
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "Sign in to sync your todos across your devices."
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = .secondaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        button.addTarget(self, action: #selector(startSignIn), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false

        status.font = .systemFont(ofSize: 13)
        status.textColor = .systemRed
        status.textAlignment = .center
        status.numberOfLines = 0
        status.isHidden = true

        spinner.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [title, subtitle, button, spinner, status])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            button.widthAnchor.constraint(equalToConstant: 240),
            button.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    @objc private func startSignIn() {
        let nonce = AppleNonce()
        currentNonce = nonce
        status.isHidden = true
        spinner.startAnimating()

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        request.nonce = nonce.hashed

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    private func show(error: String) {
        spinner.stopAnimating()
        status.text = error
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
                try await auth.signIn(appleIdentityToken: identityToken, rawNonce: raw, client: "ios")
                spinner.stopAnimating()
                onSignedIn()
            } catch {
                show(error: "Sign in failed: \(error.localizedDescription)")
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            spinner.stopAnimating()
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
