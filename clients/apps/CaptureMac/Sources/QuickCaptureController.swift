import AppKit

/// Borderless, non-activating panel that can still take keyboard focus. This is what makes the
/// ⌥Space "Spotlight-style" quick capture work without stealing focus/space from the app you're in.
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating quick-capture surface: one big text field. Enter captures instantly (the write
/// is local-first and returns immediately) and hides the panel; Esc dismisses without saving.
@MainActor
final class QuickCaptureController: NSObject, NSTextFieldDelegate {
    private let viewModel: MacViewModel
    private let panel: CapturePanel
    private let field = NSTextField()
    private let hint = NSTextField(labelWithString: "⏎ capture   ·   esc dismiss")

    init(viewModel: MacViewModel) {
        self.viewModel = viewModel
        self.panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 88),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        buildContent()
    }

    private func configurePanel() {
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    private func buildContent() {
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false

        field.placeholderString = "Capture anything…"
        field.font = .systemFont(ofSize: 24, weight: .regular)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(submit)
        field.translatesAutoresizingMaskIntoConstraints = false

        hint.font = .systemFont(ofSize: 11, weight: .medium)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(blur)
        blur.addSubview(field)
        blur.addSubview(hint)
        panel.contentView = content

        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: content.topAnchor),
            blur.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            field.topAnchor.constraint(equalTo: blur.topAnchor, constant: 16),
            field.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 22),
            field.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -22),

            hint.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
            hint.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 24),
            hint.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -12)
        ])
    }

    /// Toggle: if already visible, hide; otherwise show centered on the screen under the mouse.
    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        viewModel.start() // ensure the shared store is connected
        positionOnActiveScreen()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.count, length: 0)
    }

    func hide() {
        field.stringValue = ""
        panel.orderOut(nil)
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.midY + frame.height * 0.12 // a touch above centre, Spotlight-like
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func submit() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return } // never create blank proposals
        viewModel.capture(text)             // local-first, returns instantly
        hide()
    }

    // Esc to dismiss; Enter handled by the field's action.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            hide()
            return true
        }
        return false
    }
}
