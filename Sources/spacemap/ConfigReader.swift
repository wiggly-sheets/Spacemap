import Foundation
import CoreGraphics
import AppKit

enum ConfigReader {
    static var silentMode = false
    private static var hasLoadedOnce = false

    static func load() -> GridConfig {
        let path = NSString(string: "~/.config/spacemap/config").expandingTildeInPath
        let contents: String
        do {
            var raw = try String(contentsOfFile: path, encoding: .utf8)
            if raw.hasPrefix("\u{FEFF}") { raw = String(raw.dropFirst()) }
            contents = raw
            if !silentMode { NSLog("spacemap/ConfigReader: successfully read config from \(path)") }
        } catch {
            if !silentMode { NSLog("spacemap/ConfigReader: failed to read config at \(path) — error: \(error)") }
            createDefaultConfigFile()
            return .default
        }

        let result = parseConfig(contents)
        if !hasLoadedOnce {
            saveConfig(result)
            hasLoadedOnce = true
        }
        return result
    }

    private static func parseBool(_ value: String) -> Bool {
        let v = value.lowercased()
        return v == "true" || v == "1" || v == "yes" || v == "on"
    }

    static func parseConfig(_ text: String) -> GridConfig {
        var cols = GridConfig.default.cols
        var rows = GridConfig.default.rows
        var cellStyle = GridConfig.default.cellStyle
        var hotkey = GridConfig.default.hotkey
        var socketHealthInterval = GridConfig.default.socketHealthInterval
        var uiScale = GridConfig.default.uiScale
        var autoHideTimeout = GridConfig.default.autoHideTimeout
        var theme = GridConfig.default.theme
        var showMode = GridConfig.default.showMode
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
        var updateMode = GridConfig.default.updateMode
        var windowManager = WindowManagerType(rawValue: "yabai") ?? .yabai

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
                    if parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]), x >= 0, x <= 1, y >= 0, y <= 1 {
                        hudPosition = .custom(x: x, y: y)
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
            case "WINDOW_MANAGER":
                if let wm = WindowManagerType(rawValue: value) {
                    windowManager = wm
                } else {
                    print("spacemap: invalid WINDOW_MANAGER '\(value)', using default")
                }
            default: break
            }
        }

        // Resolve .custom sentinel (0,0) after all values are parsed
        // so that CUSTOM_HUD_X/Y values are available
        if case .custom(x: 0, y: 0) = hudPosition {
            hudPosition = .custom(x: customHUDX, y: customHUDY)
        }

        return GridConfig(
            cols: cols,
            rows: rows,
            cellStyle: cellStyle,
            hotkey: hotkey,
            socketHealthInterval: socketHealthInterval,
            uiScale: uiScale,
            autoHideTimeout: autoHideTimeout,
            theme: theme,
            showMode: showMode,
            maxSpaces: maxSpaces,
            backgroundAlpha: backgroundAlpha,
            mode: mode,
            iconScale: iconScale,
            showSpaceNumbers: showSpaceNumbers,
            showSpaceNames: showSpaceNames,
            showIconStrip: showIconStrip,
            showMultiAppIcons: showMultiAppIcons,
            hideMenuBarIcon: hideMenuBarIcon,
            spaceNames: spaceNames,
            useVimKeys: useVimKeys,
            useArrowKeys: useArrowKeys,
            hudPosition: hudPosition,
            customHUDX: customHUDX,
            customHUDY: customHUDY,
            showExtraWindows: showExtraWindows,
            updateMode: updateMode,
            windowManager: windowManager
        )
    }

    static func hotkeyToString(_ hotkey: HotkeyConfig) -> String {
        let modifiers = hotkey.modifiers
        let keyCode = hotkey.keyCode
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
        let keyString: String
        switch keyCode {
        case 49: keyString = "space"
        case 48: keyString = "tab"
        case 36: keyString = "return"
        case 53: keyString = "escape"
        case 51: keyString = "delete"
        case 121: keyString = "pgdn"
        case 116: keyString = "pgup"
        case 115: keyString = "home"
        case 119: keyString = "end"
        case 123: keyString = "left"
        case 124: keyString = "right"
        case 125: keyString = "down"
        case 126: keyString = "up"
        case 122: keyString = "f1"
        case 120: keyString = "f2"
        case 99: keyString = "f3"
        case 118: keyString = "f4"
        case 96: keyString = "f5"
        case 97: keyString = "f6"
        case 98: keyString = "f7"
        case 100: keyString = "f8"
        case 101: keyString = "f9"
        case 109: keyString = "f10"
        case 103: keyString = "f11"
        case 111: keyString = "f12"
        case 105: keyString = "f13"
        case 107: keyString = "f14"
        case 113: keyString = "f15"
        case 106: keyString = "f16"
        case 64: keyString = "f17"
        case 79: keyString = "f18"
        case 80: keyString = "f19"
        case 90: keyString = "f20"
        default:
            let alphanum: [CGKeyCode: String] = [
                0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g",
                6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q",
                13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1",
                19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
                25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 31: "o",
                32: "u", 33: "i", 34: "p", 35: "l", 36: "j", 37: "k", 38: "n", 39: "m"
            ]
            keyString = alphanum[keyCode] ?? "unknown"
        }
        return (modString == "none" ? "" : modString + "+") + keyString
    }

    private static func backupConfig(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let backupPath = path + ".bak"
        try? FileManager.default.removeItem(atPath: backupPath)
        try? FileManager.default.copyItem(atPath: path, toPath: backupPath)
        if !silentMode { NSLog("spacemap/ConfigReader: backed up config to \(backupPath)") }
    }

    private static func createDefaultConfigFile() {
        let path = NSString(string: "~/.config/spacemap/config").expandingTildeInPath
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        backupConfig(path)
        let d = GridConfig.default
        let hotkeyStr = hotkeyToString(d.hotkey)
        let modeStr = d.mode.rawValue
        let windowManagerStr = d.windowManager.rawValue
        let content = """
        GRID_COLS=\(d.cols)
        GRID_ROWS=\(d.rows)
        CELL_STYLE=\(cellStyleName(d.cellStyle))              # rects | icons | thumbnails | simple
        HOTKEY=\(hotkeyStr)
        SOCKET_HEALTH_INTERVAL=\(d.socketHealthInterval)
        UI_SCALE=\(d.uiScale)                  # 0.0–1.0
        AUTO_HIDE_TIMEOUT=\(d.autoHideTimeout)           # 0 = disabled, seconds
        THEME=\(d.theme)
        SHOW_MODE=\(d.showMode.rawValue)                 # all | active
        MAX_SPACES=\(d.maxSpaces)
        BACKGROUND_ALPHA=\(d.backgroundAlpha)          # 0.0–1.0
        MODE=\(modeStr)                     # light | dark | auto
        ICON_SCALE=\(d.iconScale)                # 0.0–1.0
        SHOW_SPACE_NUMBERS=\(d.showSpaceNumbers ? "on" : "off")              # on | off
        SHOW_SPACE_NAMES=\(d.showSpaceNames ? "on" : "off")              # on | off
        SHOW_ICON_STRIP=\(d.showIconStrip ? "on" : "off")              # on | off
        SHOW_MULTI_APP_ICONS=\(d.showMultiAppIcons ? "on" : "off")       # on | off
        HIDE_MENUBAR_ICON=\(d.hideMenuBarIcon ? "on" : "off")           # on | off
        VIM_KEYS=\(d.useVimKeys ? "on" : "off")                          # on | off
        ARROW_KEYS=\(d.useArrowKeys ? "on" : "off")                      # on | off
        SHOW_EXTRA_WINDOWS=\(d.showExtraWindows ? "on" : "off")        # on | off
        CUSTOM_HUD_X=\(d.customHUDX)
        CUSTOM_HUD_Y=\(d.customHUDY)
        HUD_POSITION=\(d.hudPosition == .center ? "center" : d.hudPosition == .top ? "top" : d.hudPosition == .bottom ? "bottom" : "custom")        # center | top | bottom | x,y
        SPACE_NAMES=\(d.spaceNames.map { "\($0.key):\($0.value)" }.joined(separator: ","))                  # comma-separated, e.g. "1:Term,2:Code"
        UPDATE_MODE=\(d.updateMode.rawValue)                   # auto | notify | off
        WINDOW_MANAGER=\(windowManagerStr)                     # yabai | aerospace | auto
        """
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            if !silentMode { print("spacemap: default config created at \(path)") }
        } catch {
            print("spacemap: failed to create default config at \(path): \(error)")
        }
    }

    static func saveConfig(_ config: GridConfig) {
        let path = NSString(string: "~/.config/spacemap/config").expandingTildeInPath
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        backupConfig(path)

        let hotkeyString = hotkeyToString(config.hotkey)

        let content = """
        GRID_COLS=\(config.cols)
        GRID_ROWS=\(config.rows)
        CELL_STYLE=\(cellStyleName(config.cellStyle))              # rects | icons | thumbnails | simple
        HOTKEY=\(hotkeyString)
        SOCKET_HEALTH_INTERVAL=\(config.socketHealthInterval)
        UI_SCALE=\(config.uiScale)                  # 0.0–1.0
        AUTO_HIDE_TIMEOUT=\(config.autoHideTimeout)           # 0 = disabled, seconds
        THEME=\(config.theme)
        SHOW_MODE=\(config.showMode.rawValue)                 # all | active
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
        CUSTOM_HUD_X=\(config.customHUDX)
        CUSTOM_HUD_Y=\(config.customHUDY)
        HUD_POSITION=\(hudPositionString(config.hudPosition))        # center | top | bottom | custom
        SPACE_NAMES=\(config.spaceNames.map { "\($0.key):\($0.value)" }.joined(separator: ","))                  # comma-separated, e.g. "1:Term,2:Code"
        UPDATE_MODE=\(config.updateMode.rawValue)                   # auto | notify | off
        WINDOW_MANAGER=\(config.windowManager.rawValue)                     # yabai | aerospace | auto
        """
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            if !silentMode { print("spacemap: config saved to \(path)") }
        } catch {
            print("spacemap: failed to save config to \(path): \(error)")
        }
    }

    static func parseHotkey(_ value: String) -> HotkeyConfig? {
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

        guard let keyCode = keyCodeFor(keyToken) else {
            print("spacemap: unknown key '\(keyToken)' in HOTKEY")
            return nil
        }

        return HotkeyConfig(keyCode: keyCode, modifiers: modifiers)
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

    static func cellStyleName(_ style: CellStyle) -> String {
        switch style {
        case .rects: return "rects"
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