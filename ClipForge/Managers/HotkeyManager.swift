import Foundation
import Carbon.HIToolbox
import AppKit

// MARK: - C-level event handler (required by Carbon API)
// Must be a top-level function - cannot be a closure.

private func carbonEventHandler(
    _ handlerRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard err == noErr else { return OSStatus(eventNotHandledErr) }

    if let userData {
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        manager.handleHotKey(id: hotKeyID.id)
    }
    return noErr
}

// MARK: - HotkeyManager

/// Registers and manages global keyboard shortcuts using the Carbon Event Manager.
/// Does not require Accessibility permission - only the screen recording permission
/// already needed for capture.
final class HotkeyManager {

    static let shared = HotkeyManager()

    // MARK: - Actions (set by the app)
    var onSaveClip: (() -> Void)?
    var onToggleCapture: (() -> Void)?
    var onToggleMic: (() -> Void)?
    var onOpenApp: (() -> Void)?

    // MARK: - Private

    private var eventHandlerRef: EventHandlerRef?
    private var registeredKeys: [UInt32: EventHotKeyRef] = [:]
    private var callbacks: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    // Stable IDs for the four app hotkeys
    private let saveClipID: UInt32    = 1
    private let toggleCaptureID: UInt32 = 2
    private let toggleMicID: UInt32   = 3
    private let openAppID: UInt32     = 4

    private init() {
        installEventHandler()
    }

    // MARK: - Public API

    func applyBindings(
        saveClip: HotkeyBinding,
        toggleCapture: HotkeyBinding,
        toggleMic: HotkeyBinding,
        openApp: HotkeyBinding
    ) {
        registerHotkey(binding: saveClip,      id: saveClipID,      callback: { [weak self] in self?.onSaveClip?() })
        registerHotkey(binding: toggleCapture, id: toggleCaptureID, callback: { [weak self] in self?.onToggleCapture?() })
        registerHotkey(binding: toggleMic,     id: toggleMicID,     callback: { [weak self] in self?.onToggleMic?() })
        registerHotkey(binding: openApp,       id: openAppID,       callback: { [weak self] in self?.onOpenApp?() })
    }

    func unregisterAll() {
        for (_, ref) in registeredKeys {
            UnregisterEventHotKey(ref)
        }
        registeredKeys.removeAll()
        callbacks.removeAll()
    }

    // MARK: - Internal

    fileprivate func handleHotKey(id: UInt32) {
        callbacks[id]?()
    }

    // MARK: - Private helpers

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func registerHotkey(binding: HotkeyBinding, id: UInt32, callback: @escaping () -> Void) {
        // Unregister existing binding for this ID
        if let existing = registeredKeys[id] {
            UnregisterEventHotKey(existing)
            registeredKeys.removeValue(forKey: id)
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharCode("CFGE"), id: id)
        let carbonMods = carbonModifiers(from: binding.modifiers)

        let err = RegisterEventHotKey(
            UInt32(binding.keyCode),
            carbonMods,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if err == noErr, let ref = hotKeyRef {
            registeredKeys[id] = ref
            callbacks[id] = callback
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command)  { mods |= UInt32(cmdKey) }
        if flags.contains(.option)   { mods |= UInt32(optionKey) }
        if flags.contains(.control)  { mods |= UInt32(controlKey) }
        if flags.contains(.shift)    { mods |= UInt32(shiftKey) }
        return mods
    }
}

// MARK: - Helpers

private func fourCharCode(_ string: String) -> FourCharCode {
    assert(string.count == 4)
    var result: FourCharCode = 0
    for char in string.unicodeScalars {
        result = (result << 8) + FourCharCode(char.value)
    }
    return result
}
