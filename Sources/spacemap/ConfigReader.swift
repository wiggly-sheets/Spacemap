import Foundation
import CoreGraphics

enum ConfigReader {
    static var silentMode = false
    static let configPath = NSString(string: "~/.config/spacemap/spacemap.jsonc").expandingTildeInPath
    private static let legacyConfigPath = NSString(string: "~/.config/spacemap/config").expandingTildeInPath

    private enum ConfigFormat {
        case legacy
        case json
    }

    static func load() -> GridConfig {
        migrateLegacyConfigIfNeeded(from: legacyConfigPath, to: configPath)
        return load(from: configPath)
    }

    static func migrateLegacyConfigIfNeeded(from legacyPath: String, to canonicalPath: String) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: canonicalPath),
              fileManager.fileExists(atPath: legacyPath) else { return }

        let directory = (canonicalPath as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        do {
            try fileManager.moveItem(atPath: legacyPath, toPath: canonicalPath)
            if !silentMode {
                NSLog("spacemap/ConfigReader: migrated config from \(legacyPath) to \(canonicalPath)")
            }
        } catch {
            if !silentMode {
                NSLog("spacemap/ConfigReader: failed to migrate config to \(canonicalPath) — error: \(error)")
            }
        }
    }

    static func load(from path: String) -> GridConfig {
        let contents: String
        do {
            var raw = try String(contentsOfFile: path, encoding: .utf8)
            if raw.hasPrefix("\u{FEFF}") { raw = String(raw.dropFirst()) }
            contents = raw
            if !silentMode { NSLog("spacemap/ConfigReader: successfully read config from \(path)") }
        } catch {
            if !silentMode { NSLog("spacemap/ConfigReader: failed to read config at \(path) — error: \(error)") }
            createDefaultConfigFile(at: path)
            return .default
        }

        let format = detectedFormat(for: contents)
        let result: GridConfig
        switch format {
        case .legacy:
            result = parseLegacyConfig(contents)
            saveConfig(result, to: path)
        case .json:
            if let parsed = parseJSONConfig(contents) {
                result = parsed.config
                if parsed.needsRepair {
                    saveConfig(result, to: path)
                }
            } else {
                result = .default
                saveConfig(result, to: path)
            }
        }
        return result
    }

    private static func detectedFormat(for text: String) -> ConfigFormat {
        let stripped = stripJSONCComments(text) ?? text
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return .legacy }
        return first == "{" ? .json : .legacy
    }

    private static func parseBool(_ value: String) -> Bool {
        let v = value.lowercased()
        return v == "true" || v == "1" || v == "yes" || v == "on"
    }

    static func parseConfig(_ text: String) -> GridConfig {
        switch detectedFormat(for: text) {
        case .legacy:
            return parseLegacyConfig(text)
        case .json:
            return parseJSONConfig(text)?.config ?? .default
        }
    }

    private static func parseJSONConfig(_ text: String) -> (config: GridConfig, needsRepair: Bool)? {
        guard let data = jsonData(from: text) else { return nil }
        do {
            let payload = try JSONDecoder().decode(SerializableGridConfig.self, from: data)
            return payload.toGridConfig()
        } catch {
            if !silentMode { NSLog("spacemap/ConfigReader: failed to decode JSON config — error: \(error)") }
            return nil
        }
    }

    private static func jsonData(from text: String) -> Data? {
        guard let stripped = stripJSONCComments(text) else { return nil }
        return stripped.data(using: .utf8)
    }

    private static func stripJSONCComments(_ text: String) -> String? {
        var result = ""
        var isInString = false
        var isEscaping = false
        var isInLineComment = false
        var isInBlockComment = false
        var index = text.startIndex

        while index < text.endIndex {
            let ch = text[index]
            let nextIndex = text.index(after: index)
            let next = nextIndex < text.endIndex ? text[nextIndex] : nil

            if isInLineComment {
                if ch == "\n" {
                    isInLineComment = false
                    result.append(ch)
                }
                index = nextIndex
                continue
            }

            if isInBlockComment {
                if ch == "*" && next == "/" {
                    isInBlockComment = false
                    index = text.index(after: nextIndex)
                } else {
                    index = nextIndex
                }
                continue
            }

            if isInString {
                result.append(ch)
                if isEscaping {
                    isEscaping = false
                } else if ch == "\\" {
                    isEscaping = true
                } else if ch == "\"" {
                    isInString = false
                }
                index = nextIndex
                continue
            }

            if ch == "\"" {
                isInString = true
                result.append(ch)
                index = nextIndex
                continue
            }

            if ch == "/" && next == "/" {
                isInLineComment = true
                index = text.index(after: nextIndex)
                continue
            }

            if ch == "/" && next == "*" {
                isInBlockComment = true
                index = text.index(after: nextIndex)
                continue
            }

            result.append(ch)
            index = nextIndex
        }

        return result
    }

    private static func parseLegacyConfig(_ text: String) -> GridConfig {
        var cols = GridConfig.default.cols
        var rows = GridConfig.default.rows
        var cellStyle = GridConfig.default.cellStyle
        var hotkey = GridConfig.default.hotkey
        var pinnedHotkey = GridConfig.default.pinnedHotkey
        var socketHealthInterval = GridConfig.default.socketHealthInterval
        var uiScale = GridConfig.default.uiScale
        var autoHideTimeout = GridConfig.default.autoHideTimeout
        var theme = GridConfig.default.theme
        var showMode = GridConfig.default.showMode
        var multiMonitorHUDMode = GridConfig.default.multiMonitorHUDMode
        var unifiedHUDVisibility = GridConfig.default.unifiedHUDVisibility
        var separateHUDVisibility = GridConfig.default.separateHUDVisibility
        var displayNavigationWrap = GridConfig.default.displayNavigationWrap
        var maxSpaces = GridConfig.default.maxSpaces
        var backgroundAlpha = GridConfig.default.backgroundAlpha
        var mode = GridConfig.default.mode
        var iconScale = GridConfig.default.iconScale
        var showSpaceNumbers = GridConfig.default.showSpaceNumbers
        var showSpaceNames = GridConfig.default.showSpaceNames
        var showIconStrip = GridConfig.default.showIconStrip
        var showMultiAppIcons = GridConfig.default.showMultiAppIcons
        var hideMenuBarIcon = GridConfig.default.hideMenuBarIcon
        var spaceNames: [Int: String] = [:]
        var useVimKeys = GridConfig.default.useVimKeys
        var useArrowKeys = GridConfig.default.useArrowKeys
        var hudPosition = GridConfig.default.hudPosition
        var customHUDX = GridConfig.default.customHUDX
        var customHUDY = GridConfig.default.customHUDY
        var showExtraWindows = GridConfig.default.showExtraWindows
        var focusSpaceOnWindowDrop = GridConfig.default.focusSpaceOnWindowDrop
        var showHUDOnSpaceChange = GridConfig.default.showHUDOnSpaceChange
        var updateMode = GridConfig.default.updateMode

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.hasPrefix("#"), !trimmed.isEmpty else { continue }
            let stripped: String
            if let commentRange = trimmed.range(of: " #") {
                stripped = String(trimmed[..<commentRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                stripped = trimmed
            }
            guard let firstEqual = stripped.firstIndex(of: "=") else { continue }
            let key = String(stripped[..<firstEqual]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let value = String(stripped[stripped.index(after: firstEqual)...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            switch key {
            case "GRID_COLS": cols = Int(value) ?? cols
            case "GRID_ROWS": rows = Int(value) ?? rows
            case "CELL_STYLE":
                switch value {
                case "icons", "icons-only":
                    cellStyle = .icons
                    if value == "icons" { showIconStrip = true }
                    else if value == "icons-only" { showIconStrip = false }
                case "hybrid":     cellStyle = .hybrid
                case "thumbnails": cellStyle = .thumbnails
                case "simple":    cellStyle = .simple
                default:          cellStyle = .rects
                }
            case "HOTKEY":
                if let parsed = parseHotkey(value) {
                    hotkey = parsed
                } else {
                    print("spacemap: unrecognized HOTKEY '\(value)', using default")
                }
            case "PINNED_HOTKEY":
                if let parsed = parseHotkey(value) {
                    pinnedHotkey = parsed
                } else {
                    print("spacemap: unrecognized PINNED_HOTKEY '\(value)', disabling it")
                }
            case "SOCKET_HEALTH_INTERVAL":
                if let v = Int(value), v > 0 {
                    socketHealthInterval = v
                } else {
                    print("spacemap: invalid SOCKET_HEALTH_INTERVAL '\(value)', using default")
                }
            case "UI_SCALE":
                if let v = Double(value), v >= 0.0 && v <= 1.0 {
                    uiScale = v
                } else {
                    print("spacemap: invalid UI_SCALE '\(value)', using default")
                }
            case "AUTO_HIDE_TIMEOUT":
                if let v = Int(value), v >= 0 {
                    autoHideTimeout = v
                } else {
                    print("spacemap/ConfigReader: FAILED to parse AUTO_HIDE_TIMEOUT value='\(value)'")
                }
            case "THEME":
                theme = value
            case "SHOW_MODE":
                switch value {
                case "active": showMode = .active
                default:        showMode = .all
                }
            case "MULTI_MONITOR_HUD_MODE":
                switch value.lowercased() {
                case "separate", "per-display", "per_display": multiMonitorHUDMode = .separate
                default: multiMonitorHUDMode = .unified
                }
            case "UNIFIED_HUD_VISIBILITY":
                switch value.lowercased() {
                case "all", "all-displays", "all_displays": unifiedHUDVisibility = .all
                default: unifiedHUDVisibility = .active
                }
            case "SEPARATE_HUD_VISIBILITY":
                switch value.lowercased() {
                case "active", "active-display", "active_display": separateHUDVisibility = .active
                default: separateHUDVisibility = .all
                }
            case "DISPLAY_NAVIGATION_WRAP":
                switch value.lowercased() {
                case "between", "across", "cross-display", "cross_display": displayNavigationWrap = .between
                default: displayNavigationWrap = .within
                }
            case "MAX_SPACES":
                if let v = Int(value), v >= 1 && v <= 16 {
                    maxSpaces = v
                } else {
                    print("spacemap: invalid MAX_SPACES '\(value)', using default")
                }
            case "BACKGROUND_ALPHA":
                if let v = Double(value), v >= 0.0 && v <= 1.0 {
                    backgroundAlpha = v
                } else {
                    print("spacemap: invalid BACKGROUND_ALPHA '\(value)', using default")
                }
            case "MODE":
                switch value.lowercased() {
                case "light": mode = .light
                case "dark":  mode = .dark
                case "auto", "automatic": mode = .auto
                default:     mode = .auto
                }
            case "ICON_SCALE":
                if let v = Double(value), v >= 0.0 && v <= 1.0 {
                    iconScale = v
                } else {
                    print("spacemap: invalid ICON_SCALE '\(value)', using default")
                }
            case "SHOW_SPACE_NUMBERS":
                showSpaceNumbers = parseBool(value)
            case "SHOW_NAMES":
                showSpaceNumbers = parseBool(value)
            case "SHOW_SPACE_NAMES":
                showSpaceNames = parseBool(value)
            case "SHOW_ICON_STRIP":
                showIconStrip = parseBool(value)
            case "SHOW_MULTI_APP_ICONS":
                showMultiAppIcons = parseBool(value)
            case "HIDE_MENUBAR_ICON":
                hideMenuBarIcon = parseBool(value)
            case "VIM_KEYS":
                useVimKeys = parseBool(value)
            case "ARROW_KEYS":
                useArrowKeys = parseBool(value)
            case "SHOW_EXTRA_WINDOWS":
                showExtraWindows = parseBool(value)
            case "FOCUS_SPACE_ON_WINDOW_DROP":
                focusSpaceOnWindowDrop = parseBool(value)
            case "SHOW_HUD_ON_SPACE_CHANGE":
                showHUDOnSpaceChange = parseBool(value)
            case "CUSTOM_HUD_X":
                if let v = Double(value), v >= 0.0 && v <= 1.0 {
                    customHUDX = v
                } else {
                    print("spacemap: invalid CUSTOM_HUD_X '\(value)', using default")
                }
            case "CUSTOM_HUD_Y":
                if let v = Double(value), v >= 0.0 && v <= 1.0 {
                    customHUDY = v
                } else {
                    print("spacemap: invalid CUSTOM_HUD_Y '\(value)', using default")
                }
            case "HUD_POSITION":
                switch value.lowercased() {
                case "center": hudPosition = .center
                case "top": hudPosition = .top
                case "bottom": hudPosition = .bottom
                case "custom": hudPosition = .custom(x: 0, y: 0) // sentinel: coordinates set after CUSTOM_HUD_X/Y parsed
                default:
                    let parts = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                    if parts.count == 2, parts[0] >= 0, parts[0] <= 1, parts[1] >= 0, parts[1] <= 1 {
                        hudPosition = .custom(x: parts[0], y: parts[1])
                    }
                }
            case "SPACE_NAMES":
                let pairs = value.components(separatedBy: ",")
                for pair in pairs {
                    let parts = pair.components(separatedBy: ":")
                    if parts.count == 2, let id = Int(parts[0].trimmingCharacters(in: .whitespaces)) {
                        spaceNames[id] = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
            case "UPDATE_MODE":
                switch value.lowercased() {
                case "auto": updateMode = .auto
                case "notify": updateMode = .notify
                case "off": updateMode = .off
                default: updateMode = .notify
                }
            default: break
            }
        }

        // Resolve .custom sentinel (0,0) after all values are parsed
        // so that CUSTOM_HUD_X/Y values are available
        if case .custom(x: 0, y: 0) = hudPosition {
            hudPosition = .custom(x: customHUDX, y: customHUDY)
        }

        return GridConfig(cols: cols, rows: rows, cellStyle: cellStyle, hotkey: hotkey, pinnedHotkey: pinnedHotkey, socketHealthInterval: socketHealthInterval, uiScale: uiScale, autoHideTimeout: autoHideTimeout, theme: theme, showMode: showMode, multiMonitorHUDMode: multiMonitorHUDMode, unifiedHUDVisibility: unifiedHUDVisibility, separateHUDVisibility: separateHUDVisibility, displayNavigationWrap: displayNavigationWrap, maxSpaces: maxSpaces, backgroundAlpha: backgroundAlpha, mode: mode, iconScale: iconScale, showSpaceNumbers: showSpaceNumbers, showSpaceNames: showSpaceNames, showIconStrip: showIconStrip, showMultiAppIcons: showMultiAppIcons, hideMenuBarIcon: hideMenuBarIcon, spaceNames: spaceNames, useVimKeys: useVimKeys, useArrowKeys: useArrowKeys, hudPosition: hudPosition, customHUDX: customHUDX, customHUDY: customHUDY, showExtraWindows: showExtraWindows, focusSpaceOnWindowDrop: focusSpaceOnWindowDrop, showHUDOnSpaceChange: showHUDOnSpaceChange, updateMode: updateMode)
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

    private struct SerializableGridConfig: Codable {
        struct SerializableHotkey: Codable {
            let keyKind: String?
            let keyCode: CGKeyCode?
            let mediaKey: String?
            let modifiers: [String]
            var needsRepair = false

            enum CodingKeys: String, CodingKey {
                case keyKind, keyCode, mediaKey, modifiers
            }

            init(keyKind: String?, keyCode: CGKeyCode?, mediaKey: String?, modifiers: [String]) {
                self.keyKind = keyKind
                self.keyCode = keyCode
                self.mediaKey = mediaKey
                self.modifiers = modifiers
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                keyKind = try? container.decodeIfPresent(String.self, forKey: .keyKind)
                keyCode = try? container.decodeIfPresent(CGKeyCode.self, forKey: .keyCode)
                mediaKey = try? container.decodeIfPresent(String.self, forKey: .mediaKey)
                do {
                    modifiers = try container.decode([String].self, forKey: .modifiers)
                } catch {
                    modifiers = []
                    needsRepair = true
                }
            }
        }

        let cols: Int
        let rows: Int
        let cellStyle: String
        let hotkey: SerializableHotkey
        let pinnedHotkey: SerializableHotkey
        let socketHealthInterval: Int
        let uiScale: Double
        let autoHideTimeout: Int
        let theme: String
        let showMode: String
        let multiMonitorHUDMode: String
        let unifiedHUDVisibility: String
        let separateHUDVisibility: String
        let displayNavigationWrap: String
        let maxSpaces: Int
        let backgroundAlpha: Double
        let mode: String
        let iconScale: Double
        let showSpaceNumbers: Bool
        let showSpaceNames: Bool
        let showIconStrip: Bool
        let showMultiAppIcons: Bool
        let hideMenuBarIcon: Bool
        let spaceNames: [String: String]
        let useVimKeys: Bool
        let useArrowKeys: Bool
        let hudPosition: HUDPositionPayload
        let customHUDX: Double
        let customHUDY: Double
        let showExtraWindows: Bool
        let focusSpaceOnWindowDrop: Bool?
        let showHUDOnSpaceChange: Bool?
        let updateMode: String
        var needsRepair = false

        struct HUDPositionPayload: Codable {
            let kind: String
            let x: Double?
            let y: Double?
            var needsRepair = false

            enum CodingKeys: String, CodingKey {
                case kind, x, y
            }

            init(kind: String, x: Double?, y: Double?) {
                self.kind = kind
                self.x = x
                self.y = y
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                do {
                    kind = try container.decode(String.self, forKey: .kind)
                } catch {
                    kind = "center"
                    needsRepair = true
                }
                x = try? container.decodeIfPresent(Double.self, forKey: .x)
                y = try? container.decodeIfPresent(Double.self, forKey: .y)
            }
        }

        enum CodingKeys: String, CodingKey {
            case cols, rows, cellStyle, hotkey, pinnedHotkey, socketHealthInterval, uiScale
            case autoHideTimeout, theme, showMode, multiMonitorHUDMode
            case unifiedHUDVisibility, separateHUDVisibility, displayNavigationWrap
            case maxSpaces, backgroundAlpha, mode, iconScale, showSpaceNumbers
            case showSpaceNames, showIconStrip, showMultiAppIcons, hideMenuBarIcon
            case spaceNames, useVimKeys, useArrowKeys, hudPosition, customHUDX
            case customHUDY, showExtraWindows, focusSpaceOnWindowDrop
            case showHUDOnSpaceChange, updateMode
        }

        private static func decode<T: Decodable>(
            _ type: T.Type,
            forKey key: CodingKeys,
            from container: KeyedDecodingContainer<CodingKeys>,
            default defaultValue: T,
            needsRepair: inout Bool
        ) -> T {
            do {
                return try container.decode(T.self, forKey: key)
            } catch {
                needsRepair = true
                return defaultValue
            }
        }

        init(from decoder: Decoder) throws {
            let defaults = SerializableGridConfig(.default)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var repair = false

            cols = Self.decode(Int.self, forKey: .cols, from: container, default: defaults.cols, needsRepair: &repair)
            rows = Self.decode(Int.self, forKey: .rows, from: container, default: defaults.rows, needsRepair: &repair)
            cellStyle = Self.decode(String.self, forKey: .cellStyle, from: container, default: defaults.cellStyle, needsRepair: &repair)
            hotkey = Self.decode(SerializableHotkey.self, forKey: .hotkey, from: container, default: defaults.hotkey, needsRepair: &repair)
            pinnedHotkey = Self.decode(SerializableHotkey.self, forKey: .pinnedHotkey, from: container, default: defaults.pinnedHotkey, needsRepair: &repair)
            socketHealthInterval = Self.decode(Int.self, forKey: .socketHealthInterval, from: container, default: defaults.socketHealthInterval, needsRepair: &repair)
            uiScale = Self.decode(Double.self, forKey: .uiScale, from: container, default: defaults.uiScale, needsRepair: &repair)
            autoHideTimeout = Self.decode(Int.self, forKey: .autoHideTimeout, from: container, default: defaults.autoHideTimeout, needsRepair: &repair)
            theme = Self.decode(String.self, forKey: .theme, from: container, default: defaults.theme, needsRepair: &repair)
            showMode = Self.decode(String.self, forKey: .showMode, from: container, default: defaults.showMode, needsRepair: &repair)
            multiMonitorHUDMode = Self.decode(String.self, forKey: .multiMonitorHUDMode, from: container, default: defaults.multiMonitorHUDMode, needsRepair: &repair)
            unifiedHUDVisibility = Self.decode(String.self, forKey: .unifiedHUDVisibility, from: container, default: defaults.unifiedHUDVisibility, needsRepair: &repair)
            separateHUDVisibility = Self.decode(String.self, forKey: .separateHUDVisibility, from: container, default: defaults.separateHUDVisibility, needsRepair: &repair)
            displayNavigationWrap = Self.decode(String.self, forKey: .displayNavigationWrap, from: container, default: defaults.displayNavigationWrap, needsRepair: &repair)
            maxSpaces = Self.decode(Int.self, forKey: .maxSpaces, from: container, default: defaults.maxSpaces, needsRepair: &repair)
            backgroundAlpha = Self.decode(Double.self, forKey: .backgroundAlpha, from: container, default: defaults.backgroundAlpha, needsRepair: &repair)
            mode = Self.decode(String.self, forKey: .mode, from: container, default: defaults.mode, needsRepair: &repair)
            iconScale = Self.decode(Double.self, forKey: .iconScale, from: container, default: defaults.iconScale, needsRepair: &repair)
            showSpaceNumbers = Self.decode(Bool.self, forKey: .showSpaceNumbers, from: container, default: defaults.showSpaceNumbers, needsRepair: &repair)
            showSpaceNames = Self.decode(Bool.self, forKey: .showSpaceNames, from: container, default: defaults.showSpaceNames, needsRepair: &repair)
            showIconStrip = Self.decode(Bool.self, forKey: .showIconStrip, from: container, default: defaults.showIconStrip, needsRepair: &repair)
            showMultiAppIcons = Self.decode(Bool.self, forKey: .showMultiAppIcons, from: container, default: defaults.showMultiAppIcons, needsRepair: &repair)
            hideMenuBarIcon = Self.decode(Bool.self, forKey: .hideMenuBarIcon, from: container, default: defaults.hideMenuBarIcon, needsRepair: &repair)
            spaceNames = Self.decode([String: String].self, forKey: .spaceNames, from: container, default: defaults.spaceNames, needsRepair: &repair)
            useVimKeys = Self.decode(Bool.self, forKey: .useVimKeys, from: container, default: defaults.useVimKeys, needsRepair: &repair)
            useArrowKeys = Self.decode(Bool.self, forKey: .useArrowKeys, from: container, default: defaults.useArrowKeys, needsRepair: &repair)
            hudPosition = Self.decode(HUDPositionPayload.self, forKey: .hudPosition, from: container, default: defaults.hudPosition, needsRepair: &repair)
            customHUDX = Self.decode(Double.self, forKey: .customHUDX, from: container, default: defaults.customHUDX, needsRepair: &repair)
            customHUDY = Self.decode(Double.self, forKey: .customHUDY, from: container, default: defaults.customHUDY, needsRepair: &repair)
            showExtraWindows = Self.decode(Bool.self, forKey: .showExtraWindows, from: container, default: defaults.showExtraWindows, needsRepair: &repair)
            focusSpaceOnWindowDrop = Self.decode(Bool.self, forKey: .focusSpaceOnWindowDrop, from: container, default: false, needsRepair: &repair)
            showHUDOnSpaceChange = Self.decode(Bool.self, forKey: .showHUDOnSpaceChange, from: container, default: false, needsRepair: &repair)
            updateMode = Self.decode(String.self, forKey: .updateMode, from: container, default: defaults.updateMode, needsRepair: &repair)
            needsRepair = repair || hotkey.needsRepair || pinnedHotkey.needsRepair || hudPosition.needsRepair
        }

        init(_ config: GridConfig) {
            cols = config.cols
            rows = config.rows
            cellStyle = ConfigReader.cellStyleName(config.cellStyle)
            switch config.hotkey.key {
            case .none:
                hotkey = SerializableHotkey(keyKind: "none", keyCode: nil, mediaKey: nil, modifiers: ConfigReader.modifierNames(for: config.hotkey.modifiers))
            case .keyCode(let keyCode):
                hotkey = SerializableHotkey(keyKind: "keyCode", keyCode: keyCode, mediaKey: nil, modifiers: ConfigReader.modifierNames(for: config.hotkey.modifiers))
            case .mediaKey(let mediaKey):
                hotkey = SerializableHotkey(keyKind: "mediaKey", keyCode: nil, mediaKey: mediaKey.rawValue, modifiers: ConfigReader.modifierNames(for: config.hotkey.modifiers))
            }
            switch config.pinnedHotkey.key {
            case .none:
                pinnedHotkey = SerializableHotkey(keyKind: "none", keyCode: nil, mediaKey: nil, modifiers: [])
            case .keyCode(let keyCode):
                pinnedHotkey = SerializableHotkey(keyKind: "keyCode", keyCode: keyCode, mediaKey: nil, modifiers: ConfigReader.modifierNames(for: config.pinnedHotkey.modifiers))
            case .mediaKey(let mediaKey):
                pinnedHotkey = SerializableHotkey(keyKind: "mediaKey", keyCode: nil, mediaKey: mediaKey.rawValue, modifiers: ConfigReader.modifierNames(for: config.pinnedHotkey.modifiers))
            }
            socketHealthInterval = config.socketHealthInterval
            uiScale = config.uiScale
            autoHideTimeout = config.autoHideTimeout
            theme = config.theme
            showMode = config.showMode.rawValue
            multiMonitorHUDMode = config.multiMonitorHUDMode.rawValue
            unifiedHUDVisibility = config.unifiedHUDVisibility.rawValue
            separateHUDVisibility = config.separateHUDVisibility.rawValue
            displayNavigationWrap = config.displayNavigationWrap.rawValue
            maxSpaces = config.maxSpaces
            backgroundAlpha = config.backgroundAlpha
            mode = config.mode.rawValue
            iconScale = config.iconScale
            showSpaceNumbers = config.showSpaceNumbers
            showSpaceNames = config.showSpaceNames
            showIconStrip = config.showIconStrip
            showMultiAppIcons = config.showMultiAppIcons
            hideMenuBarIcon = config.hideMenuBarIcon
            spaceNames = Dictionary(uniqueKeysWithValues: config.spaceNames.map { (String($0.key), $0.value) })
            useVimKeys = config.useVimKeys
            useArrowKeys = config.useArrowKeys
            switch config.hudPosition {
            case .center: hudPosition = HUDPositionPayload(kind: "center", x: nil, y: nil)
            case .top: hudPosition = HUDPositionPayload(kind: "top", x: nil, y: nil)
            case .bottom: hudPosition = HUDPositionPayload(kind: "bottom", x: nil, y: nil)
            case .custom(let x, let y): hudPosition = HUDPositionPayload(kind: "custom", x: x, y: y)
            }
            customHUDX = config.customHUDX
            customHUDY = config.customHUDY
            showExtraWindows = config.showExtraWindows
            focusSpaceOnWindowDrop = config.focusSpaceOnWindowDrop
            showHUDOnSpaceChange = config.showHUDOnSpaceChange
            updateMode = config.updateMode.rawValue
        }

        func toGridConfig() -> (config: GridConfig, needsRepair: Bool) {
            var repair = needsRepair
            let key: HotkeyKey
            switch hotkey.keyKind?.lowercased() {
            case "none":
                key = .none
            case "mediakey", "media-key":
                if let mediaKey = ConfigReader.mediaKey(from: hotkey.mediaKey) {
                    key = .mediaKey(mediaKey)
                } else {
                    key = GridConfig.default.hotkey.key
                    repair = true
                }
            default:
                if let keyCode = hotkey.keyCode {
                    key = .keyCode(keyCode)
                } else {
                    key = GridConfig.default.hotkey.key
                    repair = true
                }
            }
            let hotkey = HotkeyConfig(key: key, modifiers: ConfigReader.modifiers(from: hotkey.modifiers))
            let pinnedKey: HotkeyKey
            switch pinnedHotkey.keyKind?.lowercased() {
            case "none":
                pinnedKey = .none
            case "mediakey", "media-key":
                if let mediaKey = ConfigReader.mediaKey(from: pinnedHotkey.mediaKey) {
                    pinnedKey = .mediaKey(mediaKey)
                } else {
                    pinnedKey = .none
                    repair = true
                }
            default:
                if let keyCode = pinnedHotkey.keyCode {
                    pinnedKey = .keyCode(keyCode)
                } else {
                    pinnedKey = .none
                    repair = true
                }
            }
            let pinnedHotkey = HotkeyConfig(key: pinnedKey, modifiers: ConfigReader.modifiers(from: pinnedHotkey.modifiers))
            let hudPositionValue: HUDPosition
            switch hudPosition.kind.lowercased() {
            case "top": hudPositionValue = .top
            case "bottom": hudPositionValue = .bottom
            case "custom":
                let x = hudPosition.x ?? customHUDX
                let y = hudPosition.y ?? customHUDY
                if (0...1).contains(x), (0...1).contains(y) {
                    hudPositionValue = .custom(x: x, y: y)
                } else {
                    hudPositionValue = .center
                    repair = true
                }
            default:
                hudPositionValue = .center
                if hudPosition.kind.lowercased() != "center" { repair = true }
            }

            let spaceNames = Dictionary(uniqueKeysWithValues: self.spaceNames.compactMap { key, value in
                Int(key).map { ($0, value) }
            })
            if spaceNames.count != self.spaceNames.count { repair = true }

            let resolvedCellStyle = ConfigReader.cellStyle(from: cellStyle)
            let resolvedShowMode = ConfigReader.showMode(from: showMode)
            let resolvedMultiMonitorMode = ConfigReader.multiMonitorHUDMode(from: multiMonitorHUDMode)
            let resolvedUnifiedVisibility = ConfigReader.hudVisibility(from: unifiedHUDVisibility)
            let resolvedSeparateVisibility = ConfigReader.hudVisibility(from: separateHUDVisibility)
            let resolvedNavigationWrap = ConfigReader.displayNavigationWrap(from: displayNavigationWrap)
            let resolvedThemeMode = ConfigReader.themeMode(from: mode)
            let resolvedUpdateMode = ConfigReader.updateMode(from: updateMode)
            if resolvedCellStyle == nil || resolvedShowMode == nil || resolvedMultiMonitorMode == nil ||
                resolvedUnifiedVisibility == nil || resolvedSeparateVisibility == nil ||
                resolvedNavigationWrap == nil || resolvedThemeMode == nil || resolvedUpdateMode == nil {
                repair = true
            }

            func valid<T>(_ value: T, default defaultValue: T, where predicate: (T) -> Bool) -> T {
                if predicate(value) { return value }
                repair = true
                return defaultValue
            }

            let config = GridConfig(
                cols: valid(cols, default: GridConfig.default.cols) { $0 > 0 },
                rows: valid(rows, default: GridConfig.default.rows) { $0 > 0 },
                cellStyle: resolvedCellStyle ?? GridConfig.default.cellStyle,
                hotkey: hotkey,
                pinnedHotkey: pinnedHotkey,
                socketHealthInterval: valid(socketHealthInterval, default: GridConfig.default.socketHealthInterval) { $0 > 0 },
                uiScale: valid(uiScale, default: GridConfig.default.uiScale) { (0...1).contains($0) },
                autoHideTimeout: valid(autoHideTimeout, default: GridConfig.default.autoHideTimeout) { $0 >= 0 },
                theme: theme,
                showMode: resolvedShowMode ?? GridConfig.default.showMode,
                multiMonitorHUDMode: resolvedMultiMonitorMode ?? GridConfig.default.multiMonitorHUDMode,
                unifiedHUDVisibility: resolvedUnifiedVisibility ?? GridConfig.default.unifiedHUDVisibility,
                separateHUDVisibility: resolvedSeparateVisibility ?? GridConfig.default.separateHUDVisibility,
                displayNavigationWrap: resolvedNavigationWrap ?? GridConfig.default.displayNavigationWrap,
                maxSpaces: valid(maxSpaces, default: GridConfig.default.maxSpaces) { (1...16).contains($0) },
                backgroundAlpha: valid(backgroundAlpha, default: GridConfig.default.backgroundAlpha) { (0...1).contains($0) },
                mode: resolvedThemeMode ?? GridConfig.default.mode,
                iconScale: valid(iconScale, default: GridConfig.default.iconScale) { (0...1).contains($0) },
                showSpaceNumbers: showSpaceNumbers,
                showSpaceNames: showSpaceNames,
                showIconStrip: showIconStrip,
                showMultiAppIcons: showMultiAppIcons,
                hideMenuBarIcon: hideMenuBarIcon,
                spaceNames: spaceNames,
                useVimKeys: useVimKeys,
                useArrowKeys: useArrowKeys,
                hudPosition: hudPositionValue,
                customHUDX: valid(customHUDX, default: GridConfig.default.customHUDX) { (0...1).contains($0) },
                customHUDY: valid(customHUDY, default: GridConfig.default.customHUDY) { (0...1).contains($0) },
                showExtraWindows: showExtraWindows,
                focusSpaceOnWindowDrop: focusSpaceOnWindowDrop ?? false,
                showHUDOnSpaceChange: showHUDOnSpaceChange ?? false,
                updateMode: resolvedUpdateMode ?? GridConfig.default.updateMode
            )
            return (config, repair)
        }
    }

    private static func modifierNames(for flags: CGEventFlags) -> [String] {
        var result: [String] = []
        if flags.contains(.maskControl) { result.append("ctrl") }
        if flags.contains(.maskCommand) { result.append("cmd") }
        if flags.contains(.maskAlternate) { result.append("alt") }
        if flags.contains(.maskShift) { result.append("shift") }
        if flags.contains(.maskSecondaryFn) { result.append("fn") }
        return result
    }

    private static func modifiers(from names: [String]) -> CGEventFlags {
        var result: CGEventFlags = []
        for name in names {
            switch name.lowercased() {
            case "ctrl": result.insert(.maskControl)
            case "cmd": result.insert(.maskCommand)
            case "alt": result.insert(.maskAlternate)
            case "shift": result.insert(.maskShift)
            case "fn": result.insert(.maskSecondaryFn)
            case "hyper":
                result.formUnion([.maskControl, .maskCommand, .maskAlternate, .maskShift])
            default:
                break
            }
        }
        return result
    }

    private static func cellStyle(from name: String) -> CellStyle? {
        switch name.lowercased() {
        case "rects": return .rects
        case "hybrid": return .hybrid
        case "icons", "icons-only": return .icons
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
        case "separate", "per-display", "per_display": return .separate
        case "unified": return .unified
        default: return nil
        }
    }

    private static func hudVisibility(from name: String) -> SeparateHUDVisibility? {
        switch name.lowercased() {
        case "active", "active-display", "active_display": return .active
        case "all", "all-displays", "all_displays": return .all
        default: return nil
        }
    }

    private static func displayNavigationWrap(from name: String) -> DisplayNavigationWrap? {
        switch name.lowercased() {
        case "within": return .within
        case "between", "across", "cross-display", "cross_display": return .between
        default: return nil
        }
    }

    private static func themeMode(from name: String) -> ThemeMode? {
        switch name.lowercased() {
        case "light": return .light
        case "dark": return .dark
        case "auto", "automatic": return .auto
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

    private static func mediaKey(from name: String?) -> MediaKey? {
        guard let name else { return nil }
        return MediaKey(rawValue: name.lowercased())
    }

    static func hotkeyToString(mediaKey: MediaKey, modifiers: CGEventFlags) -> String {
        let prefix = hotkeyModifierString(modifiers)
        let keyString = mediaKey.rawValue
        return prefix.isEmpty ? keyString : "\(prefix)+\(keyString)"
    }

    private static func hotkeyModifierString(_ modifiers: CGEventFlags) -> String {
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
        return modString
    }

    static func keyCodeToSymbolicString(_ keyCode: CGKeyCode) -> String {
        switch keyCode {
        case 49: return "space"
        case 48: return "tab"
        case 36: return "return"
        case 53: return "escape"
        case 51: return "delete"
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
            let alphanum: [CGKeyCode: String] = [
                0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g",
                6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q",
                13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1",
                19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
                25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 31: "o",
                32: "u", 33: "i", 34: "p", 35: "l", 36: "j", 37: "k", 38: "n", 39: "m"
            ]
            return alphanum[keyCode] ?? "unknown"
        }
    }

    static func hotkeyToString(keyCode: CGKeyCode, modifiers: CGEventFlags) -> String {
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
        if modString.isEmpty {
            modString = "none"
        }
        let keyString = keyCodeToSymbolicString(keyCode)
        return (modString == "none" ? "" : modString + "+") + keyString
    }

    private static func backupConfig(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let backupPath = path + ".bak"
        try? FileManager.default.removeItem(atPath: backupPath)
        try? FileManager.default.copyItem(atPath: path, toPath: backupPath)
        if !silentMode { NSLog("spacemap/ConfigReader: backed up config to \(backupPath)") }
    }

    private static func createDefaultConfigFile(at path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        backupConfig(path)
        let content = jsonConfigString(from: .default, includeHeaderComments: true)
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            if !silentMode { print("spacemap: default config created at \(path)") }
        } catch {
            print("spacemap: failed to create default config at \(path): \(error)")
        }
    }

    static func saveConfig(_ config: GridConfig) {
        saveConfig(config, to: configPath)
    }

    private static func saveConfig(_ config: GridConfig, to path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        backupConfig(path)
        let content = jsonConfigString(from: config, includeHeaderComments: true)
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            if !silentMode { print("spacemap: config saved to \(path)") }
        } catch {
            print("spacemap: failed to save config to \(path): \(error)")
        }
    }

    private static func jsonConfigString(from config: GridConfig, includeHeaderComments: Bool) -> String {
        let payload = SerializableGridConfig(config)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json: String
        do {
            let data = try encoder.encode(payload)
            json = String(decoding: data, as: UTF8.self)
        } catch {
            if !silentMode { NSLog("spacemap/ConfigReader: failed to encode JSON config — error: \(error)") }
            return legacyConfigString(from: config)
        }

        guard includeHeaderComments else { return json }
        return """
        // Spacemap config
        // JSONC is supported: comments and trailing notes are allowed.
        // Legacy key=value files are still accepted for migration.
        \(json)
        """
    }

    private static func legacyConfigString(from config: GridConfig) -> String {
        let hotkeyString = hotkeyToString(config.hotkey)
        let pinnedHotkeyString = hotkeyToString(config.pinnedHotkey)
        return """
        GRID_COLS=\(config.cols)
        GRID_ROWS=\(config.rows)
        CELL_STYLE=\(cellStyleName(config.cellStyle))              # rects | hybrid | icons | thumbnails | simple
        HOTKEY=\(hotkeyString)
        PINNED_HOTKEY=\(pinnedHotkeyString)
        SOCKET_HEALTH_INTERVAL=\(config.socketHealthInterval)
        UI_SCALE=\(config.uiScale)                  # 0.0–1.0
        AUTO_HIDE_TIMEOUT=\(config.autoHideTimeout)           # 0 = disabled, seconds
        THEME=\(config.theme)
        SHOW_MODE=\(config.showMode.rawValue)                 # all | active
        MULTI_MONITOR_HUD_MODE=\(config.multiMonitorHUDMode.rawValue)  # unified | separate
        UNIFIED_HUD_VISIBILITY=\(config.unifiedHUDVisibility.rawValue) # all | active
        SEPARATE_HUD_VISIBILITY=\(config.separateHUDVisibility.rawValue) # all | active
        DISPLAY_NAVIGATION_WRAP=\(config.displayNavigationWrap.rawValue) # within | between
        MAX_SPACES=\(config.maxSpaces)
        BACKGROUND_ALPHA=\(config.backgroundAlpha)          # 0.0–1.0
        MODE=\(config.mode.rawValue)                     # light | dark | auto
        ICON_SCALE=\(config.iconScale)                # 0.0–1.0
        SHOW_SPACE_NUMBERS=\(config.showSpaceNumbers ? "on" : "off")              # on | off
        SHOW_SPACE_NAMES=\(config.showSpaceNames ? "on" : "off")              # on | off
        SHOW_ICON_STRIP=\(config.showIconStrip ? "on" : "off")              # on | off
        SHOW_MULTI_APP_ICONS=\(config.showMultiAppIcons ? "on" : "off")       # on | off
        HIDE_MENUBAR_ICON=\(config.hideMenuBarIcon ? "on" : "off")           # on | off
        VIM_KEYS=\(config.useVimKeys ? "on" : "off")                          # on | off
        ARROW_KEYS=\(config.useArrowKeys ? "on" : "off")                      # on | off
        SHOW_EXTRA_WINDOWS=\(config.showExtraWindows ? "on" : "off")        # on | off
        FOCUS_SPACE_ON_WINDOW_DROP=\(config.focusSpaceOnWindowDrop ? "on" : "off") # on | off
        SHOW_HUD_ON_SPACE_CHANGE=\(config.showHUDOnSpaceChange ? "on" : "off") # on | off
        CUSTOM_HUD_X=\(config.customHUDX)
        CUSTOM_HUD_Y=\(config.customHUDY)
        HUD_POSITION=\(hudPositionString(config.hudPosition))        # center | top | bottom | custom
        SPACE_NAMES=\(config.spaceNames.map { "\($0.key):\($0.value)" }.joined(separator: ","))                  # comma-separated, e.g. "1:Term,2:Code"
        UPDATE_MODE=\(config.updateMode.rawValue)                   # auto | notify | off
        """
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
            case "hyper": modifiers.insert([.maskControl, .maskCommand, .maskAlternate, .maskShift])
            case "capslock": modifiers.insert(.maskAlphaShift)
            case "fn": modifiers.insert(.maskSecondaryFn)
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
        let named: [String: CGKeyCode] = [
            "space": 49, "tab": 48, "return": 36, "enter": 36,
            "escape": 53, "delete": 51, "backspace": 51,
            "pgdn": 121, "pagedown": 121, "pgup": 116, "pageup": 116,
            "home": 115, "end": 119,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "f1": 122, "f2": 120, "f3": 99,  "f4": 118,
            "f5": 96,  "f6": 97,  "f7": 98,  "f8": 100,
            "f9": 101, "f10": 109, "f11": 103, "f12": 111,
            "f13": 105, "f14": 107, "f15": 113, "f16": 106,
            "f17": 64, "f18": 79, "f19": 80, "f20": 90,
        ]
        if let code = named[token] { return code }

        let alphanum: [String: CGKeyCode] = [
            "a": 0,  "s": 1,  "d": 2,  "f": 3,  "h": 4,  "g": 5,
            "z": 6,  "x": 7,  "c": 8,  "v": 9,  "b": 11, "q": 12,
            "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18,
            "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24,
            "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "o": 31,
            "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
            "n": 45, "m": 46,
        ]
        return alphanum[token]
    }

    static func mediaKeyFor(_ token: String) -> MediaKey? {
        switch token.lowercased() {
        case "play", "playpause", "play-pause", "play_pause": return .playPause
        case "next", "nexttrack", "next-track", "next_track": return .nextTrack
        case "previous", "prev", "back", "previoustrack", "previous-track", "previous_track": return .previousTrack
        case "volumeup", "volume-up", "volume_up", "volup": return .volumeUp
        case "volumedown", "volume-down", "volume_down", "voldown": return .volumeDown
        case "mute", "muteaudio", "volume-mute", "volume_mute": return .mute
        case "brightnessup", "brightness-up", "brightness_up": return .brightnessUp
        case "brightnessdown", "brightness-down", "brightness_down": return .brightnessDown
        default: return nil
        }
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

    static func hudPositionString(_ position: HUDPosition) -> String {
        switch position {
        case .center: return "center"
        case .top: return "top"
        case .bottom: return "bottom"
        case .custom: return "custom"
        }
    }
}
