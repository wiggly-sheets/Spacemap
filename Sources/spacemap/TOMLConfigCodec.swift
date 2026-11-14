import Foundation
import CoreGraphics

enum TOMLParserError: LocalizedError {
    case parseFailure(reason: String)

    var errorDescription: String? {
        switch self {
        case .parseFailure(let reason):
            return "TOML parse failure: \(reason)"
        }
    }
}

enum TOMLConfigCodec {
    static func parse(_ data: String) throws -> ConfigValues {
        guard let object = TOMLDocumentParser.parse(data) else {
            throw TOMLParserError.parseFailure(reason: "malformed TOML")
        }
        return TOMLConfigDecoder.decode(TOMLConfigDecoder.normalize(object))
    }
}

typealias TOMLParser = TOMLConfigCodec

enum TOMLDocumentParser {
    static func parse(_ text: String) -> [String: Any]? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }

        var root: [String: Any] = [:]
        var tables: [String: [String: Any]] = [:]
        var currentTable: String?

        let lines = splitPhysicalLines(text)
        var index = 0
        while index < lines.count {
            let rawLine = lines[index]
            index += 1
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
            var rawValue = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            // Arrays may span lines. Keep folding continuation lines until the
            // brackets balance so a hand-wrapped `modifiers = [ ... ]` is not
            // treated as a fatal parse error.
            if rawValue.hasPrefix("[") {
                var depth = bracketDepth(rawValue)
                while depth > 0, index < lines.count {
                    guard let continuation = stripTOMLComment(lines[index]) else { return nil }
                    index += 1
                    let trimmed = continuation.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    rawValue += " " + trimmed
                    depth = bracketDepth(rawValue)
                }
                guard depth == 0 else { return nil }
            }
            guard let keyPath = parseTOMLKeyPath(rawKey),
                  let value = parseTOMLValue(rawValue) else { return nil }
            insert(value, keyPath: keyPath, currentTable: currentTable, root: &root, tables: &tables)
        }

        for (name, table) in tables {
            root[name] = table
        }
        return root
    }

    /// Split on line terminators (`\n`, `\r\n`, lone `\r`) but not on
    /// U+2028/U+2029: those are legal inside a quoted string and must reach
    /// the sanitizer instead of corrupting the document.
    private static func splitPhysicalLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r" }
            .map { String($0) }
    }

    /// Bracket balance outside quoted strings. A non-zero result means the
    /// array value continues onto the next line.
    private static func bracketDepth(_ raw: String) -> Int {
        var depth = 0
        var quote: Character?
        var escaping = false
        for character in raw {
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
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
            }
        }
        return depth
    }

    /// Dotted keys (`grid.cols = 8`) resolve to the same table shape as a
    /// `[grid]` section, so the decoder sees one representation.
    private static func insert(
        _ value: Any,
        keyPath: [String],
        currentTable: String?,
        root: inout [String: Any],
        tables: inout [String: [String: Any]]
    ) {
        guard let key = keyPath.last else { return }
        let prefix = Array(keyPath.dropLast())
        if let currentTable {
            if prefix.isEmpty {
                tables[currentTable, default: [:]][key] = value
            } else {
                tables[([currentTable] + prefix).joined(separator: "."), default: [:]][key] = value
            }
        } else if prefix.isEmpty {
            root[key] = value
        } else {
            tables[prefix.joined(separator: "."), default: [:]][key] = value
        }
    }
    /// Strips full-line and trailing `#` comments; `#` inside quotes is
    /// literal. Nil means unbalanced quote — fail closed, whole file rejected.
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

    /// Split a dotted key into its unquoted segments: `grid.cols`,
    /// `spaceNames.names."1"`. A quoted segment may contain a literal dot.
    private static func parseTOMLKeyPath(_ raw: String) -> [String]? {
        var parts: [String] = []
        var start = raw.startIndex
        var quote: Character?
        var escaping = false
        for index in raw.indices {
            let character = raw[index]
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
            } else if character == "." {
                parts.append(String(raw[start..<index]).trimmingCharacters(in: .whitespaces))
                start = raw.index(after: index)
            }
        }
        guard quote == nil else { return nil }
        parts.append(String(raw[start...]).trimmingCharacters(in: .whitespaces))
        var keys: [String] = []
        for part in parts {
            guard let key = parseTOMLKey(part) else { return nil }
            keys.append(key)
        }
        return keys.isEmpty ? nil : keys
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
        if let integer = parseTOMLInteger(raw) { return integer }
        if let double = Double(raw.replacingOccurrences(of: "_", with: "")), double.isFinite {
            return double
        }
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
        if raw.hasPrefix("{"), raw.hasSuffix("}") {
            let body = String(raw.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if body.isEmpty { return [String: Any]() }
            guard let items = splitTOMLArray(body) else { return nil }
            var table: [String: Any] = [:]
            for item in items {
                guard let equals = firstUnquotedEquals(in: item) else { return nil }
                let rawKey = String(item[..<equals]).trimmingCharacters(in: .whitespaces)
                let rawValue = String(item[item.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
                guard let keyPath = parseTOMLKeyPath(rawKey), keyPath.count == 1,
                      let value = parseTOMLValue(rawValue) else { return nil }
                table[keyPath[0]] = value
            }
            return table
        }
        return nil
    }

    /// TOML integers: optional sign, `_` separators, and `0x`/`0o`/`0b`
    /// prefixes. `Int(raw)` alone rejects every one of those beyond plain
    /// decimal.
    private static func parseTOMLInteger(_ raw: String) -> Int? {
        let compact = raw.replacingOccurrences(of: "_", with: "")
        guard !compact.isEmpty else { return nil }
        var body = compact
        var negative = false
        if body.hasPrefix("+") {
            body.removeFirst()
        } else if body.hasPrefix("-") {
            negative = true
            body.removeFirst()
        }
        let radix: Int
        if body.hasPrefix("0x") || body.hasPrefix("0X") {
            radix = 16
            body.removeFirst(2)
        } else if body.hasPrefix("0o") || body.hasPrefix("0O") {
            radix = 8
            body.removeFirst(2)
        } else if body.hasPrefix("0b") || body.hasPrefix("0B") {
            radix = 2
            body.removeFirst(2)
        } else {
            radix = 10
        }
        guard !body.isEmpty, let magnitude = Int(body, radix: radix) else { return nil }
        return negative ? -magnitude : magnitude
    }

    private static func splitTOMLArray(_ body: String) -> [String]? {
        var items: [String] = []
        var start = body.startIndex
        var quote: Character?
        var escaping = false
        var depth = 0
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
            } else if character == "[" || character == "{" {
                depth += 1
            } else if character == "]" || character == "}" {
                depth -= 1
            } else if character == ",", depth == 0 {
                items.append(String(body[start..<index]).trimmingCharacters(in: .whitespaces))
                start = body.index(after: index)
            }
        }
        guard quote == nil else { return nil }
        items.append(String(body[start...]).trimmingCharacters(in: .whitespaces))
        // TOML allows a trailing comma; the empty tail is not an item.
        if items.last?.isEmpty == true {
            items.removeLast()
        }
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
}

