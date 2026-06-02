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

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(rootViewController: CaptureViewController())
        window.makeKeyAndVisible()
        self.window = window
        drainOutbox()
    }

    /// Flush any captures the Share Extension / App Intent queued offline. Fire-and-forget — the
    /// drain is idempotent and re-enqueues anything still unreachable.
    func sceneWillEnterForeground(_ scene: UIScene) {
        drainOutbox()
    }

    private func drainOutbox() {
        Task { await CaptureConfig.fromEnvironment().drainOutbox() }
    }
}
