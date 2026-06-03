import AppKit
import SwiftUI

/// Hosts the Settings UI (currently the global-hotkey recorder) in an AppKit window
/// via NSHostingController, since the app is otherwise pure AppKit.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let store: HotKeyStore
    private let onChange: (HotKey) -> Void

    init(store: HotKeyStore, onChange: @escaping (HotKey) -> Void) {
        self.store = store
        self.onChange = onChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        super.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: SettingsView(store: store, onChange: onChange)
        )
        window.center()
        window.setFrameAutosaveName("CaptureSettingsWindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsView: View {
    @ObservedObject var store: HotKeyStore
    let onChange: (HotKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Global Hotkey")
                .font(.title3).bold()
            Text("Press this combination anywhere to summon quick capture. Click the field, then press your shortcut — it needs at least one modifier (⌘ ⌥ ⌃ ⇧).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HotKeyRecorder(hotKey: Binding(
                get: { store.hotKey },
                set: { newValue in
                    // Let the app try to register it; it persists store.hotKey only on success,
                    // so a rejected combo leaves the recorder showing the previous shortcut.
                    onChange(newValue)
                }
            ))
            Spacer()
        }
        .padding(20)
        .frame(width: 440, height: 240, alignment: .topLeading)
    }
}
