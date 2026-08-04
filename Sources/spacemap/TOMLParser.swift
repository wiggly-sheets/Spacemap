import Foundation
import CoreGraphics

enum TOMLParser: TOMLParserProtocol {

    static func parse(_ data: String) -> ConfigValues {
        guard let parsedObject = parseTOMLObject(data) else {
            return ConfigValues()
        }
        let object = normalizedTOMLObject(parsedObject)
        return decodedTOMLConfig(object)
    }

    // MARK: - TOML Parsing

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

    // MARK: - Normalization

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

    // MARK: - Decoding

    private static func decodedTOMLConfig(_ object: [String: Any]) -> ConfigValues {
        var values = ConfigValues()

        func value<T>(_ key: String) -> T? {
            object[key] as? T
        }

        func double(_ key: String) -> Double? {
            if let result = object[key] as? Double { return result }
            if let result = object[key] as? Int { return Double(result) }
            return nil
        }

        // Grid section
        values.cols = value("cols")
        values.rows = value("rows")
        if let name: String = value("cellStyle") {
            values.cellStyle = cellStyle(from: name)
        }
        if let name: String = value("showMode") {
            values.showMode = showMode(from: name)
        }
        if let name: String = value("multiMonitorHUDMode") {
            values.multiMonitorHUDMode = multiMonitorHUDMode(from: name)
        }
        if let name: String = value("unifiedHUDVisibility") {
            values.unifiedHUDVisibility = hudVisibility(from: name)
        }
        if let name: String = value("separateHUDVisibility") {
            values.separateHUDVisibility = hudVisibility(from: name)
        }
        values.maxSpaces = value("maxSpaces")
        values.showSpaceNumbers = value("showSpaceNumbers")
        values.showIconStrip = value("showIconStrip")
        values.showMultiAppIcons = value("showMultiAppIcons")

        // Space names
        if let rawSpaceNames = object["spaceNames"] as? [String: Any] {
            var spaceNames: [Int: String] = [:]
            for (key, rawName) in rawSpaceNames {
                guard let index = Int(key), let name = rawName as? String else { continue }
                spaceNames[index] = name
            }
            values.spaceNames = spaceNames.isEmpty ? nil : spaceNames
        }
        if let showSpaceNames: Bool = value("showSpaceNames") {
            values.showSpaceNames = showSpaceNames
        }

        // Appearance section
        values.theme = value("theme")
        if let name: String = value("mode") {
            values.mode = themeMode(from: name)
        }
        values.backgroundAlpha = double("backgroundAlpha")
        values.iconScale = double("iconScale")
        values.uiScale = double("uiScale")

        // Behavior section
        values.autoHideTimeout = value("autoHideTimeout")
        if let name: String = value("displayNavigationWrap") {
            values.displayNavigationWrap = displayNavigationWrap(from: name)
        }
        values.useVimKeys = value("useVimKeys")
        values.useArrowKeys = value("useArrowKeys")
        values.customHUDX = double("customHUDX")
        values.customHUDY = double("customHUDY")
        if let name: String = value("focusSpaceOnWindowDrop") {
            values.focusSpaceOnWindowDrop = WindowDropFocusMode(rawValue: name.lowercased())
        }
        if let name: String = value("focusSpaceOnWindowDropModifier") {
            values.focusSpaceOnWindowDropModifier = WindowDropFocusModifier(rawValue: name.lowercased())
        }
        values.showHUDOnSpaceChange = value("showHUDOnSpaceChange")
        values.hideMenuBarIcon = value("hideMenuBarIcon")
        if let name: String = value("menuBarDisplayMode") {
            values.menuBarDisplayMode = menuBarDisplayMode(from: name)
        }
        values.menuBarNearbyCount = value("menuBarNearbyCount")
        if let name: String = value("updateMode") {
            values.updateMode = updateMode(from: name)
        }

        // Hotkey — delegates to Hotkey module
        if let table = object["hotkey"] as? [String: Any] {
            values.hotkey = parseHotkeyTable(table)
        }
        if let table = object["pinnedHotkey"] as? [String: Any] {
            values.pinnedHotkey = parseHotkeyTable(table)
        }

        // HUD Position
        if let table = object["hudPosition"] as? [String: Any],
           let kind = table["kind"] as? String {
            switch kind.lowercased() {
            case "center": values.hudPosition = .center
            case "top": values.hudPosition = .top
            case "bottom": values.hudPosition = .bottom
            case "custom":
                let x = (table["x"] as? Double) ?? (table["x"] as? Int).map(Double.init) ?? 0.5
                let y = (table["y"] as? Double) ?? (table["y"] as? Int).map(Double.init) ?? 0.5
                if (0...1).contains(x), (0...1).contains(y) {
                    values.hudPosition = .custom(x: x, y: y)
                }
            default:
                break
            }
        }

        // Advanced section
        values.socketHealthInterval = value("socketHealthInterval")
        values.showExtraWindows = value("showExtraWindows")

        return values
    }

    // MARK: - Hotkey Parsing (delegates to Hotkey module)

    private static func parseHotkeyTable(_ table: [String: Any]) -> HotkeyConfig? {
        guard let kind = table["keyKind"] as? String,
              let modifierNames = table["modifiers"] as? [String] else {
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

    // MARK: - TOML Lexer Helpers

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

    // MARK: - Enum Resolution

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
}
