import AppKit
import CaptureCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = MacViewModel()            // single shared store / PowerSync instance
    private lazy var captureVC = MacCaptureViewController(viewModel: model)
    private lazy var quick = QuickCaptureController(viewModel: model)
    private var statusItemController: StatusItemController?
    private var window: NSWindow!
    private var hotKey: GlobalHotKey?
    private let updater = UpdaterController.shared   // starts Sparkle scheduled checks

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        buildWindow()

        statusItemController = StatusItemController(
            viewModel: model,
            onQuickCapture: { [weak self] in self?.quick.show() },
            onOpenMain: { [weak self] in self?.showMainWindow() }
        )

        // ⌥Space from anywhere → Spotlight-style quick capture (does not steal focus context).
        hotKey = GlobalHotKey { [weak self] in self?.quick.toggle() }
        if hotKey?.isRegistered == false {
            NSLog("[Capture] global hotkey registration failed; use the menu bar item to capture.")
        }

        showMainWindow()
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Capture"
        window.contentViewController = captureVC
        window.center()
        window.setFrameAutosaveName("CaptureMainWindow")
    }

    private func showMainWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        captureVC.focusCapture()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // App stays alive in the menu bar after the window is closed. Re-show the main window when the
    // user reactivates via Dock click or ⌘-Tab, otherwise reactivation looks like nothing happens.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if NSApp.windows.allSatisfy({ !$0.isVisible }) { showMainWindow() }
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let quickItem = appMenu.addItem(withTitle: "Quick Capture", action: #selector(quickCapture), keyEquivalent: " ")
        quickItem.keyEquivalentModifierMask = [.option]
        appMenu.addItem(withTitle: "Open Capture", action: #selector(newCapture), keyEquivalent: "n")
        appMenu.addItem(.separator())
        let updateItem = appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Capture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func quickCapture() { quick.show() }

    @objc private func newCapture() { showMainWindow() }

    @objc private func checkForUpdates() { updater.checkForUpdates(nil) }
}
