import Foundation
import CoreGraphics

enum Config {
    static var silentMode = false
    static let configPath = NSString(string: "~/.config/spacemap/config.toml").expandingTildeInPath

    public static func load() -> GridConfig {
        return load(from: configPath)
    }

    public static func load(from path: String) -> GridConfig {
        let contents: String
        do {
            var raw = try String(contentsOfFile: path, encoding: .utf8)
            if raw.hasPrefix("\u{FEFF}") { raw = String(raw.dropFirst()) }
            contents = raw
            if !silentMode { NSLog("spacemap/Config: successfully read config from \(path)") }
        } catch {
            if !silentMode { NSLog("spacemap/Config: failed to read config at \(path) — error: \(error)") }
            createDefaultConfigFile(at: path)
            return .default
        }

        if let parsed = parseTOMLConfig(contents) {
            if parsed.needsRepair {
                saveConfig(parsed.config, to: path)
            }
            return parsed.config
        }
        saveConfig(.default, to: path)
        return .default
    }

    internal static func parseConfig(_ text: String) -> GridConfig {
        return parseTOMLConfig(text)?.config ?? .default
    }

    private static func parseTOMLConfig(_ text: String) -> (config: GridConfig, needsRepair: Bool)? {
        guard let parsedObject = parseTOMLObject(text) else { return nil }
        let object = normalizedTOMLObject(parsedObject)
        return decodedTOMLConfig(object)
    }

