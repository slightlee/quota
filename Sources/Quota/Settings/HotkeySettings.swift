import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - HotkeyConfiguration

struct HotkeyConfiguration: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var isEnabled: Bool

    static let empty = HotkeyConfiguration(keyCode: 0, modifiers: 0, isEnabled: false)

    var isEmpty: Bool { keyCode == 0 && modifiers == 0 }
    var isValid: Bool { keyCode != 0 && modifiers != 0 }

    var displayString: String? {
        guard !isEmpty else { return nil }
        return HotkeyKeymap.modifierSymbols(from: modifiers) + HotkeyKeymap.character(for: keyCode)
    }
}

// MARK: - HotkeySettingsStore

final class HotkeySettingsStore {
    static let shared = HotkeySettingsStore()

    private let defaults: UserDefaults
    private let keyCodeKey = "hotkey.keyCode"
    private let modifiersKey = "hotkey.modifiers"
    private let enabledKey = "hotkey.enabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var configuration: HotkeyConfiguration {
        get {
            let keyCode = UInt32(defaults.integer(forKey: keyCodeKey))
            let modifiers = UInt32(defaults.integer(forKey: modifiersKey))
            let isEnabled = defaults.bool(forKey: enabledKey)
            return HotkeyConfiguration(keyCode: keyCode, modifiers: modifiers, isEnabled: isEnabled)
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: keyCodeKey)
            defaults.set(Int(newValue.modifiers), forKey: modifiersKey)
            defaults.set(newValue.isEnabled, forKey: enabledKey)
        }
    }
}

// MARK: - HotkeyKeymap

/// Shared utilities for modifier flag conversion and key code mapping.
enum HotkeyKeymap {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    static func modifierSymbols(from carbonMods: UInt32) -> String {
        var result = ""
        if carbonMods & UInt32(cmdKey) != 0 { result += "⌘" }
        if carbonMods & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonMods & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonMods & UInt32(controlKey) != 0 { result += "⌃" }
        return result
    }

    static func modifierSymbols(from flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.command) { result += "⌘" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.control) { result += "⌃" }
        return result
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        modifierSymbols(from: modifiers) + character(for: keyCode)
    }

    static func character(for keyCode: UInt32) -> String {
        keyMapping[keyCode] ?? "?\(keyCode)"
    }

    private static let keyMapping: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 103: "F11", 109: "F10", 111: "F12",
        118: "F4", 120: "F2", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
