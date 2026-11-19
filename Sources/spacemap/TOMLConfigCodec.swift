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
    /// Decodes and repairs in one walk: the result is a complete config seeded
    /// from the defaults, plus whether the file needs a rewritten copy.
    static func parse(_ data: String) throws -> (config: SpacemapConfig, needsRepair: Bool) {
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

        // `showThumbnailWallpaper` is also flattened from [behavior] below: the
        // key is written there, older files may carry it under either section.
        flatten("grid", keys: ConfigSchema.flattenedKeys(in: "grid"))
        flatten("appearance", keys: ConfigSchema.flattenedKeys(in: "appearance"))
        // The explicit key covers the grid field the writer emits under
        // [behavior], which `flattenedKeys` files under [grid].
        flatten("behavior", keys: ConfigSchema.flattenedKeys(in: "behavior") + ["showThumbnailWallpaper"])
        flatten("advanced", keys: ConfigSchema.flattenedKeys(in: "advanced"))

        // `[spaceNames]` holds the showSpaceNames toggle; the names live in the
        // nested `names` table (written as `[spaceNames.names]`).
        var spaceNames: [String: Any] = [:]
        if let section = result.removeValue(forKey: "spaceNames") as? [String: Any] {
            if let show = section["showSpaceNames"] {
                result["showSpaceNames"] = show
            }
            if let nested = section["names"] as? [String: Any] {
                spaceNames.merge(nested) { _, new in new }
            }
        }
        if let nested = result.removeValue(forKey: "spaceNames.names") as? [String: Any] {
            spaceNames.merge(nested) { _, new in new }
        }
        if !spaceNames.isEmpty {
            result["spaceNames"] = spaceNames
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
        if let hotkey = result.removeValue(forKey: "behavior.hudMoveSpaceBackHotkey") {
            result["hudMoveSpaceBackHotkey"] = hotkey
        }
        if let hotkey = result.removeValue(forKey: "behavior.hudMoveSpaceForwardHotkey") {
            result["hudMoveSpaceForwardHotkey"] = hotkey
        }
        if let hotkey = result.removeValue(forKey: "behavior.hudNewSpaceHotkey") {
            result["hudNewSpaceHotkey"] = hotkey
        }
        if let hotkey = result.removeValue(forKey: "behavior.hudDeleteSpaceHotkey") {
            result["hudDeleteSpaceHotkey"] = hotkey
        }
        if let hotkey = result.removeValue(forKey: "behavior.hudCycleLayoutHotkey") {
            result["hudCycleLayoutHotkey"] = hotkey
        }
        if let hudPosition = result.removeValue(forKey: "behavior.hudPosition") {
            result["hudPosition"] = hudPosition
        }
        return result
    }


    static func decode(_ object: [String: Any]) -> (config: SpacemapConfig, needsRepair: Bool) {
        var config = SpacemapConfig.default
        var needsRepair = false

        for field in ConfigSchema.gridFields {
            field.apply(from: object, into: &config, needsRepair: &needsRepair)
        }
        for field in ConfigSchema.appearanceFields {
            field.apply(from: object, into: &config, needsRepair: &needsRepair)
        }
        for field in ConfigSchema.behaviorFields {
            field.apply(from: object, into: &config, needsRepair: &needsRepair)
        }
        for field in ConfigSchema.tableFields {
            field.apply(from: object, into: &config, needsRepair: &needsRepair)
        }
        for field in ConfigSchema.advancedFields {
            field.apply(from: object, into: &config, needsRepair: &needsRepair)
        }

        if let rawSpaceNames = object["spaceNames"] as? [String: Any] {
            var spaceNames: [Int: String] = [:]
            for (key, rawName) in rawSpaceNames {
                guard let index = Int(key), index > 0, let name = rawName as? String else {
                    needsRepair = true
                    continue
                }
                spaceNames[index] = name
            }
            config.spaceNames = spaceNames
        }
        if let showSpaceNames = object["showSpaceNames"] as? Bool {
            config.showSpaceNames = showSpaceNames
        } else {
            needsRepair = true
        }

        // Out-of-range strip numbers clamp in memory and flag a rewrite.
        if let strip = glyphStripConfig(from: object) {
            let clamped = strip.clamped()
            if clamped != strip { needsRepair = true }
            config.glyphStrip = clamped
        } else {
            needsRepair = true
        }
        if let font = appFontConfig(from: object) {
            config.appFont = font
        } else {
            needsRepair = true
        }

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
            config.spaceNameProfiles = indexedProfiles
        }
        if let meta = object["spaceNameProfiles"] as? [String: Any],
           let activeIndex = meta["activeIndex"] as? Int {
            config.activeSpaceNameProfileIndex = activeIndex
        }
        if !(0..<config.spaceNameProfiles.count).contains(config.activeSpaceNameProfileIndex) {
            config.activeSpaceNameProfileIndex = 0
            needsRepair = true
        }

        return (config, needsRepair)
    }

    /// `[glyphStrip]` table. Unknown enum names fall back to that key's default
    /// instead of failing the whole load, matching how the other enum keys behave.
    private static func glyphStripConfig(from object: [String: Any]) -> GlyphStripConfig? {
        guard let table = object["glyphStrip"] as? [String: Any] else { return nil }
        var config = GlyphStripConfig.default
        if let value = table["enabled"] as? Bool { config.enabled = value }
        if let value = table["hideInFullscreen"] as? Bool { config.hideInFullscreen = value }
        if let value = table["showSpaceNumbers"] as? Bool { config.showSpaceNumbers = value }
        if let name = table["spaceLabelStyle"] as? String {
            config.spaceLabelStyle = parsedEnum(from: name) ?? GlyphStripConfig.default.spaceLabelStyle
        }
        if let value = table["showLayoutSuffix"] as? Bool { config.showLayoutSuffix = value }
        if let value = table["showBSPLayoutBadge"] as? Bool { config.showBSPLayoutBadge = value }
        if let value = table["showStackLayoutBadge"] as? Bool { config.showStackLayoutBadge = value }
        if let value = table["showFloatLayoutBadge"] as? Bool { config.showFloatLayoutBadge = value }
        if let value = number(table["autoResizeMaxLength"]) { config.autoResizeMaxLength = value }
        if let value = number(table["verticalPadding"]) { config.verticalPadding = value }
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
        }
        if let value = variant(table["glassClearVariant"]) { config.glassClearVariant = value }
        if let value = variant(table["glassRegularVariant"]) { config.glassRegularVariant = value }
        if let value = variant(table["glassTintedVariant"]) { config.glassTintedVariant = value }
        if let name = table["glassTintedMaterial"] as? String {
            config.glassTintedMaterial = parsedEnum(from: name) ?? GlyphStripConfig.default.glassTintedMaterial
        }
        if let value = number(table["backgroundOpacity"]) { config.backgroundOpacity = value }
        if let value = number(table["glassClearOpacity"]) { config.glassClearOpacity = value }
        if let value = number(table["glassRegularOpacity"]) { config.glassRegularOpacity = value }
        if let value = number(table["glassTintedOpacity"]) { config.glassTintedOpacity = value }
        if let value = number(table["solidOpacity"]) { config.solidOpacity = value }
        if let value = table["matchBackgroundOpacity"] as? Bool { config.matchBackgroundOpacity = value }
        if let value = table["matchHUDAppearance"] as? Bool { config.matchHUDAppearance = value }
        if let value = number(table["cornerRadius"]) { config.cornerRadius = value }
        if let value = number(table["margin"]) { config.margin = value }
        if let value = number(table["padding"]) { config.padding = value }
        if let value = table["lockPadding"] as? Bool { config.lockPadding = value }
        if let value = number(table["horizontalPadding"]) { config.horizontalPadding = value }
        if let name = table["displayMode"] as? String {
            config.displayMode = parsedEnum(from: name) ?? GlyphStripConfig.default.displayMode
        }
        if let value = number(table["iconSpacing"]) { config.iconSpacing = value }
        if let value = number(table["indexPadding"]) { config.indexPadding = value }
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
        // Free placement mirrors the HUD: a fraction of the screen's spare
        // width/height plus the display identity. `clamped()` bounds both.
        if let value = number(table["customX"]) { config.customX = value }
        if let value = number(table["customY"]) { config.customY = value }
        if let name = table["customScreen"] as? String { config.customScreen = name }
        if let value = table["borderEnabled"] as? Bool { config.borderEnabled = value }
        if let value = table["theme"] as? String { config.theme = value }
        return config
    }

    /// Case-insensitive enum lookup: exact match, then lowercased, else nil.
    /// Callers holding struct defaults apply `?? default`; callers holding
    /// optionals assign directly so unknown names stay nil and flag repair.
    static func parsedEnum<E: RawRepresentable>(_ type: E.Type = E.self, from name: String) -> E?
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
    /// instead; `TOMLConfigDecoder.decode` still clamps to the documented range and flags
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
            config.updateMode = parsedEnum(from: name) ?? AppFontConfig.default.updateMode
        }
        if let value = table["installedVersion"] as? String {
            config.installedVersion = value
        }
        if let value = table["lastCheck"] as? Int, value >= 0 {
            config.lastCheck = value
        }
        return config
    }
}
