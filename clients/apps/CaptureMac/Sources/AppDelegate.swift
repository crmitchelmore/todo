import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var hotKey: GlobalHotKey?
    private let captureVC = MacCaptureViewController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()

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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        hotKey = GlobalHotKey { [weak self] in self?.summon() }
    }

    private func summon() {
        if window.isVisible && NSApp.isActive {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            captureVC.focusCapture()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "New Capture", action: #selector(newCapture), keyEquivalent: "n")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Capture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func newCapture() {
        window.makeKeyAndOrderFront(nil)
        captureVC.focusCapture()
    }
}
