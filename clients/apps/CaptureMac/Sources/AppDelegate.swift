import AppKit
import CaptureCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let config = CaptureConfig.fromEnvironment()
    private lazy var auth = AuthStore(config: config)
    private lazy var model = MacViewModel(auth: auth, config: config)  // single shared store / PowerSync instance
    private lazy var captureVC: MacCaptureViewController = {
        let vc = MacCaptureViewController(viewModel: model)
        vc.onOpenSettings = { [weak self] in self?.openSettings() }
        return vc
    }()
    private lazy var quick = QuickCaptureController(viewModel: model)
    private var statusItemController: StatusItemController?
    private var window: NSWindow!
    private var hotKey: GlobalHotKey?
    private let hotKeyStore = HotKeyStore()
    private let preferencesStore = MacPreferencesStore()
    private var settingsWindow: SettingsWindowController?
    private var quickAppMenuItem: NSMenuItem?
    private let updater = UpdaterController.shared   // starts Sparkle scheduled checks
    private var started = false
    private let passkeys = NativePasskeyAuthorizer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        applyAppearance(preferencesStore.preferences.appearance)
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
                    await model.store.prepareForActiveUser()
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
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Capture"
        window.backgroundColor = Theme.ink
        window.contentMinSize = NSSize(width: 980, height: 620)
        window.contentViewController = captureVC
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("CaptureMainWindow")
        if window.frame.width < 980 || window.frame.height < 620 {
            window.setContentSize(NSSize(width: 1180, height: 760))
            window.center()
        }
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
        model.restartSyncIfNeeded(reason: "app became active")
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let quickItem = appMenu.addItem(withTitle: quickCaptureTitle(for: hotKeyStore.hotKey), action: #selector(quickCapture), keyEquivalent: "")
        quickAppMenuItem = quickItem
        appMenu.addItem(withTitle: "Open Capture", action: #selector(newCapture), keyEquivalent: "n")
        let passkeyItem = appMenu.addItem(withTitle: "Add Passkey…", action: #selector(addPasskey), keyEquivalent: "")
        passkeyItem.target = self
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
            await model.store.clearActiveUser()
            refreshAuthUI()
        }
    }

    @objc private func addPasskey() {
        guard auth.isAuthenticated else { return }
        showMainWindow()
        Task {
            do {
                let options = try await auth.beginPasskeyRegistration()
                let registration = try await passkeys.register(options: options, anchor: window)
                try await auth.finishPasskeyRegistration(registration)
                showPasskeyAlert(title: "Passkey added", message: "This Mac can now sign in to Capture with a passkey.")
            } catch {
                showPasskeyAlert(title: "Passkey unavailable",
                                 message: (error as? CaptureError)?.message ?? error.localizedDescription)
            }
        }
    }

    private func showPasskeyAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                store: hotKeyStore,
                preferences: preferencesStore,
                onChange: { [weak self] newHotKey in self?.applyHotKey(newHotKey) },
                onAppearanceChange: { [weak self] mode in self?.applyAppearance(mode) },
                onSignOut: { [weak self] in self?.signOut() }
            )
        }
        settingsWindow?.show()
    }

    private func applyAppearance(_ mode: CaptureAppearanceMode) {
        let appearance: NSAppearance?
        switch mode {
        case .system: appearance = nil
        case .dark: appearance = NSAppearance(named: .darkAqua)
        case .light: appearance = NSAppearance(named: .aqua)
        }
        NSApp.appearance = appearance
        window?.appearance = appearance
        settingsWindow?.window?.appearance = appearance
        window?.backgroundColor = Theme.ink
        if window != nil { captureVC.applyTheme() }
        NotificationCenter.default.post(name: .captureAppearanceChanged, object: nil)
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
