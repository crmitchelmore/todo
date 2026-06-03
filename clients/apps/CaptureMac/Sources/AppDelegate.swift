import AppKit
import CaptureCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let config = CaptureConfig.fromEnvironment()
    private lazy var auth = AuthStore(config: config)
    private lazy var model = MacViewModel(auth: auth, config: config)  // single shared store / PowerSync instance
    private lazy var captureVC = MacCaptureViewController(viewModel: model)
    private lazy var quick = QuickCaptureController(viewModel: model)
    private var statusItemController: StatusItemController?
    private var window: NSWindow!
    private var hotKey: GlobalHotKey?
    private let hotKeyStore = HotKeyStore()
    private var settingsWindow: SettingsWindowController?
    private var quickAppMenuItem: NSMenuItem?
    private let updater = UpdaterController.shared   // starts Sparkle scheduled checks
    private var started = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        buildWindow()

        statusItemController = StatusItemController(
            viewModel: model,
            onQuickCapture: { [weak self] in self?.quick.show() },
            onOpenMain: { [weak self] in self?.showMainWindow() }
        )

        // Configurable global hotkey (default ⌥Space) from anywhere → Spotlight-style quick
        // capture (does not steal focus context).
        hotKey = GlobalHotKey(hotKey: hotKeyStore.hotKey) { [weak self] in self?.quick.toggle() }
        statusItemController?.setShortcutDisplay(hotKeyStore.hotKey.displayString)
        if hotKey?.isRegistered == false {
            NSLog("[Capture] global hotkey registration failed; use the menu bar item to capture.")
        }

        // Swap the window between the sign-in gate and the capture UI whenever auth changes
        // (sign-in success, sign-out, or a backend 401 that revoked our session).
        auth.onChange = { [weak self] in
            Task { @MainActor in self?.refreshAuthUI() }
        }
        refreshAuthUI()
        showMainWindow()
    }

    /// Drive the root content from the current auth state. After a fresh sign-in we wipe any local
    /// data (so a previous account's optimistic writes can't leak) and start syncing.
    private func refreshAuthUI() {
        if auth.isAuthenticated {
            window.contentViewController = captureVC
            if !started {
                started = true
                Task {
                    try? await model.store.resetLocalData()
                    model.start()
                    captureVC.focusCapture()
                }
            } else {
                captureVC.focusCapture()
            }
        } else {
            started = false
            window.contentViewController = SignInViewController(auth: auth) { [weak self] in
                self?.refreshAuthUI()
            }
        }
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
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("CaptureMainWindow")
    }

    // Hand the capture field our paste-aware editor so pasting a markdown list ingests items.
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        captureVC.fieldEditor(for: client)
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
        let quickItem = appMenu.addItem(withTitle: quickCaptureTitle(for: hotKeyStore.hotKey), action: #selector(quickCapture), keyEquivalent: "")
        quickAppMenuItem = quickItem
        appMenu.addItem(withTitle: "Open Capture", action: #selector(newCapture), keyEquivalent: "n")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        let updateItem = appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        appMenu.addItem(.separator())
        let signOutItem = appMenu.addItem(withTitle: "Sign Out", action: #selector(signOut), keyEquivalent: "")
        signOutItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Capture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // Standard Edit menu so the text fields get Cut/Copy/Paste/Select All and the
        // system keyboard shortcuts (⌘X/⌘C/⌘V/⌘A) reach the first responder.
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func quickCapture() { quick.show() }

    @objc private func newCapture() { showMainWindow() }

    @objc private func checkForUpdates() { updater.checkForUpdates(nil) }

    @objc private func signOut() {
        Task {
            await auth.signOut()
            try? await model.store.resetLocalData()
            refreshAuthUI()
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(store: hotKeyStore) { [weak self] newHotKey in
                self?.applyHotKey(newHotKey)
            }
        }
        settingsWindow?.show()
    }

    /// Re-register the global hotkey live; only persist + show the new shortcut if the
    /// system accepted it, otherwise keep the previous working combination.
    private func applyHotKey(_ newHotKey: HotKey) {
        guard hotKey?.update(to: newHotKey) ?? false else {
            NSLog("[Capture] hotkey \(newHotKey.displayString) unavailable; keeping \(hotKeyStore.hotKey.displayString)")
            return
        }
        hotKeyStore.hotKey = newHotKey
        quickAppMenuItem?.title = quickCaptureTitle(for: newHotKey)
        statusItemController?.setShortcutDisplay(newHotKey.displayString)
    }

    private func quickCaptureTitle(for hotKey: HotKey) -> String {
        "Quick Capture  (\(hotKey.displayString))"
    }
}