    private static func decodedTOMLConfig(_ object: [String: Any]) -> (config: GridConfig, needsRepair: Bool) {
        let defaults = GridConfig.default
        var repair = false

        func value<T>(_ key: String, default defaultValue: T) -> T {
            guard let result = object[key] as? T else {
                repair = true
                return defaultValue
            }
            return result
        }

        func double(_ key: String, default defaultValue: Double) -> Double {
            if let result = object[key] as? Double { return result }
            if let result = object[key] as? Int { return Double(result) }
            repair = true
            return defaultValue
        }

        func valid<T>(_ candidate: T, default defaultValue: T, where predicate: (T) -> Bool) -> T {
            guard predicate(candidate) else {
                repair = true
                return defaultValue
            }
            return candidate
        }

        func hotkey(_ key: String, default defaultValue: HotkeyConfig) -> HotkeyConfig {
            guard let table = object[key] as? [String: Any],
                  let kind = table["keyKind"] as? String,
                  let modifierNames = table["modifiers"] as? [String] else {
                repair = true
                return defaultValue
            }
            let canonicalModifiers = Set(["ctrl", "cmd", "alt", "shift", "fn"])
            if modifierNames.contains(where: { !canonicalModifiers.contains($0.lowercased()) }) {
                repair = true
            }
            let flags = Hotkey.modifiers(from: modifierNames)
            switch kind.lowercased() {
            case "none":
                return HotkeyConfig(key: .none, modifiers: flags)
            case "keycode":
                guard let rawCode = table["keyCode"] as? Int,
                      let keyCode = CGKeyCode(exactly: rawCode) else {
                    repair = true
                    return defaultValue
                }
                return HotkeyConfig(key: .keyCode(keyCode), modifiers: flags)
            case "mediakey":
                guard let name = table["mediaKey"] as? String,
                      let mediaKey = MediaKey(rawValue: name.lowercased()) else {
                    repair = true
                    return defaultValue
                }
                return HotkeyConfig(key: .mediaKey(mediaKey), modifiers: flags)
            default:
                repair = true
                return defaultValue
            }
        }

        let rawSpaceNames = value("spaceNames", default: [String: Any]())
        var spaceNames: [Int: String] = [:]
        for (key, rawName) in rawSpaceNames {
            guard let index = Int(key), let name = rawName as? String else {
                repair = true
                continue
            }
            spaceNames[index] = name
        }

        let position: HUDPosition
        if let table = object["hudPosition"] as? [String: Any],
           let kind = table["kind"] as? String {
            switch kind.lowercased() {
            case "center": position = .center
            case "top": position = .top
            case "bottom": position = .bottom
            case "custom":
                let x = (table["x"] as? Double) ?? (table["x"] as? Int).map(Double.init)
                    ?? double("customHUDX", default: defaults.customHUDX)
                let y = (table["y"] as? Double) ?? (table["y"] as? Int).map(Double.init)
                    ?? double("customHUDY", default: defaults.customHUDY)
                if (0...1).contains(x), (0...1).contains(y) {
                    position = .custom(x: x, y: y)
                } else {
                    repair = true
                    position = .center
                }
            default:
                repair = true
                position = .center
            }
        } else {
            repair = true
            position = defaults.hudPosition
        }

        let cellStyleName: String = value("cellStyle", default: Config.cellStyleName(defaults.cellStyle))
        let showModeName: String = value("showMode", default: defaults.showMode.rawValue)
        let multiMonitorName: String = value("multiMonitorHUDMode", default: defaults.multiMonitorHUDMode.rawValue)
        let unifiedVisibilityName: String = value("unifiedHUDVisibility", default: defaults.unifiedHUDVisibility.rawValue)
        let separateVisibilityName: String = value("separateHUDVisibility", default: defaults.separateHUDVisibility.rawValue)
        let navigationWrapName: String = value("displayNavigationWrap", default: defaults.displayNavigationWrap.rawValue)
        let themeModeName: String = value("mode", default: defaults.mode.rawValue)
        let updateModeName: String = value("updateMode", default: defaults.updateMode.rawValue)
        let menuBarDisplayModeName: String = value("menuBarDisplayMode", default: defaults.menuBarDisplayMode.rawValue)
        let windowDropFocusModeName: String = value(
            "focusSpaceOnWindowDrop",
            default: defaults.focusSpaceOnWindowDrop.rawValue
        )
        let windowDropModifierName: String = value(
            "focusSpaceOnWindowDropModifier",
            default: defaults.focusSpaceOnWindowDropModifier.rawValue
        )
        let windowDropModifier = WindowDropFocusModifier(rawValue: windowDropModifierName.lowercased())
        if windowDropModifier == nil {
            repair = true
        }

        let resolvedCellStyle = cellStyle(from: cellStyleName)
        let resolvedShowMode = showMode(from: showModeName)
        let resolvedMultiMonitorMode = multiMonitorHUDMode(from: multiMonitorName)
        let resolvedUnifiedVisibility = hudVisibility(from: unifiedVisibilityName)
        let resolvedSeparateVisibility = hudVisibility(from: separateVisibilityName)
        let resolvedNavigationWrap = displayNavigationWrap(from: navigationWrapName)
        let resolvedThemeMode = themeMode(from: themeModeName)
        let resolvedUpdateMode = updateMode(from: updateModeName)
        let resolvedMenuBarDisplayMode = menuBarDisplayMode(from: menuBarDisplayModeName)
        let resolvedWindowDropFocusMode = WindowDropFocusMode(rawValue: windowDropFocusModeName.lowercased())
        if resolvedCellStyle == nil || resolvedShowMode == nil || resolvedMultiMonitorMode == nil ||
            resolvedUnifiedVisibility == nil || resolvedSeparateVisibility == nil ||
            resolvedNavigationWrap == nil || resolvedThemeMode == nil || resolvedUpdateMode == nil ||
            resolvedMenuBarDisplayMode == nil || resolvedWindowDropFocusMode == nil {
            repair = true
        }

        let config = GridConfig(
            cols: valid(value("cols", default: defaults.cols), default: defaults.cols) { $0 > 0 },
            rows: valid(value("rows", default: defaults.rows), default: defaults.rows) { $0 > 0 },
            cellStyle: resolvedCellStyle ?? defaults.cellStyle,
            hotkey: hotkey("hotkey", default: defaults.hotkey),
            pinnedHotkey: hotkey("pinnedHotkey", default: defaults.pinnedHotkey),
            socketHealthInterval: valid(value("socketHealthInterval", default: defaults.socketHealthInterval), default: defaults.socketHealthInterval) { $0 > 0 },
            uiScale: valid(double("uiScale", default: defaults.uiScale), default: defaults.uiScale) { (0...1).contains($0) },
            autoHideTimeout: valid(value("autoHideTimeout", default: defaults.autoHideTimeout), default: defaults.autoHideTimeout) { $0 >= 0 },
            theme: value("theme", default: defaults.theme),
            showMode: resolvedShowMode ?? defaults.showMode,
            multiMonitorHUDMode: resolvedMultiMonitorMode ?? defaults.multiMonitorHUDMode,
            unifiedHUDVisibility: resolvedUnifiedVisibility ?? defaults.unifiedHUDVisibility,
            separateHUDVisibility: resolvedSeparateVisibility ?? defaults.separateHUDVisibility,
            displayNavigationWrap: resolvedNavigationWrap ?? defaults.displayNavigationWrap,
            maxSpaces: valid(value("maxSpaces", default: defaults.maxSpaces), default: defaults.maxSpaces) { (1...16).contains($0) },
            backgroundAlpha: valid(double("backgroundAlpha", default: defaults.backgroundAlpha), default: defaults.backgroundAlpha) { (0...1).contains($0) },
            mode: resolvedThemeMode ?? defaults.mode,
            iconScale: valid(double("iconScale", default: defaults.iconScale), default: defaults.iconScale) { (0...1).contains($0) },
            showSpaceNumbers: value("showSpaceNumbers", default: defaults.showSpaceNumbers),
            showSpaceNames: value("showSpaceNames", default: defaults.showSpaceNames),
            showIconStrip: value("showIconStrip", default: defaults.showIconStrip),
            showMultiAppIcons: value("showMultiAppIcons", default: defaults.showMultiAppIcons),
            hideMenuBarIcon: value("hideMenuBarIcon", default: defaults.hideMenuBarIcon),
            menuBarDisplayMode: resolvedMenuBarDisplayMode ?? defaults.menuBarDisplayMode,
            menuBarNearbyCount: valid(value("menuBarNearbyCount", default: defaults.menuBarNearbyCount), default: defaults.menuBarNearbyCount) { (1...16).contains($0) },
            spaceNames: spaceNames,
            useVimKeys: value("useVimKeys", default: defaults.useVimKeys),
            useArrowKeys: value("useArrowKeys", default: defaults.useArrowKeys),
            hudPosition: position,
            customHUDX: valid(double("customHUDX", default: defaults.customHUDX), default: defaults.customHUDX) { (0...1).contains($0) },
            customHUDY: valid(double("customHUDY", default: defaults.customHUDY), default: defaults.customHUDY) { (0...1).contains($0) },
            showExtraWindows: value("showExtraWindows", default: defaults.showExtraWindows),
            focusSpaceOnWindowDrop: resolvedWindowDropFocusMode ?? defaults.focusSpaceOnWindowDrop,
            focusSpaceOnWindowDropModifier: windowDropModifier ?? defaults.focusSpaceOnWindowDropModifier,
            showHUDOnSpaceChange: value("showHUDOnSpaceChange", default: defaults.showHUDOnSpaceChange),
            updateMode: resolvedUpdateMode ?? defaults.updateMode
        )
        return (config, repair)
    }

