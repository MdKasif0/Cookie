import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut that calls Cookie to the cursor. It uses Carbon's hot key API,
/// which works system-wide without asking for any permission.
@MainActor
final class SummonHotKey: ObservableObject {
    /// True when the chosen shortcut could not be registered, usually because another app owns it.
    @Published private(set) var isUnavailable = false

    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x434F_4F4B // 'COOK'

    /// Registers `shortcut`, replacing the previous one. `.off` just unregisters.
    @discardableResult
    func register(_ shortcut: SummonShortcut) -> Bool {
        unregister()
        isUnavailable = false
        guard let keyCode = shortcut.keyCode else { return true }

        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            hotKeyRef = nil
            isUnavailable = true
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == SummonHotKey.signature else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<SummonHotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.onTrigger?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
