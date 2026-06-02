import AppKit
import CaptureCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = MacViewModel()            // single shared store / PowerSync instance
    private lazy var captureVC = MacCaptureViewController(viewModel: model)
    private lazy var quick = QuickCaptureController(viewModel: model)
    private var statusItemController: StatusItemController?
    private var window: NSWindow!
    private var hotKey: GlobalHotKey?

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

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let quickItem = appMenu.addItem(withTitle: "Quick Capture", action: #selector(quickCapture), keyEquivalent: " ")
        quickItem.keyEquivalentModifierMask = [.option]
        appMenu.addItem(withTitle: "Open Capture", action: #selector(newCapture), keyEquivalent: "n")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Capture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func quickCapture() { quick.show() }

    @objc private func newCapture() { showMainWindow() }
}
