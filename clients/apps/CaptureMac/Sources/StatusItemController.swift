import AppKit
import CaptureCore

/// Always-present menu bar entry: shows the count of items needing confirmation and is a second
/// quick-capture entry point (click → open the quick panel). The menu opens the main review window.
@MainActor
final class StatusItemController: NSObject {
    private let viewModel: MacViewModel
    private let statusItem: NSStatusItem
    private let onQuickCapture: () -> Void
    private let onOpenMain: () -> Void
    private var quickMenuItem: NSMenuItem?

    init(
        viewModel: MacViewModel,
        onQuickCapture: @escaping () -> Void,
        onOpenMain: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onQuickCapture = onQuickCapture
        self.onOpenMain = onOpenMain
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        buildMenu()
        viewModel.addObserver { [weak self] in self?.refresh() }
        refresh()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Capture")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
    }

    private func buildMenu() {
        let menu = NSMenu()
        let quick = menu.addItem(
            withTitle: "Quick Capture",
            action: #selector(quickCapture),
            keyEquivalent: ""
        )
        quick.target = self
        quickMenuItem = quick
        menu.addItem(
            withTitle: "Open Capture…",
            action: #selector(openMain),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Capture",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
    }

    /// Update the Quick Capture menu item to show the currently configured shortcut.
    func setShortcutDisplay(_ shortcut: String) {
        quickMenuItem?.title = "Quick Capture  (\(shortcut))"
    }

    private func refresh() {
        guard let button = statusItem.button else { return }
        let count = viewModel.proposed.count
        button.title = count > 0 ? " \(count)" : ""
    }

    @objc private func quickCapture() {
        CaptureDiagnostics.record(category: "ui", name: "menu.status.quick_capture", message: "Status menu quick capture clicked")
        onQuickCapture()
    }

    @objc private func openMain() {
        CaptureDiagnostics.record(category: "ui", name: "menu.status.open_main", message: "Status menu open main clicked")
        onOpenMain()
    }
}
