import AppKit
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

    private override init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    var updater: SPUUpdater { controller.updater }

    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }
}
