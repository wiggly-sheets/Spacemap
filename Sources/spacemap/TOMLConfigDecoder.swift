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

        // `showThumbnailWallpaper` is also flattened from [behavior] below: the
        // key is written there, older files may carry it under either section.
        flatten("grid", keys: ConfigSchema.flattenedKeys(in: "grid"))
        flatten("appearance", keys: ConfigSchema.flattenedKeys(in: "appearance"))
        // The explicit key covers the grid field the writer emits under
        // [behavior], which `flattenedKeys` files under [grid].
        flatten("behavior", keys: ConfigSchema.flattenedKeys(in: "behavior") + ["showThumbnailWallpaper"])
        flatten("advanced", keys: ConfigSchema.flattenedKeys(in: "advanced"))

        // `[spaceNames]` holds the showSpaceNames toggle and namingMode; the
        // names live in the nested `names` table (written as `[spaceNames.names]`).
        var spaceNames: [String: Any] = [:]
        if let section = result.removeValue(forKey: "spaceNames") as? [String: Any] {
            if let show = section["showSpaceNames"] {
                result["showSpaceNames"] = show
            }
            if let naming = section["namingMode"] {
                result["namingMode"] = naming
            }
            if let appCount = section["autoNameAppCount"] {
                result["autoNameAppCount"] = appCount
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
        // New key: absent in old files heals silently, like the other keys added
        // to an existing section. An unknown value falls back to custom.
        if let name = object["namingMode"] as? String {
            config.namingMode = parsedEnum(from: name) ?? SpacemapConfig.default.namingMode
        }
        // New key too: absent in old files heals silently. Values outside the
        // stepper's 1-3 range clamp and flag a rewrite.
        if let appCount = object["autoNameAppCount"] as? Int {
            let clamped = min(max(appCount, 1), 3)
            if clamped != appCount { needsRepair = true }
            config.autoNameAppCount = clamped
        } else {
            config.autoNameAppCount = SpacemapConfig.default.autoNameAppCount
        }

        // Out-of-range strip numbers clamp in memory and flag a rewrite.
        if var strip = glyphStripConfig(from: object) {
            // A status item cannot draw glass. Heal a saved glass material so
            // menu-bar mode stays solid or transparent.
            if strip.displayMode == .menuBarItem, strip.backgroundMaterial == .liquidGlass {
                strip.backgroundMaterial = .solid
                needsRepair = true
            }
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
        if let value = number(table["plainMargin"]) { config.plainMargin = value }
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
        if let name = table["plainPosition"] as? String {
            config.plainPosition = parsedEnum(from: name) ?? GlyphStripConfig.default.plainPosition
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
        if let value = number(table["plainCustomX"]) { config.plainCustomX = value }
        if let value = number(table["plainCustomY"]) { config.plainCustomY = value }
        if let name = table["plainCustomScreen"] as? String { config.plainCustomScreen = name }
        // Pre-separation configs shared one point between both screen types.
        // Seed the plain point from it so a dragged plain strip survives the
        // upgrade with its old position.
        if table["plainCustomX"] == nil,
           table["plainCustomY"] == nil,
           table["plainCustomScreen"] == nil {
            config.plainCustomX = config.customX
            config.plainCustomY = config.customY
            config.plainCustomScreen = config.customScreen
        }
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
