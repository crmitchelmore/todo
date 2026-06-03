import AppKit
import SwiftUI

/// A SwiftUI view that lets the user record a custom global hotkey.
/// Adapted (and trimmed — no Fn option) from the justspeaktoit SpeakHotKeys recorder.
struct HotKeyRecorder: View {
    @Binding var hotKey: HotKey
    @State private var isRecording = false
    @State private var pendingModifiers: HotKey.ModifierSet = []

    var body: some View {
        HStack(spacing: 12) {
            hotKeyDisplay
            resetButton
        }
    }

    private var hotKeyDisplay: some View {
        Button {
            isRecording.toggle()
            if isRecording { pendingModifiers = [] }
        } label: {
            Group {
                if isRecording {
                    HStack(spacing: 4) {
                        if !pendingModifiers.isEmpty {
                            Text(pendingModifiers.displayString)
                                .font(.system(.body, design: .rounded))
                        }
                        Text("Press a key…")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } else {
                    Text(hotKey.displayString)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                }
            }
            .frame(minWidth: 120)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isRecording ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .onKeyEvent { event in
            guard isRecording else { return false }
            return handleEvent(event)
        }
    }

    private var resetButton: some View {
        Button {
            isRecording = false
            hotKey = .default
        } label: {
            Text("Reset")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func handleEvent(_ event: NSEvent) -> Bool {
        // Modifier keys arrive as .flagsChanged — use them to live-preview the pending combo.
        if event.type == .flagsChanged {
            pendingModifiers = HotKey.ModifierSet(from: event.modifierFlags)
            return true
        }
        // Escape always cancels recording, even with modifiers held.
        if event.keyCode == 53 {
            isRecording = false
            pendingModifiers = []
            return true
        }
        if KeyCodeMapping.modifierKeyCodes.contains(event.keyCode) {
            pendingModifiers = HotKey.ModifierSet(from: event.modifierFlags)
            return true
        }
        let modifiers = HotKey.ModifierSet(
            from: event.modifierFlags.intersection([.command, .shift, .option, .control])
        )
        guard !modifiers.isEmpty else { return true } // require ≥1 modifier
        hotKey = HotKey(keyCode: event.keyCode, modifiers: modifiers)
        isRecording = false
        return true
    }
}

/// View modifier that intercepts keyDown / flagsChanged events via a local event monitor.
private struct KeyEventMonitor: ViewModifier {
    let handler: (NSEvent) -> Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                    handler(event) ? nil : event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    func onKeyEvent(handler: @escaping (NSEvent) -> Bool) -> some View {
        modifier(KeyEventMonitor(handler: handler))
    }
}