    private static func normalizedTOMLObject(_ object: [String: Any]) -> [String: Any] {
        var result = object

        func flatten(_ sectionName: String, keys: [String]) {
            guard let section = result.removeValue(forKey: sectionName) as? [String: Any] else { return }
            for key in keys {
                if let value = section[key] { result[key] = value }
            }
        }

        flatten("grid", keys: [
            "cols", "rows", "cellStyle", "showMode", "multiMonitorHUDMode",
            "unifiedHUDVisibility", "separateHUDVisibility", "maxSpaces",
            "showSpaceNumbers", "showIconStrip", "showMultiAppIcons"
        ])
        flatten("appearance", keys: [
            "theme", "mode", "backgroundAlpha", "iconScale", "uiScale"
        ])
        flatten("behavior", keys: [
            "autoHideTimeout", "displayNavigationWrap", "useVimKeys", "useArrowKeys",
            "customHUDX", "customHUDY", "focusSpaceOnWindowDrop", "showHUDOnSpaceChange",
            "focusSpaceOnWindowDropModifier", "hideMenuBarIcon", "menuBarDisplayMode",
            "menuBarNearbyCount", "updateMode"
        ])
        flatten("advanced", keys: ["socketHealthInterval", "showExtraWindows"])

        if let section = result["spaceNames"] as? [String: Any],
           section["showSpaceNames"] != nil {
            result["showSpaceNames"] = section["showSpaceNames"]
            result.removeValue(forKey: "spaceNames")
        }
        if let names = result.removeValue(forKey: "spaceNames.names") as? [String: Any] {
            result["spaceNames"] = names
        }
        if let hotkey = result.removeValue(forKey: "behavior.hotkey") {
            result["hotkey"] = hotkey
        }
        if let pinnedHotkey = result.removeValue(forKey: "behavior.pinnedHotkey") {
            result["pinnedHotkey"] = pinnedHotkey
        }
        if let hudPosition = result.removeValue(forKey: "behavior.hudPosition") {
            result["hudPosition"] = hudPosition
        }
        return result
    }

