import Foundation
import CoreGraphics

extension ConfigSchema {
    static func hotkeyField(
        _ key: String,
        _ keyPath: WritableKeyPath<SpacemapConfig, HotkeyConfig>
    ) -> AnyField {
        Field(
            key: key, section: "behavior",
            keyPath: keyPath,
            decode: { ($0 as? [String: Any]).flatMap(parseHotkeyTable) },
            encode: hotkeyBody, repair: .orDefault
        ).erased
    }

    /// `[behavior.<key>]` body. `modifiers` always closes the table.
    static func hotkeyBody(_ hotkey: HotkeyConfig) -> String {
        var lines: [String]
        switch hotkey.key {
        case .none:
            lines = ["keyKind = \"none\""]
        case .keyCode(let keyCode):
            lines = ["keyKind = \"keyCode\"", "keyCode = \(keyCode)"]
        case .mediaKey(let mediaKey):
            lines = ["keyKind = \"mediaKey\"", "mediaKey = \(ConfigLoader.tomlString(mediaKey.rawValue))"]
        }
        lines.append("modifiers = \(ConfigLoader.tomlStringArray(Hotkey.modifierNames(for: hotkey.modifiers)))")
        return lines.joined(separator: "\n")
    }

    /// `[hudKeys]` body: every command is written, unbound ones as `[]`.
    static func hudKeysBody(_ bindings: HUDKeyBindings) -> String {
        HUDCommand.allCases.map { command in
            let names = bindings[command].filter { !$0.isDisabled }.map(Hotkey.hotkeyToString)
            return "\(command.rawValue) = \(ConfigLoader.tomlStringArray(names))"
        }.joined(separator: "\n")
    }

    static func hudKeysBindings(_ raw: Any) -> HUDKeyBindings? {
        guard let table = raw as? [String: Any] else { return nil }
        var bindings = HUDKeyBindings.default
        for (name, rawNames) in table {
            guard let command = HUDCommand(rawValue: name), let names = rawNames as? [String] else {
                continue
            }
            bindings[command] = names.compactMap { Hotkey.parseHotkey($0) }
        }
        return bindings
    }

    static func hudPositionBody(_ position: HUDPosition) -> String {
        var lines = ["kind = \(ConfigLoader.tomlString(HUDPositionKind(from: position).rawValue))"]
        if case .custom(let x, let y, let screen) = position {
            lines += ["x = \(x)", "y = \(y)"]
            // Optional: a custom position without a display pairing keeps the
            // key out of the file, so old and new files round-trip unchanged.
            if let screen, !screen.isEmpty {
                lines.append("screen = \(ConfigLoader.tomlString(screen))")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func hudPosition(_ raw: Any) -> HUDPosition? {
        guard let table = raw as? [String: Any], let kind = table["kind"] as? String else { return nil }
        switch kind.lowercased() {
        case "center": return .center
        case "top": return .top
        case "bottom": return .bottom
        case "custom":
            // Numeric and in range; no invented 0.5 fallback so repair heals it.
            guard let x = double(table["x"]), let y = double(table["y"]),
                  (0...1).contains(x), (0...1).contains(y) else { return nil }
            let screen = (table["screen"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .custom(x: x, y: y, screen: screen)
        default: return nil
        }
    }

    static func parseHotkeyTable(_ table: [String: Any]) -> HotkeyConfig? {
        guard let kind = table["keyKind"] as? String,
              let modifierNames = table["modifiers"] as? [String] else {
            return nil
        }

        let supportedModifiers = Set(["ctrl", "cmd", "alt", "shift", "fn", "hyper"])
        guard modifierNames.allSatisfy({ supportedModifiers.contains($0.lowercased()) }) else {
            return nil
        }

        let flags = Hotkey.modifiers(from: modifierNames)

        switch kind.lowercased() {
        case "none":
            return HotkeyConfig(key: .none, modifiers: flags)
        case "keycode":
            guard let rawCode = table["keyCode"] as? Int,
                  let keyCode = CGKeyCode(exactly: rawCode) else {
                return nil
            }
            return HotkeyConfig(key: .keyCode(keyCode), modifiers: flags)
        case "mediakey":
            guard let name = table["mediaKey"] as? String,
                  let mediaKey = Hotkey.mediaKeyFor(name) else {
                return nil
            }
            return HotkeyConfig(key: .mediaKey(mediaKey), modifiers: flags)
        default:
            return nil
        }
    }
}
