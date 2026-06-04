import AppKit
import SwiftUI
import CaptureCore

@MainActor
final class MacPreferencesStore: ObservableObject {
    @Published var preferences: CapturePreferences {
        didSet { preferences.save() }
    }

    init() {
        self.preferences = CapturePreferences.load()
    }
}

/// Hosts the Settings UI (hotkey, appearance and account) in an AppKit window
/// via NSHostingController, since the app is otherwise pure AppKit.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let store: HotKeyStore
    private let preferences: MacPreferencesStore
    private let onChange: (HotKey) -> Void
    private let onAppearanceChange: (CaptureAppearanceMode) -> Void
    private let onSignOut: () -> Void

    init(
        store: HotKeyStore,
        preferences: MacPreferencesStore,
        onChange: @escaping (HotKey) -> Void,
        onAppearanceChange: @escaping (CaptureAppearanceMode) -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.store = store
        self.preferences = preferences
        self.onChange = onChange
        self.onAppearanceChange = onAppearanceChange
        self.onSignOut = onSignOut
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        super.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: SettingsView(
                store: store,
                preferences: preferences,
                onChange: onChange,
                onAppearanceChange: onAppearanceChange,
                onSignOut: onSignOut
            )
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
    @ObservedObject var preferences: MacPreferencesStore
    let onChange: (HotKey) -> Void
    let onAppearanceChange: (CaptureAppearanceMode) -> Void
    let onSignOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("Keep capture fast, tune the surface, and manage this account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox("Global Hotkey") {
                VStack(alignment: .leading, spacing: 10) {
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
                }
                .padding(.top, 4)
            }

            GroupBox("Appearance") {
                Picker("Mode", selection: Binding(
                    get: { preferences.preferences.appearance },
                    set: { mode in
                        preferences.preferences.appearance = mode
                        onAppearanceChange(mode)
                    }
                )) {
                    ForEach(CaptureAppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 4)
            }

            GroupBox("Account") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Signed in")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                        Text("Password changes use the emailed reset flow from the sign-in screen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sign Out", role: .destructive, action: onSignOut)
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 480, height: 430, alignment: .topLeading)
    }
}
