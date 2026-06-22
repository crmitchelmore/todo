import AppKit
import CaptureCore
import Sparkle

/// Wraps Sparkle's standard updater for the AppKit Mac app.
///
/// Starting the controller kicks off Sparkle's scheduled background checks
/// (driven by the `SU*` keys in Info.plist). `checkForUpdates` is wired to a
/// "Check for Updates…" menu item for on-demand checks.
@MainActor
final class UpdaterController: NSObject {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController
    private let disabled: Bool

    private override init() {
        disabled = ProcessInfo.processInfo.environment["CAPTURE_DISABLE_UPDATER"] == "1"
        controller = SPUStandardUpdaterController(
            startingUpdater: !disabled,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    var updater: SPUUpdater { controller.updater }

    @objc func checkForUpdates(_ sender: Any?) {
        guard !disabled else {
            CaptureDiagnostics.record(category: "updates", name: "updates.check.skipped", message: "Updater disabled for this launch")
            return
        }
        controller.checkForUpdates(sender)
    }
}
