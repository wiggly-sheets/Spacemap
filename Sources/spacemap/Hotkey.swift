import Foundation
import CoreGraphics
import AppKit

public enum Hotkey {

    private static let named: [String: CGKeyCode] = [
        "space": 49, "tab": 48, "return": 36,
        "escape": 53, "delete": 51,
        "pgdn": 121, "pgup": 116,
        "home": 115, "end": 119, "help": 114, "forward-delete": 117,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99,  "f4": 118,
        "f5": 96,  "f6": 97,  "f7": 98,  "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113, "f16": 106,
        "f17": 64, "f18": 79, "f19": 80, "f20": 90,
    ]

    private static let alphanum: [CGKeyCode: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g",
        6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q",
        13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1",
        19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
        25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 31: "o",
        32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m"
    ]

    private static let namedReverse: [CGKeyCode: String] = Dictionary(
        uniqueKeysWithValues: named.map { ($1, $0) }
    )

    private static let alphanumReverse: [String: CGKeyCode] = Dictionary(
        uniqueKeysWithValues: alphanum.map { ($1, $0) }
    )

    private static let punctuation: [CGKeyCode: String] = [
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";",
        42: "backslash", 43: ",", 44: "/", 47: ".", 50: "`",
        65: "keypad-decimal", 67: "keypad-multiply", 69: "keypad-plus",
        71: "keypad-clear", 75: "keypad-divide", 76: "keypad-enter",
        78: "keypad-minus", 81: "keypad-equals", 82: "keypad-0",
        83: "keypad-1", 84: "keypad-2", 85: "keypad-3", 86: "keypad-4",
        87: "keypad-5", 88: "keypad-6", 89: "keypad-7", 91: "keypad-8",
        92: "keypad-9"
    ]

    private static let punctuationReverse: [String: CGKeyCode] = Dictionary(
        uniqueKeysWithValues: punctuation.map { ($1, $0) }
    )

    static var supportedKeyNames: [String] {
        Array(named.keys) + Array(alphanum.values) + Array(punctuation.values)
    }

    static func hotkeyToString(_ hotkey: HotkeyConfig) -> String {
        switch hotkey.key {
        case .none:
            return "none"
        case .keyCode(let keyCode):
            return hotkeyToString(keyCode: keyCode, modifiers: hotkey.modifiers)
        case .mediaKey(let mediaKey):
            return hotkeyToString(mediaKey: mediaKey, modifiers: hotkey.modifiers)
        }
    }

    static func modifierNames(for flags: CGEventFlags) -> [String] {
        var result: [String] = []
        if flags.contains(.maskControl) { result.append("ctrl") }
        if flags.contains(.maskCommand) { result.append("cmd") }
        if flags.contains(.maskAlternate) { result.append("alt") }
        if flags.contains(.maskShift) { result.append("shift") }
        if flags.contains(.maskSecondaryFn) { result.append("fn") }
        return result
    }

    static func modifiers(from names: [String]) -> CGEventFlags {
        var result: CGEventFlags = []
        for name in names {
            switch name.lowercased() {
            case "ctrl": result.insert(.maskControl)
            case "cmd": result.insert(.maskCommand)
            case "alt": result.insert(.maskAlternate)
            case "shift": result.insert(.maskShift)
            case "fn": result.insert(.maskSecondaryFn)
            case "hyper":
                result.insert(.maskCommand)
                result.insert(.maskControl)
                result.insert(.maskAlternate)
                result.insert(.maskShift)
            default:
                break
            }
        }
        return result
    }

    static func hotkeyToString(mediaKey: MediaKey, modifiers: CGEventFlags) -> String {
        let prefix = hotkeyModifierString(modifiers)
        let keyString = mediaKey.rawValue
        return prefix == "none" ? keyString : "\(prefix)+\(keyString)"
    }

        static func hotkeyModifierString(_ modifiers: CGEventFlags) -> String {
        if modifiers.contains(.maskCommand) &&
           modifiers.contains(.maskControl) &&
           modifiers.contains(.maskAlternate) &&
           modifiers.contains(.maskShift) {
            return "hyper"
        }

        var modString = ""
        if modifiers.contains(.maskControl) { modString += "ctrl" }
        if modifiers.contains(.maskCommand) {
            if !modString.isEmpty { modString += "+" }
            modString += "cmd"
        }
        if modifiers.contains(.maskAlternate) {
            if !modString.isEmpty { modString += "+" }
            modString += "alt"
        }
        if modifiers.contains(.maskShift) {
            if !modString.isEmpty { modString += "+" }
            modString += "shift"
        }
        if modifiers.contains(.maskSecondaryFn) {
            if !modString.isEmpty { modString += "+" }
            modString += "fn"
        }
        if modString.isEmpty {
            modString = "none"
        }
        return modString
    }
static func keyCodeToSymbolicString(_ keyCode: CGKeyCode) -> String {
        namedReverse[keyCode] ?? alphanum[keyCode] ?? punctuation[keyCode] ?? "unknown"
    }

