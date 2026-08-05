import Foundation
import CoreGraphics
import AppKit

public enum Hotkey {

    private static let named: [String: CGKeyCode] = [
        "space": 49, "tab": 48, "return": 36,
        "escape": 53, "delete": 51,
        "pgdn": 121, "pgup": 116,
        "home": 115, "end": 119,
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
        return prefix.isEmpty ? keyString : "\(prefix)+\(keyString)"
    }

        static func hotkeyModifierString(_ modifiers: CGEventFlags) -> String {
        // Hyper combination: cmd+ctrl+shift+option displays as "hyper"
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
        switch keyCode {
        case 49: return "space"
        case 48: return "tab"
        case 36: return "return"
        case 53: return "escape"
        case 51: return "delete"
        case 76: return "delete"
        case 121: return "pgdn"
        case 116: return "pgup"
        case 115: return "home"
        case 119: return "end"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        case 122: return "f1"
        case 120: return "f2"
        case 99:  return "f3"
        case 118: return "f4"
        case 96:  return "f5"
        case 97:  return "f6"
        case 98:  return "f7"
        case 100: return "f8"
        case 101: return "f9"
        case 109: return "f10"
        case 103: return "f11"
        case 111: return "f12"
        case 105: return "f13"
        case 107: return "f14"
        case 113: return "f15"
        case 106: return "f16"
        case 64:  return "f17"
        case 79:  return "f18"
        case 80:  return "f19"
        case 90:  return "f20"
        default:
            return alphanum[keyCode] ?? "unknown"
        }
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
        let keyToken = tokens.last!

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
                print("spacemap: unknown modifier '\(token)' in HOTKEY")
                return nil
            }
        }

        if let keyCode = keyCodeFor(keyToken) {
            return HotkeyConfig(key: .keyCode(keyCode), modifiers: modifiers)
        }
        if let mediaKey = mediaKeyFor(keyToken) {
            return HotkeyConfig(key: .mediaKey(mediaKey), modifiers: modifiers)
        }
        print("spacemap: unknown key '\(keyToken)' in HOTKEY")
        return nil
    }

    static func keyCodeFor(_ token: String) -> CGKeyCode? {
        if let code = named[token] { return code }

        let alphanumReverse: [String: CGKeyCode] = [
            "a": 0,  "s": 1,  "d": 2,  "f": 3,  "h": 4,  "g": 5,
            "z": 6,  "x": 7,  "c": 8,  "v": 9,  "b": 11, "q": 12,
            "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18,
            "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24,
            "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "o": 31,
            "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
            "n": 45, "m": 46,
        ]
        return alphanumReverse[token]
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

    static func parseHotkeyFromEvent(_ event: NSEvent) -> HotkeyConfig {
        var modifiers: CGEventFlags = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.maskControl) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.maskCommand) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.maskAlternate) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.maskShift) }
        if event.modifierFlags.contains(.function) { modifiers.insert(.maskSecondaryFn) }

        let keyCode = event.keyCode
        if keyCode > 0 {
            return HotkeyConfig(key: .keyCode(keyCode), modifiers: modifiers)
        }
        return HotkeyConfig(key: .none, modifiers: [])
    }

}
