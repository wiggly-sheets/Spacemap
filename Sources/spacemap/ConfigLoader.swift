import Foundation

enum ConfigLoader: ConfigLoaderProtocol {

    static let configPath = NSString(string: "~/.config/spacemap/config.toml").expandingTildeInPath

    static func load(from path: String, silentMode: Bool) -> (values: ConfigValues, needsRepair: Bool) {
        let contents: String
        do {
            var raw = try String(contentsOfFile: path, encoding: .utf8)
            if raw.hasPrefix("\u{FEFF}") { raw = String(raw.dropFirst()) }
            contents = raw
            if !silentMode { NSLog("spacemap/ConfigLoader: successfully read config from \(path)") }
        } catch {
            if !silentMode { NSLog("spacemap/ConfigLoader: failed to read config at \(path) — error: \(error)") }
            createDefaultConfigFile(at: path)
            return (ConfigValues(), true)
        }

        let values = (try? TOMLParser.parse(contents)) ?? ConfigValues()
        let (_, needsRepair) = values.toGridConfig()
        if needsRepair {
            save(values, to: path)
        }
        return (values, needsRepair)
    }

    static func save(_ values: ConfigValues, to path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        backupConfig(at: path)
        let content = tomlConfigString(from: values, includeHeaderComments: true)
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            print("spacemap: failed to save config to \(path): \(error)")
        }
    }

    static func save(_ config: GridConfig, to path: String) {
        let values = ConfigValues(from: config)
        save(values, to: path)
    }

    static func createDefaultConfigFile(at path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        backupConfig(at: path)
        let content = tomlConfigString(from: ConfigValues(), includeHeaderComments: true)
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            print("spacemap: default config created at \(path)")
        } catch {
            print("spacemap: failed to create default config at \(path): \(error)")
        }
    }


    static func tomlConfigString(from values: ConfigValues, includeHeaderComments: Bool) -> String {
        let defaults = GridConfig.default
        var lines: [String] = []
        if includeHeaderComments {
            lines += [
                "# Spacemap config",
                ""
            ]
        }

        lines += [
            "[grid]",
            "cols = \(values.cols ?? defaults.cols)",
            "rows = \(values.rows ?? defaults.rows)",
            "cellStyle = \(tomlString(ConfigLoader.cellStyleName(values.cellStyle ?? defaults.cellStyle)))",
            "showMode = \(tomlString((values.showMode ?? defaults.showMode).rawValue))",
            "multiMonitorHUDMode = \(tomlString((values.multiMonitorHUDMode ?? defaults.multiMonitorHUDMode).rawValue))",
            "unifiedHUDVisibility = \(tomlString((values.unifiedHUDVisibility ?? defaults.unifiedHUDVisibility).rawValue))",
            "separateHUDVisibility = \(tomlString((values.separateHUDVisibility ?? defaults.separateHUDVisibility).rawValue))",
            "maxSpaces = \(values.maxSpaces ?? defaults.maxSpaces)",
            "showSpaceNumbers = \(values.showSpaceNumbers ?? defaults.showSpaceNumbers)",
            "showIconStrip = \(values.showIconStrip ?? defaults.showIconStrip)",
            "showMultiAppIcons = \(values.showMultiAppIcons ?? defaults.showMultiAppIcons)",
            "",
            "[spaceNames]",
            "showSpaceNames = \(values.showSpaceNames ?? defaults.showSpaceNames)",
            "",
            "[spaceNames.names]"
        ]
        let spaceNames = values.spaceNames ?? defaults.spaceNames
        for key in spaceNames.keys.sorted() {
            if let name = spaceNames[key] {
                lines.append("\(tomlString(String(key))) = \(tomlString(name))")
            }
        }

        lines += [
            "",
            "[appearance]",
            "theme = \(tomlString(values.theme ?? defaults.theme))",
            "mode = \(tomlString((values.mode ?? defaults.mode).rawValue))",
            "backgroundAlpha = \(values.backgroundAlpha ?? defaults.backgroundAlpha)",
            "hudShadow = \(values.hudShadow ?? defaults.hudShadow)",
            "iconScale = \(values.iconScale ?? defaults.iconScale)",
            "uiScale = \(values.uiScale ?? defaults.uiScale)",
            "",
            "[behavior]",
            "autoHideTimeout = \(values.autoHideTimeout ?? defaults.autoHideTimeout)",
            "displayNavigationWrap = \(tomlString((values.displayNavigationWrap ?? defaults.displayNavigationWrap).rawValue))",
            "useVimKeys = \(values.useVimKeys ?? defaults.useVimKeys)",
            "useArrowKeys = \(values.useArrowKeys ?? defaults.useArrowKeys)",
            "jumpToSpaceEnabled = \(values.jumpToSpaceEnabled ?? defaults.jumpToSpaceEnabled)",
            "customHUDX = \(values.customHUDX ?? defaults.customHUDX)",
            "customHUDY = \(values.customHUDY ?? defaults.customHUDY)",
            "focusSpaceOnWindowDrop = \(tomlString((values.focusSpaceOnWindowDrop ?? defaults.focusSpaceOnWindowDrop).rawValue))",
            "focusSpaceOnWindowDropModifier = \(tomlString((values.focusSpaceOnWindowDropModifier ?? defaults.focusSpaceOnWindowDropModifier).rawValue))",
            "showHUDOnSpaceChange = \(values.showHUDOnSpaceChange ?? defaults.showHUDOnSpaceChange)",
            "hideMenuBarIcon = \(values.hideMenuBarIcon ?? defaults.hideMenuBarIcon)",
            "menuBarDisplayMode = \(tomlString((values.menuBarDisplayMode ?? defaults.menuBarDisplayMode).rawValue))",
            "menuBarNearbyCount = \(values.menuBarNearbyCount ?? defaults.menuBarNearbyCount)",
            "updateMode = \(tomlString((values.updateMode ?? defaults.updateMode).rawValue))"
        ]
        appendHotkey(values.hotkey ?? defaults.hotkey, section: "behavior.hotkey", to: &lines)
        appendHotkey(values.pinnedHotkey ?? defaults.pinnedHotkey, section: "behavior.pinnedHotkey", to: &lines)

        lines += ["", "[behavior.hudPosition]"]
        switch values.hudPosition ?? defaults.hudPosition {
        case .center: lines.append("kind = \"center\"")
        case .top: lines.append("kind = \"top\"")
        case .bottom: lines.append("kind = \"bottom\"")
        case .custom(let x, let y):
            lines += ["kind = \"custom\"", "x = \(x)", "y = \(y)"]
        }

        lines += [
            "",
            "[advanced]",
            "socketHealthInterval = \(values.socketHealthInterval ?? defaults.socketHealthInterval)",
            "showExtraWindows = \(values.showExtraWindows ?? defaults.showExtraWindows)"
        ]
        return lines.joined(separator: "\n") + "\n"
    }


    private static func backupConfig(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let backupPath = path + ".bak"
        try? FileManager.default.removeItem(atPath: backupPath)
        try? FileManager.default.copyItem(atPath: path, toPath: backupPath)
    }


    private static func appendHotkey(_ hotkey: HotkeyConfig, section: String, to lines: inout [String]) {
        lines += ["", "[\(section)]"]
        switch hotkey.key {
        case .none:
            lines.append("keyKind = \"none\"")
        case .keyCode(let keyCode):
            lines += ["keyKind = \"keyCode\"", "keyCode = \(keyCode)"]
        case .mediaKey(let mediaKey):
            lines += ["keyKind = \"mediaKey\"", "mediaKey = \(tomlString(mediaKey.rawValue))"]
        }
        lines.append("modifiers = \(tomlStringArray(Hotkey.modifierNames(for: hotkey.modifiers)))")
    }

    static func tomlString(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: escaped += "\\b"
            case 0x09: escaped += "\\t"
            case 0x0A: escaped += "\\n"
            case 0x0C: escaped += "\\f"
            case 0x0D: escaped += "\\r"
            case 0x22: escaped += "\\\""
            case 0x5C: escaped += "\\\\"
            case 0x00...0x1F, 0x7F:
                escaped += String(format: "\\u%04X", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"\(escaped)\""
    }

    private static func tomlStringArray(_ values: [String]) -> String {
        "[" + values.map(tomlString).joined(separator: ", ") + "]"
    }

    static func cellStyleName(_ style: CellStyle) -> String {
        switch style {
        case .rects: return "rects"
        case .hybrid: return "hybrid"
        case .icons: return "icons"
        case .thumbnails: return "thumbnails"
        case .simple: return "simple"
        }
    }
}
