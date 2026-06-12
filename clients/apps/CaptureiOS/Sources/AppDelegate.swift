import UIKit
import CaptureCore

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let config = CaptureConfig.fromEnvironment()
    private lazy var auth = AuthStore(config: config)
    private lazy var viewModel = CaptureViewModel(auth: auth, config: config)
    private var startedSync = false
    private var shouldFocusQuickCapture = false

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = CapturePreferences.load().appearance.userInterfaceStyle
        window.tintColor = Theme.signal
        self.window = window

        // Swap the root between the sign-in gate and the capture UI as the auth state changes.
        auth.onChange = { [weak self] in
            Task { @MainActor in self?.refreshRoot() }
        }
        refreshRoot()
        window.makeKeyAndVisible()
        handle(urlContexts: connectionOptions.urlContexts)
    }

    @MainActor
    private func refreshRoot() {
        guard let window else { return }
        if auth.isAuthenticated {
            if !startedSync {
                startedSync = true
                Task {
                    await viewModel.store.prepareForActiveUser()
                    await MainActor.run {
                        window.rootViewController = UINavigationController(
                            rootViewController: CaptureViewController(viewModel: viewModel))
                        self.viewModel.start()
                        self.focusQuickCaptureIfNeeded()
                    }
                    await drainOutbox()
                }
            }
        } else {
            startedSync = false
            window.rootViewController = SignInViewController(auth: auth) { [weak self] in
                self?.refreshRoot()
            }
        }
    }

    /// Flush any captures the Share Extension / App Intent queued offline. Fire-and-forget — the
    /// drain is idempotent and re-enqueues anything still unreachable.
    func sceneWillEnterForeground(_ scene: UIScene) {
        guard auth.isAuthenticated else { return }
        viewModel.restartSyncIfNeeded(reason: "foreground")
        Task { await drainOutbox() }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handle(urlContexts: URLContexts)
    }

    private func drainOutbox() async {
        await config.drainOutbox(token: auth)
    }

    private func handle(urlContexts: Set<UIOpenURLContext>) {
        guard urlContexts.contains(where: { $0.url.isQuickCaptureURL }) else { return }
        shouldFocusQuickCapture = true
        focusQuickCaptureIfNeeded()
    }

    @MainActor
    private func focusQuickCaptureIfNeeded() {
        guard shouldFocusQuickCapture,
              let nav = window?.rootViewController as? UINavigationController,
              let capture = nav.viewControllers.first as? CaptureViewController else { return }
        shouldFocusQuickCapture = false
        capture.focusCaptureField()
    }
}

private extension URL {
    var isQuickCaptureURL: Bool {
        scheme == "capture" && (host == "quick-capture" || path == "/quick-capture")
    }
}

private extension CaptureAppearanceMode {
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .dark: return .dark
        case .light: return .light
        }
    }
}