    static func hotkeyToString(keyCode: CGKeyCode, modifiers: CGEventFlags) -> String {
        let modString = hotkeyModifierString(modifiers)
        let keyString = keyCodeToSymbolicString(keyCode)
        return (modString == "none" ? "" : modString + "+") + keyString
    }

    static func parseHotkey(_ value: String) -> HotkeyConfig? {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "none" {
            return HotkeyConfig(key: .none, modifiers: [])
        }
        let tokens = value.lowercased().components(separatedBy: "+").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard !tokens.isEmpty else { return nil }

        let modifierTokens = tokens.dropLast()
        guard let keyToken = tokens.last else { return nil }

        var modifiers: CGEventFlags = []
        for token in modifierTokens {
            switch token {
            case "ctrl":  modifiers.insert(.maskControl)
            case "cmd":   modifiers.insert(.maskCommand)
            case "alt":   modifiers.insert(.maskAlternate)
            case "shift": modifiers.insert(.maskShift)
            case "fn": modifiers.insert(.maskSecondaryFn)
            case "hyper":
                modifiers.insert(.maskCommand)
                modifiers.insert(.maskControl)
                modifiers.insert(.maskAlternate)
                modifiers.insert(.maskShift)
            default:
                NSLog("spacemap: unknown modifier '%@' in HOTKEY", token)
                return nil
            }
        }

        if let keyCode = keyCodeFor(keyToken) {
            return HotkeyConfig(key: .keyCode(keyCode), modifiers: modifiers)
        }
        if let mediaKey = mediaKeyFor(keyToken) {
            return HotkeyConfig(key: .mediaKey(mediaKey), modifiers: modifiers)
        }
        NSLog("spacemap: unknown key '%@' in HOTKEY", keyToken)
        return nil
    }

    static func keyCodeFor(_ token: String) -> CGKeyCode? {
        if let code = named[token] { return code }
        if let keyCode = alphanumReverse[token] { return keyCode }
        if let keyCode = punctuationReverse[token] { return keyCode }
        return nil
    }

    static func mediaKeyFor(_ token: String) -> MediaKey? {
        switch token.lowercased() {
        case "play-pause": return .playPause
        case "next-track": return .nextTrack
        case "previous-track": return .previousTrack
        case "volume-up": return .volumeUp
        case "volume-down": return .volumeDown
        case "mute": return .mute
        case "brightness-up": return .brightnessUp
        case "brightness-down": return .brightnessDown
        default: return nil
        }
    }

    static func mediaKeyForSystemKeyCode(_ code: Int) -> MediaKey? {
        switch code {
        case 16: return .playPause
        case 17: return .nextTrack
        case 18: return .previousTrack
        case 0: return .volumeUp
        case 1: return .volumeDown
        case 7: return .mute
        case 2: return .brightnessUp
        case 3: return .brightnessDown
        default: return nil
        }
    }

    static func parseHotkeyFromMediaKeyEvent(_ event: NSEvent) -> HotkeyConfig? {
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return nil }
        let code = Int((event.data1 & 0xFFFF0000) >> 16)
        let keyFlags = event.data1 & 0x0000FFFF
        let state = (keyFlags >> 8) & 0x0F
        let isRepeat = keyFlags & 0x1 != 0
        guard state == 0xA, !isRepeat, let mediaKey = mediaKeyForSystemKeyCode(code) else {
            return nil
        }

        var modifiers: CGEventFlags = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.maskControl) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.maskCommand) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.maskAlternate) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.maskShift) }
        if event.modifierFlags.contains(.function) { modifiers.insert(.maskSecondaryFn) }
        return HotkeyConfig(key: .mediaKey(mediaKey), modifiers: modifiers)
    }

    static func parseHotkeyFromEvent(_ event: NSEvent) -> HotkeyConfig {
        var modifiers: CGEventFlags = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.maskControl) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.maskCommand) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.maskAlternate) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.maskShift) }
        if event.modifierFlags.contains(.function) { modifiers.insert(.maskSecondaryFn) }

        return HotkeyConfig(key: .keyCode(event.keyCode), modifiers: modifiers)
    }

}
