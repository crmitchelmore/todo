import AppKit
import Carbon.HIToolbox

/// System-wide hotkey via Carbon RegisterEventHotKey (works without Accessibility
/// permission). Reconfigurable at runtime via `update(to:)`. Default: ⌥Space.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    /// The combination currently registered with the system (the last one that succeeded).
    private(set) var current: HotKey
    /// Whether the system accepted the active hotkey registration.
    private(set) var isRegistered = false
    // Carbon hotkey callbacks fire on the main run loop; one instance for the app lifetime.
    nonisolated(unsafe) private static weak var shared: GlobalHotKey?

    init(hotKey: HotKey, action: @escaping () -> Void) {
        self.action = action
        self.current = hotKey
        GlobalHotKey.shared = self
        installHandler()
        _ = register(hotKey)
    }

    /// Re-register on a new combination. Returns false (and restores the previous working
    /// combination) if the system rejects it — e.g. another app already owns that shortcut.
    @discardableResult
    func update(to hotKey: HotKey) -> Bool {
        if register(hotKey) {
            current = hotKey
            return true
        }
        // Roll back to the last known-good combination so we never end up with no hotkey.
        _ = register(current)
        return false
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            GlobalHotKey.shared?.action()
            return noErr
        }, 1, &eventType, nil, &handlerRef)
        if status != noErr {
            NSLog("[Capture] InstallEventHandler failed (status \(status)); global hotkey will not fire.")
        }
    }

    @discardableResult
    private func register(_ hotKey: HotKey) -> Bool {
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x43505448), id: 1) // 'CPTH'
        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode),
            hotKey.modifiers.carbonFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        isRegistered = (status == noErr)
        return isRegistered
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        if GlobalHotKey.shared === self { GlobalHotKey.shared = nil }
    }
}
