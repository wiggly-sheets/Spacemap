import Foundation
import CoreGraphics


struct HotkeyConfig: Equatable {
    var key: HotkeyKey
    var modifiers: CGEventFlags

    static let `default` = HotkeyConfig(key: .keyCode(121), modifiers: .maskControl)

    var keyCode: CGKeyCode? {
        if case .keyCode(let code) = key { return code }
        return nil
    }

    var mediaKey: MediaKey? {
        if case .mediaKey(let key) = key { return key }
        return nil
    }

    var isDisabled: Bool {
        if case .none = key { return true }
        return false
    }
}

enum HotkeyKey: Equatable {
    case none
    case keyCode(CGKeyCode)
    case mediaKey(MediaKey)
}

enum MediaKey: String, Codable, CaseIterable, Equatable {
    case playPause = "play-pause"
    case nextTrack = "next-track"
    case previousTrack = "previous-track"
    case volumeUp = "volume-up"
    case volumeDown = "volume-down"
    case mute = "mute"
    case brightnessUp = "brightness-up"
    case brightnessDown = "brightness-down"
}

/// One configurable HUD key action. The raw value is the `[hudKeys]` TOML key.
enum HUDCommand: String, CaseIterable, Equatable {
    case left, right, up, down
    case first, last, recent, close
    case newSpace, newSpaceAndFocus, deleteSpace
    case layoutBSP, layoutStack, layoutFloat
    case cycleLayout, moveSpaceBack, moveSpaceForward
    case previousSpace, nextSpace

    /// Display name. Settings is the only place these are shown.
    var label: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .up: return "Up"
        case .down: return "Down"
        case .first: return "First Space"
        case .last: return "Last Space"
        case .recent: return "Recent Space"
        case .close: return "Close HUD"
        case .newSpace: return "New Space"
        case .newSpaceAndFocus: return "New Space and Focus"
        case .deleteSpace: return "Delete Space"
        case .layoutBSP: return "BSP Layout"
        case .layoutStack: return "Stack Layout"
        case .layoutFloat: return "Float Layout"
        case .cycleLayout: return "Cycle Layout"
        case .moveSpaceBack: return "Move Space Left"
        case .moveSpaceForward: return "Move Space Right"
        case .previousSpace: return "Previous Space"
        case .nextSpace: return "Next Space"
        }
    }
}

/// One map for every HUD key action: `[hudKeys]` plus the legacy `[behavior]`
/// scalar keys, which are matched before the table like they always were.
struct HUDKeyBindings: Equatable {
    private var keys: [HUDCommand: [HotkeyConfig]]
    /// Dissolved `[behavior]` scalar keys. Matched before `keys`.
    private var legacy: [HUDCommand: HotkeyConfig]

    init(
        _ keys: [HUDCommand: [HotkeyConfig]] = [:],
        legacy: [HUDCommand: HotkeyConfig] = [:]
    ) {
        // Empty lists are the same as unbound, so they are never stored: a
        // decoded `[]` must equal a map that never had the entry.
        self.keys = keys.filter { !$0.value.isEmpty }
        self.legacy = legacy.filter { !$0.value.isDisabled }
    }

    subscript(command: HUDCommand) -> [HotkeyConfig] {
        get { keys[command] ?? [] }
        set {
            if newValue.isEmpty {
                keys.removeValue(forKey: command)
            } else {
                keys[command] = newValue
            }
        }
    }

    /// Original `[behavior]` check order, kept so a scalar key still wins.
    static let legacyOrder: [HUDCommand] = [
        .moveSpaceBack, .moveSpaceForward, .newSpace, .deleteSpace, .cycleLayout
    ]

    /// Legacy scalar keys as the first-match layer over this table.
    func withLegacy(_ legacy: [HUDCommand: HotkeyConfig]) -> HUDKeyBindings {
        HUDKeyBindings(keys, legacy: legacy)
    }

    /// The same map with the legacy scalars folded into their commands, so a
    /// settings save keeps them once the scalar keys are written unbound.
    func foldingLegacy() -> HUDKeyBindings {
        var folded = self
        for command in Self.legacyOrder {
            guard let hotkey = legacy[command] else { continue }
            let existing = folded.keys[command] ?? []
            // The folded map is written back on save, so a scalar that already
            // matches a table binding must not add a second identical row.
            let identity = Hotkey.bindingIdentity(hotkey)
            if existing.contains(where: { Hotkey.bindingIdentity($0) == identity }) { continue }
            folded.keys[command] = [hotkey] + existing
        }
        folded.legacy = [:]
        return folded
    }

    /// First matching command overall: legacy scalars, then the table.
    func command(for keyCode: CGKeyCode, flags: CGEventFlags) -> HUDCommand? {
        legacyCommand(for: keyCode, flags: flags) ?? tableCommand(for: keyCode, flags: flags)
    }

    /// First matching legacy scalar key, in its original check order.
    func legacyCommand(for keyCode: CGKeyCode, flags: CGEventFlags) -> HUDCommand? {
        Self.legacyOrder.first {
            legacy[$0]?.matches(keyCode: keyCode, flags: flags) == true
        }
    }

    /// First matching `[hudKeys]` binding.
    func tableCommand(for keyCode: CGKeyCode, flags: CGEventFlags) -> HUDCommand? {
        HUDCommand.allCases.first { command in
            self[command].contains { $0.matches(keyCode: keyCode, flags: flags) }
        }
    }

    private static func key(_ name: String) -> HotkeyConfig {
        Hotkey.parseHotkey(name) ?? HotkeyConfig(key: .none, modifiers: [])
    }

    /// Vim and arrow defaults. Editing one action does not touch the others.
    static let `default` = HUDKeyBindings([
        .left: [key("h"), key("left")],
        .right: [key("l"), key("right")],
        .up: [key("k"), key("up")],
        .down: [key("j"), key("down")],
        .first: [key("f")],
        .last: [key("e")],
        .recent: [key("r")],
        .close: [key("escape"), key("c")],
        .newSpace: [key("a")],
        .newSpaceAndFocus: [key("t")],
        .deleteSpace: [key("w")],
        .layoutBSP: [key("b")],
        .layoutStack: [key("s")],
        .layoutFloat: [key("u")],
        .previousSpace: [key("p")],
        .nextSpace: [key("n")]
    ])
}

extension HotkeyConfig {
    /// Key-code and modifier match, following `Hotkey.modifierMatches`.
    func matches(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard case .keyCode(let target) = key, !isDisabled else { return false }
        return keyCode == target && Hotkey.modifierMatches(
            keyCode: keyCode,
            eventFlags: flags,
            bindingModifiers: modifiers
        )
    }
}
