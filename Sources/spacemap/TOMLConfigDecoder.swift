import Foundation
import CoreGraphics

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
            "showSpaceNumbers", "showIconStrip", "showMultiAppIcons"
        ])
        flatten("appearance", keys: [
            "theme", "mode", "backgroundAlpha", "hudShadow", "iconScale", "uiScale"
        ])
        flatten("behavior", keys: [
            "autoHideTimeout", "displayNavigationWrap", "useVimKeys", "useArrowKeys",
            "customHUDX", "customHUDY", "focusSpaceOnWindowDrop", "showHUDOnSpaceChange",
            "focusSpaceOnWindowDropModifier", "hideMenuBarIcon", "menuBarDisplayMode",
            "menuBarNearbyCount", "jumpToSpaceEnabled", "updateMode"
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
        values.showIconStrip = value("showIconStrip")
        values.showMultiAppIcons = value("showMultiAppIcons")

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

        values.theme = value("theme")
        if let name: String = value("mode") {
            values.mode = themeMode(from: name)
        }
        values.backgroundAlpha = rangedDouble("backgroundAlpha")
        values.hudShadow = value("hudShadow")
        values.iconScale = rangedDouble("iconScale")
        values.uiScale = rangedDouble("uiScale")

        values.autoHideTimeout = nonNegativeInt("autoHideTimeout")
        if let name: String = value("displayNavigationWrap") {
            values.displayNavigationWrap = displayNavigationWrap(from: name)
        }
        values.useVimKeys = value("useVimKeys")
        values.useArrowKeys = value("useArrowKeys")
        values.jumpToSpaceEnabled = value("jumpToSpaceEnabled")
        values.customHUDX = rangedDouble("customHUDX")
        values.customHUDY = rangedDouble("customHUDY")
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
        values.menuBarNearbyCount = positiveInt("menuBarNearbyCount")
        if let name: String = value("updateMode") {
            values.updateMode = updateMode(from: name)
        }

        if let table = object["hotkey"] as? [String: Any] {
            values.hotkey = parseHotkeyTable(table)
        }
        if let table = object["pinnedHotkey"] as? [String: Any] {
            values.pinnedHotkey = parseHotkeyTable(table)
        }

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

        values.socketHealthInterval = positiveInt("socketHealthInterval")
        values.showExtraWindows = value("showExtraWindows")

        return values
    }


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