enum TOMLConfigDecoder {
    static func normalize(_ object: [String: Any]) -> [String: Any] {
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
            "showSpaceNumbers", "showSpaceLayout", "showIconStrip", "showMultiAppIcons",
            "showThumbnailWallpaper"
        ])
        flatten("appearance", keys: [
            "theme", "mode", "backgroundAlpha", "hudShadow", "hudCornerRadius", "iconScale", "uiScale",
            "backgroundStyle", "glassStyle",
            "glassClearVariant", "glassRegularVariant", "glassTintedVariant", "glassTintedMaterial",
            "glassClearOpacity", "glassRegularOpacity", "glassTintedOpacity",
            "solidOpacity", "matchBackgroundOpacity",
            "spacesMatchBackground", "spacesBackgroundStyle", "spacesGlassStyle",
            "spacesGlassClearVariant", "spacesGlassRegularVariant", "spacesGlassTintedVariant",
            "spacesGlassTintedMaterial", "spacesOpacity", "spacesCornerRadius"
        ])
        // Legacy fallback: pre-[advanced] files keep showExtraWindows under
        // [behavior]. Capture before flatten drops the section; [advanced]
        // and top level win when present.
        let legacyShowExtra = (result["behavior"] as? [String: Any])?["showExtraWindows"]
        flatten("behavior", keys: [
            "autoHideTimeout", "displayNavigationWrap", "useVimKeys", "useArrowKeys",
            "useExtendedKeys", "customHUDX", "customHUDY", "focusSpaceOnWindowDrop", "showHUDOnSpaceChange", "hudAnimationsEnabled", "hudAnimationStyle", "showBSPLayoutBadge", "showStackLayoutBadge", "showFloatLayoutBadge", "showHUDInteractionFeedback",
            "focusSpaceOnWindowDropModifier", "presence", "hideMenuBarIcon", "showThumbnailWallpaper",
            "menuBarDisplayMode", "menuBarNearbyCount", "jumpToSpaceEnabled", "updateMode",
            // Inline `hotkey = { ... }` / `hudPosition = { ... }` under
            // [behavior] must survive flatten just like the dotted form.
            "hotkey", "pinnedHotkey", "glyphStripHotkey", "hudPosition"
        ])
        flatten("advanced", keys: ["socketHealthInterval", "showExtraWindows", "refuseUntrustedYabai"])
        if result["showExtraWindows"] == nil, let legacyShowExtra {
            result["showExtraWindows"] = legacyShowExtra
        }

        // `[spaceNames]` has held three shapes over time: a names map, the
        // showSpaceNames toggle, and a nested `names` map. Merge them instead
        // of dropping direct entries; anything non-numeric still reaches the
        // decoder and flags repair.
        var directSpaceNames: [String: Any] = [:]
        if let section = result.removeValue(forKey: "spaceNames") as? [String: Any] {
            for (key, value) in section {
                if key == "showSpaceNames" {
                    result["showSpaceNames"] = value
                } else if key == "names", let nested = value as? [String: Any] {
                    directSpaceNames.merge(nested) { _, new in new }
                } else {
                    directSpaceNames[key] = value
                }
            }
        }
        if let nested = result.removeValue(forKey: "spaceNames.names") as? [String: Any] {
            directSpaceNames.merge(nested) { _, new in new }
        }
        if !directSpaceNames.isEmpty {
            result["spaceNames"] = directSpaceNames
        }
        if let hotkey = result.removeValue(forKey: "behavior.hotkey") {
            result["hotkey"] = hotkey
        }
        if let pinnedHotkey = result.removeValue(forKey: "behavior.pinnedHotkey") {
            result["pinnedHotkey"] = pinnedHotkey
        }
        if let glyphStripHotkey = result.removeValue(forKey: "behavior.glyphStripHotkey") {
            result["glyphStripHotkey"] = glyphStripHotkey
        }
        if let hudPosition = result.removeValue(forKey: "behavior.hudPosition") {
            result["hudPosition"] = hudPosition
        }
        return result
    }


    static func decode(_ object: [String: Any]) -> ConfigValues {
        var values = ConfigValues()

        func value<T>(_ key: String) -> T? {
            object[key] as? T
        }

        func positiveInt(_ key: String) -> Int? {
            if let intValue = object[key] as? Int, intValue > 0 { return intValue }
            return nil
        }

        func nonNegativeInt(_ key: String) -> Int? {
            if let intValue = object[key] as? Int, intValue >= 0 { return intValue }
            return nil
        }

        func rangedDouble(_ key: String) -> Double? {
            if let doubleValue = object[key] as? Double, (0...1).contains(doubleValue) { return doubleValue }
            if let intValue = object[key] as? Int, (0...1).contains(Double(intValue)) { return Double(intValue) }
            return nil
        }

        func variant(_ key: String) -> Int? {
            guard let value = object[key] as? Int, (0...21).contains(value) else { return nil }
            return value
        }

        func double(_ key: String) -> Double? {
            if let result = object[key] as? Double { return result }
            if let result = object[key] as? Int { return Double(result) }
            return nil
        }

        values.cols = positiveInt("cols")
        values.rows = positiveInt("rows")
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
        values.maxSpaces = positiveInt("maxSpaces")
        values.showSpaceNumbers = value("showSpaceNumbers")
        values.showSpaceLayout = value("showSpaceLayout")
        values.showIconStrip = value("showIconStrip")
        values.showMultiAppIcons = value("showMultiAppIcons")
        if let name: String = value("backgroundStyle") {
            values.backgroundStyle = parsedEnum(from: name)
        }
        if let name: String = value("glassStyle") {
            values.glassStyle = parsedEnum(from: name)
        }
        values.glassClearVariant = variant("glassClearVariant")
        values.glassRegularVariant = variant("glassRegularVariant")
        values.glassTintedVariant = variant("glassTintedVariant")
        if let name: String = value("glassTintedMaterial") {
            values.glassTintedMaterial = parsedEnum(from: name)
        }
        values.glassClearOpacity = rangedDouble("glassClearOpacity")
        values.glassRegularOpacity = rangedDouble("glassRegularOpacity")
        values.glassTintedOpacity = rangedDouble("glassTintedOpacity")
        values.solidOpacity = rangedDouble("solidOpacity")
        values.matchBackgroundOpacity = value("matchBackgroundOpacity")
        values.spacesMatchBackground = value("spacesMatchBackground")
        if let name: String = value("spacesBackgroundStyle") {
            values.spacesBackgroundStyle = parsedEnum(from: name)
        }
        if let name: String = value("spacesGlassStyle") {
            values.spacesGlassStyle = parsedEnum(from: name)
        }
        values.spacesGlassClearVariant = variant("spacesGlassClearVariant")
        values.spacesGlassRegularVariant = variant("spacesGlassRegularVariant")
        values.spacesGlassTintedVariant = variant("spacesGlassTintedVariant")
        if let name: String = value("spacesGlassTintedMaterial") {
            values.spacesGlassTintedMaterial = parsedEnum(from: name)
        }
        values.spacesOpacity = rangedDouble("spacesOpacity")
        values.spacesCornerRadius = double("spacesCornerRadius")

        if let rawSpaceNames = object["spaceNames"] as? [String: Any] {
            var spaceNames: [Int: String] = [:]
            for (key, rawName) in rawSpaceNames {
                guard let index = Int(key), index > 0, let name = rawName as? String else {
                    values.hasInvalidSpaceNames = true
                    continue
                }
                spaceNames[index] = name
            }
            values.spaceNames = spaceNames
        }
        if let showSpaceNames: Bool = value("showSpaceNames") {
            values.showSpaceNames = showSpaceNames
        }

        values.theme = validatedThemeName(value("theme"))
        if let name: String = value("mode") {
            values.mode = themeMode(from: name)
        }
        values.backgroundAlpha = rangedDouble("backgroundAlpha")
        values.hudShadow = value("hudShadow")
        values.hudCornerRadius = double("hudCornerRadius")
        values.iconScale = rangedDouble("iconScale")
        values.uiScale = rangedDouble("uiScale")

        values.autoHideTimeout = nonNegativeInt("autoHideTimeout")
        if let name: String = value("displayNavigationWrap") {
            values.displayNavigationWrap = displayNavigationWrap(from: name)
        }
        values.useVimKeys = value("useVimKeys")
        values.useArrowKeys = value("useArrowKeys")
        values.useExtendedKeys = value("useExtendedKeys")
        values.jumpToSpaceEnabled = value("jumpToSpaceEnabled")
        values.customHUDX = rangedDouble("customHUDX")
        values.customHUDY = rangedDouble("customHUDY")
        if let name: String = value("focusSpaceOnWindowDrop") {
            values.focusSpaceOnWindowDrop = parsedEnum(from: name)
        }
        if let name: String = value("focusSpaceOnWindowDropModifier") {
            values.focusSpaceOnWindowDropModifier = parsedEnum(from: name)
        }
        values.showHUDOnSpaceChange = value("showHUDOnSpaceChange")
        values.showBSPLayoutBadge = value("showBSPLayoutBadge")
        values.showStackLayoutBadge = value("showStackLayoutBadge")
        values.showFloatLayoutBadge = value("showFloatLayoutBadge")
        values.showHUDInteractionFeedback = value("showHUDInteractionFeedback")
        values.showThumbnailWallpaper = value("showThumbnailWallpaper")
        values.hudAnimationsEnabled = value("hudAnimationsEnabled")
        if let name: String = value("hudAnimationStyle") {
            values.hudAnimationStyle = parsedEnum(from: name)
        }
        if let name: String = value("presence") {
            values.presence = parsedEnum(from: name)
        } else if let hide: Bool = value("hideMenuBarIcon") {
            // Legacy: hidden menu bar icon meant a menu-bar-less app.
            values.presence = hide ? AppPresence.none : .menuBar
        } else if let hide: Int = value("hideMenuBarIcon") {
            values.presence = hide == 0 ? .menuBar : AppPresence.none
        }
        values.glyphStrip = glyphStripConfig(from: object)
        if let name: String = value("menuBarDisplayMode") {
            values.menuBarDisplayMode = parsedEnum(from: name)
        }
        values.menuBarNearbyCount = positiveInt("menuBarNearbyCount")
        if let name: String = value("updateMode") {
            values.updateMode = updateMode(from: name)
        }
        values.appFont = appFontConfig(from: object)

        if let table = object["hotkey"] as? [String: Any] {
            values.hotkey = parseHotkeyTable(table)
        }
        if let table = object["pinnedHotkey"] as? [String: Any] {
            values.pinnedHotkey = parseHotkeyTable(table)
        }
        if let table = object["glyphStripHotkey"] as? [String: Any] {
            values.glyphStripHotkey = parseHotkeyTable(table)
        }

        if let table = object["hudPosition"] as? [String: Any],
           let kind = table["kind"] as? String {
            switch kind.lowercased() {
            case "center": values.hudPosition = .center
            case "top": values.hudPosition = .top
            case "bottom": values.hudPosition = .bottom
            case "custom":
                // Both coordinates required, numeric, in range. No invented
                // 0.5 fallback: anything else stays nil so repair heals it.
                if let x = number(table["x"]), let y = number(table["y"]),
                   (0...1).contains(x), (0...1).contains(y) {
                    values.hudPosition = .custom(x: x, y: y)
                }
            default:
                break
            }
        }

        values.socketHealthInterval = positiveInt("socketHealthInterval")
        values.showExtraWindows = value("showExtraWindows")
        values.refuseUntrustedYabai = value("refuseUntrustedYabai")

        // Indexed-dotted schema written by ConfigLoader (`[spaceNameProfiles]`
        // + `[spaceNameProfiles.N]` + `[spaceNameProfiles.N.names]`).
        var index = 0
        var indexedProfiles: [SpaceNameProfile] = []
        while let profileDict = object["spaceNameProfiles.\(index)"] as? [String: Any] {
            var profile = SpaceNameProfile.default
            if let name = profileDict["name"] as? String {
                profile.name = name
            }
            // `[spaceNameProfiles.N.names]` is the writer's form; accept the
            // inline `names = { ... }` form under the profile table too.
            if let names = (object["spaceNameProfiles.\(index).names"] as? [String: Any])
                ?? (profileDict["names"] as? [String: Any]) {
                var spaceNames: [Int: String] = [:]
                for (key, rawName) in names {
                    guard let spaceIndex = Int(key), spaceIndex > 0,
                          let name = rawName as? String else { continue }
                    spaceNames[spaceIndex] = name
                }
                profile.spaceNames = spaceNames
            }
            indexedProfiles.append(profile)
            index += 1
        }
        if !indexedProfiles.isEmpty {
            values.spaceNameProfiles = indexedProfiles
        }
        if let meta = object["spaceNameProfiles"] as? [String: Any],
           let activeIndex = meta["activeIndex"] as? Int {
            values.activeSpaceNameProfileIndex = activeIndex
        }

        return values
    }


    /// Unknown theme names stay nil so `toGridConfig` flags repair and heals
    /// the file, instead of silently falling back at every use site. Lookup
    /// mirrors `ThemeManager.named`: normalized (spaces/hyphens/underscores)
    /// first, then compact (`tokyonight` -> `tokyo night`). The user's
    /// spelling is preserved so a save does not rewrite it.
    private static func validatedThemeName(_ name: String?) -> String? {
        guard let name else { return nil }
        let names = ThemeManager.shared.allNames()
        let normalized = ThemeManager.normalizedName(name)
        if names.contains(normalized) { return name }
        let compact = ThemeManager.compactName(name)
        if names.contains(where: { ThemeManager.compactName($0) == compact }) { return name }
        return nil
    }

    private static func parseHotkeyTable(_ table: [String: Any]) -> HotkeyConfig? {
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
    /// `[glyphStrip]` table. Unknown enum names fall back to that key's default
    /// instead of failing the whole load, matching how the other enum keys behave.
    /// A bare `glyphStrip = true` is the legacy on/off form and maps to `enabled`.
    private static func glyphStripConfig(from object: [String: Any]) -> GlyphStripConfig? {
        if let enabled = object["glyphStrip"] as? Bool {
            var config = GlyphStripConfig.default
            config.enabled = enabled
            return config
        }
        guard let table = object["glyphStrip"] as? [String: Any] else { return nil }
        var config = GlyphStripConfig.default
        if let value = table["enabled"] as? Bool { config.enabled = value }
        if let value = table["hideInFullscreen"] as? Bool { config.hideInFullscreen = value }
        if let value = table["showSpaceNumbers"] as? Bool { config.showSpaceNumbers = value }
        if let value = table["showLayoutSuffix"] as? Bool { config.showLayoutSuffix = value }
        if let value = table["showAppIcons"] as? Bool { config.showAppIcons = value }
        if let name = table["iconSource"] as? String,
           let source = GlyphStripIconSource.iconSource(from: name) { config.iconSource = source }
        if let value = table["dedupeAppsPerSpace"] as? Bool { config.dedupeAppsPerSpace = value }
        if let value = number(table["maxIconsPerSpace"]) {
            config.maxIconsPerSpace = clampedInt(value, rounding: .towardZero)
        }
        if let value = number(table["iconSize"]) { config.iconSize = value }
        if let value = number(table["indexSize"]) { config.indexSize = value }
        if let value = table["highlightCurrentSpace"] as? Bool { config.highlightCurrentSpace = value }
        if let name = table["backgroundMaterial"] as? String {
            config.backgroundMaterial = parsedEnum(from: name) ?? GlyphStripConfig.default.backgroundMaterial
        }
        if let name = table["shape"] as? String {
            config.shape = parsedEnum(from: name) ?? GlyphStripConfig.default.shape
        }
        if let name = table["glassStyle"] as? String {
            config.glassStyle = parsedEnum(from: name) ?? GlyphStripConfig.default.glassStyle
        } else {
            // Older files only had a continuous amount plus a tint toggle.
            // Map them onto the closest of the three native positions.
            let legacyTint = table["useThemeTint"] as? Bool
            let legacyAmount = number(table["glassAmount"])
            if legacyTint == false {
                config.glassStyle = .regular
            } else if let legacyAmount {
                config.glassStyle = legacyAmount <= 0.02 ? .clear : .tinted
            } else if legacyTint == true {
                config.glassStyle = .tinted
            }
        }
        if let value = variant(table["glassClearVariant"]) { config.glassClearVariant = value }
        if let value = variant(table["glassRegularVariant"]) { config.glassRegularVariant = value }
        if let value = variant(table["glassTintedVariant"]) { config.glassTintedVariant = value }
        if let name = table["glassTintedMaterial"] as? String {
            config.glassTintedMaterial = parsedEnum(from: name) ?? GlyphStripConfig.default.glassTintedMaterial
        }
        if let value = number(table["backgroundOpacity"]) { config.backgroundOpacity = value }
        // New per-style keys inherit the shared value from older configs. Clear
        // used to be painted at 15% of its value, so inherit that share to keep
        // existing strips looking the same.
        let sharedOpacity = config.backgroundOpacity
        config.glassClearOpacity = number(table["glassClearOpacity"]) ?? sharedOpacity * 0.15
        config.glassRegularOpacity = number(table["glassRegularOpacity"]) ?? sharedOpacity
        config.glassTintedOpacity = number(table["glassTintedOpacity"]) ?? sharedOpacity
        config.solidOpacity = number(table["solidOpacity"]) ?? sharedOpacity
        if let value = table["matchBackgroundOpacity"] as? Bool { config.matchBackgroundOpacity = value }
        if let value = table["matchHUDAppearance"] as? Bool { config.matchHUDAppearance = value }
        if let value = number(table["cornerRadius"]) { config.cornerRadius = value }
        if let value = number(table["margin"]) { config.margin = value }
        if let value = number(table["iconSpacing"]) { config.iconSpacing = value }
        if let value = number(table["indexPadding"]) { config.indexPadding = value }
        if let value = number(table["yOffset"]) { config.yOffset = value }
        if let value = number(table["hoverPadding"]) { config.hoverPadding = value }
        if let value = number(table["hoverCornerRadius"]) { config.hoverCornerRadius = value }
        if let value = table["showDisplaySeparators"] as? Bool { config.showDisplaySeparators = value }
        if let value = table["showAddSpaceButton"] as? Bool { config.showAddSpaceButton = value }
        if let value = table["showPlaceholders"] as? Bool { config.showPlaceholders = value }
        if let name = table["leftClickAction"] as? String {
            config.leftClickAction = parsedEnum(from: name) ?? GlyphStripConfig.default.leftClickAction
        }
        if let name = table["rightClickAction"] as? String {
            config.rightClickAction = parsedEnum(from: name) ?? GlyphStripConfig.default.rightClickAction
        }
        if let name = table["middleClickAction"] as? String {
            config.middleClickAction = parsedEnum(from: name) ?? GlyphStripConfig.default.middleClickAction
        }
        if let value = table["lockPosition"] as? Bool { config.lockPosition = value }
        if let name = table["position"] as? String {
            config.position = parsedEnum(from: name) ?? GlyphStripConfig.default.position
        }
        if let name = table["orientation"] as? String {
            config.orientation = parsedEnum(from: name) ?? GlyphStripConfig.default.orientation
        }
        if let name = table["verticalLayout"] as? String {
            config.verticalLayout = parsedEnum(from: name) ?? GlyphStripConfig.default.verticalLayout
        }
        // Int storage (see GlyphStrip.customOffsets): round, don't truncate,
        // so 12.7 lands on 13 rather than 12. Full-Double storage needs
        // Glyph* call-site changes, out of scope for this pass.
        if let value = number(table["xOffset"]) {
            config.xOffset = clampedInt(value, rounding: .toNearestOrAwayFromZero)
        }
        if let value = table["borderEnabled"] as? Bool { config.borderEnabled = value }
        if let value = table["theme"] as? String { config.theme = value }
        return config
    }

    /// Case-insensitive enum lookup: exact match, then lowercased, else nil.
    /// Callers holding struct defaults apply `?? default`; callers holding
    /// optionals assign directly so unknown names stay nil and flag repair.
    private static func parsedEnum<E: RawRepresentable>(_ type: E.Type = E.self, from name: String) -> E?
    where E.RawValue == String {
        E(rawValue: name) ?? E(rawValue: name.lowercased())
    }

    /// Raw `_variant` value, only when it is in the safe 0...21 range.
    private static func variant(_ raw: Any?) -> Int? {
        guard let value = number(raw), value.rounded() == value, (0...21).contains(Int(value)) else { return nil }
        return Int(value)
    }

    private static func number(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        return nil
    }

    /// `Int(Double)` traps outside `Int`'s range (e.g. `1e300`). Saturate
    /// instead; `toGridConfig` still clamps to the documented range and flags
    /// repair, so a wild file heals on the next save rather than killing the app.
    private static func clampedInt(_ value: Double, rounding rule: FloatingPointRoundingRule) -> Int {
        guard value.isFinite else { return 0 }
        let rounded = value.rounded(rule)
        if rounded >= Double(Int.max) { return Int.max }
        if rounded <= Double(Int.min) { return Int.min }
        return Int(rounded)
    }

    /// `[appFont]` table.
    private static func appFontConfig(from object: [String: Any]) -> AppFontConfig? {
        guard let table = object["appFont"] as? [String: Any] else { return nil }
        var config = AppFontConfig.default
        if let name = table["updateMode"] as? String {
            config.updateMode = parsedEnum(from: name) ?? .manual
        }
        if let value = table["installedVersion"] as? String {
            config.installedVersion = value
        }
        if let value = table["lastCheck"] as? Int, value >= 0 {
            config.lastCheck = value
        }
        return config
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
}
