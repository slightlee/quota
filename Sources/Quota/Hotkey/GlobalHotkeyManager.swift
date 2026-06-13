import Carbon.HIToolbox
import AppKit

/// Wraps Carbon Event Hot Key API to register/unregister a single global hotkey.
@MainActor
final class GlobalHotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    /// Shared instance accessible from the Carbon C callback.
    private static var shared: GlobalHotkeyManager?

    private static let hotkeyID = EventHotKeyID(signature: fourCharCode("Quta"), id: 1)

    // MARK: - Public

    func register(keyCode: UInt32, modifiers: UInt32, onTrigger: @escaping () -> Void) {
        unregister()
        self.onTrigger = onTrigger
        Self.shared = self

        guard installEventHandler() else { return }

        let eventID = Self.hotkeyID
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            eventID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status != noErr {
            debugLog("[Hotkey] RegisterEventHotKey failed: \(status)")
            unregister()
        }
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        onTrigger = nil
        Self.shared = nil
    }

    // MARK: - Private

    private func installEventHandler() -> Bool {
        guard eventHandlerRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            GlobalHotkeyManager.carbonCallback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            debugLog("[Hotkey] InstallEventHandler failed: \(status)")
            return false
        }

        return true
    }

    /// Carbon C callback — bridges to the Swift instance via static reference.
    private static let carbonCallback: EventHandlerUPP = { _, _, _ -> OSStatus in
        DispatchQueue.main.async {
            shared?.onTrigger?()
        }
        return noErr
    }
}

// MARK: - Helpers

/// Convert a four-character string to OSType (FourCharCode).
private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) | OSType(char)
    }
    return result
}
