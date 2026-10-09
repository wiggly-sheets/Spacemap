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
            "useExtendedKeys", "customHUDX", "customHUDY", "focusSpaceOnWindowDrop", "showHUDOnSpaceChange",
            "focusSpaceOnWindowDropModifier", "hideMenuBarIcon",
            "menuBarDisplayMode", "menuBarNearbyCount", "jumpToSpaceEnabled", "updateMode"
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
        values.hideMenuBarIcon = value("hideMenuBarIcon")
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

        // Indexed-dotted schema written by ConfigLoader (`[spaceNameProfiles]`
        // + `[spaceNameProfiles.N]` + `[spaceNameProfiles.N.names]`).
        var index = 0
        var indexedProfiles: [SpaceNameProfile] = []
        while let profileDict = object["spaceNameProfiles.\(index)"] as? [String: Any] {
            var profile = SpaceNameProfile.default
            if let name = profileDict["name"] as? String {
                profile.name = name
            }
            if let names = object["spaceNameProfiles.\(index).names"] as? [String: Any] {
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
    private static func glyphStripConfig(from object: [String: Any]) -> GlyphStripConfig? {
        guard let table = object["glyphStrip"] as? [String: Any] else { return nil }
        var config = GlyphStripConfig.default
        if let value = table["enabled"] as? Bool { config.enabled = value }
        if let value = table["showSpaceNumbers"] as? Bool { config.showSpaceNumbers = value }
        if let value = table["showLayoutSuffix"] as? Bool { config.showLayoutSuffix = value }
        if let value = table["showAppIcons"] as? Bool { config.showAppIcons = value }
        if let name = table["iconSource"] as? String,
           let source = GlyphStripIconSource.iconSource(from: name) { config.iconSource = source }
        if let value = table["dedupeAppsPerSpace"] as? Bool { config.dedupeAppsPerSpace = value }
        if let value = number(table["maxIconsPerSpace"]) { config.maxIconsPerSpace = Int(value) }
        if let value = number(table["iconSize"]) { config.iconSize = value }
        if let value = number(table["indexSize"]) { config.indexSize = value }
        if let value = table["highlightCurrentSpace"] as? Bool { config.highlightCurrentSpace = value }
        if let name = table["backgroundMaterial"] as? String {
            config.backgroundMaterial = parsedEnum(from: name) ?? GlyphStripConfig.default.backgroundMaterial
        }
        if let name = table["shape"] as? String {
            config.shape = parsedEnum(from: name) ?? GlyphStripConfig.default.shape
        }
        if let value = number(table["glassAmount"]) { config.glassAmount = value }
        if let value = table["useThemeTint"] as? Bool { config.useThemeTint = value }
        if let value = number(table["backgroundOpacity"]) { config.backgroundOpacity = value }
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
        if let name = table["position"] as? String {
            config.position = parsedEnum(from: name) ?? GlyphStripConfig.default.position
        }
        // Int storage (see GlyphStrip.customOffsets): round, don't truncate,
        // so 12.7 lands on 13 rather than 12. Full-Double storage needs
        // Glyph* call-site changes, out of scope for this pass.
        if let value = number(table["xOffset"]) { config.xOffset = Int(value.rounded()) }
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

    private static func number(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        return nil
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