    private static func parseTOMLObject(_ text: String) -> [String: Any]? {
        var root: [String: Any] = [:]
        var tables: [String: [String: Any]] = [:]
        var currentTable: String?

        for rawLine in text.components(separatedBy: .newlines) {
            guard let uncommented = stripTOMLComment(rawLine) else { return nil }
            let line = uncommented.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[") {
                guard line.hasSuffix("]"), !line.hasPrefix("[[") else { return nil }
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return nil }
                currentTable = name
                if tables[name] == nil { tables[name] = [:] }
                continue
            }

            guard let equals = firstUnquotedEquals(in: line) else { return nil }
            let rawKey = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            guard let key = parseTOMLKey(rawKey), let value = parseTOMLValue(rawValue) else { return nil }
            if let currentTable {
                tables[currentTable, default: [:]][key] = value
            } else {
                root[key] = value
            }
        }

        for (name, table) in tables {
            root[name] = table
        }
        return root
    }

    private static func stripTOMLComment(_ line: String) -> String? {
        var quote: Character?
        var escaping = false
        for index in line.indices {
            let character = line[index]
            if let activeQuote = quote {
                if activeQuote == "\"", escaping {
                    escaping = false
                } else if activeQuote == "\"", character == "\\" {
                    escaping = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" {
                return String(line[..<index])
            }
        }
        return quote == nil ? line : nil
    }

    private static func firstUnquotedEquals(in line: String) -> String.Index? {
        var quote: Character?
        var escaping = false
        for index in line.indices {
            let character = line[index]
            if let activeQuote = quote {
                if activeQuote == "\"", escaping {
                    escaping = false
                } else if activeQuote == "\"", character == "\\" {
                    escaping = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "=" {
                return index
            }
        }
        return nil
    }

    private static func parseTOMLKey(_ raw: String) -> String? {
        if raw.hasPrefix("\""), raw.hasSuffix("\"") {
            return decodeTOMLString(raw)
        }
        if raw.hasPrefix("'"), raw.hasSuffix("'"), raw.count >= 2 {
            return String(raw.dropFirst().dropLast())
        }
        guard !raw.isEmpty, raw.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
            return nil
        }
        return raw
    }

    private static func parseTOMLValue(_ raw: String) -> Any? {
        if raw.hasPrefix("\""), raw.hasSuffix("\"") {
            return decodeTOMLString(raw)
        }
        if raw.hasPrefix("'"), raw.hasSuffix("'"), raw.count >= 2 {
            return String(raw.dropFirst().dropLast())
        }
        if raw == "true" { return true }
        if raw == "false" { return false }
        if let integer = Int(raw) { return integer }
        if let double = Double(raw), double.isFinite { return double }
        if raw.hasPrefix("["), raw.hasSuffix("]") {
            let body = String(raw.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if body.isEmpty { return [String]() }
            guard let items = splitTOMLArray(body) else { return nil }
            var strings: [String] = []
            for item in items {
                guard let value = parseTOMLValue(item) as? String else { return nil }
                strings.append(value)
            }
            return strings
        }
        return nil
    }

    private static func splitTOMLArray(_ body: String) -> [String]? {
        var items: [String] = []
        var start = body.startIndex
        var quote: Character?
        var escaping = false
        for index in body.indices {
            let character = body[index]
            if let activeQuote = quote {
                if activeQuote == "\"", escaping {
                    escaping = false
                } else if activeQuote == "\"", character == "\\" {
                    escaping = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "," {
                items.append(String(body[start..<index]).trimmingCharacters(in: .whitespaces))
                start = body.index(after: index)
            }
        }
        guard quote == nil else { return nil }
        items.append(String(body[start...]).trimmingCharacters(in: .whitespaces))
        return items.allSatisfy { !$0.isEmpty } ? items : nil
    }

    private static func decodeTOMLString(_ raw: String) -> String? {
        guard raw.count >= 2, raw.first == "\"", raw.last == "\"" else { return nil }
        let body = raw.dropFirst().dropLast()
        var result = ""
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            guard character == "\\" else {
                result.append(character)
                index = body.index(after: index)
                continue
            }
            index = body.index(after: index)
            guard index < body.endIndex else { return nil }
            switch body[index] {
            case "b": result.append("\u{08}")
            case "t": result.append("\t")
            case "n": result.append("\n")
            case "f": result.append("\u{0C}")
            case "r": result.append("\r")
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            case "u", "U":
                let digits = body[index] == "u" ? 4 : 8
                let start = body.index(after: index)
                guard let end = body.index(start, offsetBy: digits, limitedBy: body.endIndex),
                      let value = UInt32(body[start..<end], radix: 16),
                      let scalar = UnicodeScalar(value) else { return nil }
                result.unicodeScalars.append(scalar)
                index = end
                continue
            default: return nil
            }
            index = body.index(after: index)
        }
        return result
    }

    private static func cellStyle(from name: String) -> CellStyle? {
        switch name.lowercased() {
        case "rects": return .rects
        case "hybrid": return .hybrid
        case "icons": return .icons
        case "thumbnails": return .thumbnails
        case "simple": return .simple
        default: return nil
        }
    }

    private static func showMode(from name: String) -> ShowMode? {
        switch name.lowercased() {
        case "active": return .active
        case "all": return .all
        default: return nil
        }
    }

    private static func multiMonitorHUDMode(from name: String) -> MultiMonitorHUDMode? {
        switch name.lowercased() {
        case "separate": return .separate
        case "unified": return .unified
        default: return nil
        }
    }

    private static func hudVisibility(from name: String) -> SeparateHUDVisibility? {
        switch name.lowercased() {
        case "active": return .active
        case "all": return .all
        default: return nil
        }
    }

    private static func displayNavigationWrap(from name: String) -> DisplayNavigationWrap? {
        switch name.lowercased() {
        case "within": return .within
        case "between": return .between
        default: return nil
        }
    }

    private static func themeMode(from name: String) -> ThemeMode? {
        switch name.lowercased() {
        case "light": return .light
        case "dark": return .dark
        case "auto": return .auto
        default: return nil
        }
    }

    private static func updateMode(from name: String) -> UpdateMode? {
        switch name.lowercased() {
        case "auto": return .auto
        case "notify": return .notify
        case "off": return .off
        default: return nil
        }
    }

    private static func menuBarDisplayMode(from name: String) -> MenuBarDisplayMode? {
        MenuBarDisplayMode(rawValue: name.lowercased())
    }

    private static func mediaKey(from name: String?) -> MediaKey? {
        guard let name else { return nil }
        return MediaKey(rawValue: name.lowercased())
    }

    private static func backupConfig(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let backupPath = path + ".bak"
        try? FileManager.default.removeItem(atPath: backupPath)
        try? FileManager.default.copyItem(atPath: path, toPath: backupPath)
        if !silentMode { NSLog("spacemap/Config: backed up config to \(backupPath)") }
    }

    private static func createDefaultConfigFile(at path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        backupConfig(path)
        let content = tomlConfigString(from: .default, includeHeaderComments: true)
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            if !silentMode { print("spacemap: default config created at \(path)") }
        } catch {
            print("spacemap: failed to create default config at \(path): \(error)")
        }
    }

    public static func saveConfig(_ config: GridConfig) {
        saveConfig(config, to: configPath)
    }

    public static func saveConfig(_ config: GridConfig, to path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        backupConfig(path)
        let content = tomlConfigString(from: config, includeHeaderComments: true)
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            if !silentMode { print("spacemap: config saved to \(path)") }
        } catch {
            print("spacemap: failed to save config to \(path): \(error)")
        }
    }

    private static func tomlConfigString(from config: GridConfig, includeHeaderComments: Bool) -> String {
        var lines: [String] = []
        if includeHeaderComments {
            lines += [
                "# Spacemap config",
                ""
            ]
        }

        lines += [
            "[grid]",
            "cols = \(config.cols)",
            "rows = \(config.rows)",
            "cellStyle = \(tomlString(cellStyleName(config.cellStyle)))",
            "showMode = \(tomlString(config.showMode.rawValue))",
            "multiMonitorHUDMode = \(tomlString(config.multiMonitorHUDMode.rawValue))",
            "unifiedHUDVisibility = \(tomlString(config.unifiedHUDVisibility.rawValue))",
            "separateHUDVisibility = \(tomlString(config.separateHUDVisibility.rawValue))",
            "maxSpaces = \(config.maxSpaces)",
            "showSpaceNumbers = \(config.showSpaceNumbers)",
            "showIconStrip = \(config.showIconStrip)",
            "showMultiAppIcons = \(config.showMultiAppIcons)",
            "",
            "[spaceNames]",
            "showSpaceNames = \(config.showSpaceNames)",
            "",
            "[spaceNames.names]"
        ]
        for key in config.spaceNames.keys.sorted() {
            lines.append("\(tomlString(String(key))) = \(tomlString(config.spaceNames[key]!))")
        }

        lines += [
            "",
            "[appearance]",
            "theme = \(tomlString(config.theme))",
            "mode = \(tomlString(config.mode.rawValue))",
            "backgroundAlpha = \(config.backgroundAlpha)",
            "iconScale = \(config.iconScale)",
            "uiScale = \(config.uiScale)",
            "",
            "[behavior]",
            "autoHideTimeout = \(config.autoHideTimeout)",
            "displayNavigationWrap = \(tomlString(config.displayNavigationWrap.rawValue))",
            "useVimKeys = \(config.useVimKeys)",
            "useArrowKeys = \(config.useArrowKeys)",
            "customHUDX = \(config.customHUDX)",
            "customHUDY = \(config.customHUDY)",
            "focusSpaceOnWindowDrop = \(tomlString(config.focusSpaceOnWindowDrop.rawValue))",
            "focusSpaceOnWindowDropModifier = \(tomlString(config.focusSpaceOnWindowDropModifier.rawValue))",
            "showHUDOnSpaceChange = \(config.showHUDOnSpaceChange)",
            "hideMenuBarIcon = \(config.hideMenuBarIcon)",
            "menuBarDisplayMode = \(tomlString(config.menuBarDisplayMode.rawValue))",
            "menuBarNearbyCount = \(config.menuBarNearbyCount)",
            "updateMode = \(tomlString(config.updateMode.rawValue))"
        ]
        appendHotkey(config.hotkey, section: "behavior.hotkey", to: &lines)
        appendHotkey(config.pinnedHotkey, section: "behavior.pinnedHotkey", to: &lines)

        lines += ["", "[behavior.hudPosition]"]
        switch config.hudPosition {
        case .center: lines.append("kind = \"center\"")
        case .top: lines.append("kind = \"top\"")
        case .bottom: lines.append("kind = \"bottom\"")
        case .custom(let x, let y):
            lines += ["kind = \"custom\"", "x = \(x)", "y = \(y)"]
        }

        lines += [
            "",
            "[advanced]",
            "socketHealthInterval = \(config.socketHealthInterval)",
            "showExtraWindows = \(config.showExtraWindows)"
        ]
        return lines.joined(separator: "\n") + "\n"
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

    private static func tomlString(_ value: String) -> String {
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

    internal static func cellStyleName(_ style: CellStyle) -> String {
        switch style {
        case .rects: return "rects"
        case .hybrid: return "hybrid"
        case .icons: return "icons"
        case .thumbnails: return "thumbnails"
        case .simple: return "simple"
        }
    }

}
