import AppKit
import Carbon.HIToolbox

/// System-wide hotkey via Carbon RegisterEventHotKey (works without Accessibility
/// permission). Default: ⌥Space to summon the capture window.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    // Carbon hotkey callbacks fire on the main run loop.
    nonisolated(unsafe) private static var shared: GlobalHotKey?

    init(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(optionKey), action: @escaping () -> Void) {
        self.action = action
        GlobalHotKey.shared = self
        register(keyCode: keyCode, modifiers: modifiers)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            GlobalHotKey.shared?.action()
            return noErr
        }, 1, &eventType, nil, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x43505448), id: 1) // 'CPTH'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
