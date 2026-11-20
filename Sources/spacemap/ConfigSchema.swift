import Foundation
import CoreGraphics

/// One config key: its TOML name and section, where it lands on the config
/// value, how it decodes and encodes, and how a missing or invalid value is
/// repaired.
struct Field<T> {
    let key: String
    /// TOML section the key is written under. `[hudKeys]` is its own section,
    /// so its section equals its key.
    let section: String
    let keyPath: WritableKeyPath<SpacemapConfig, T>
    let decode: (Any) -> T?
    let encode: (T) -> String
    let repair: Repair<T>

    var erased: AnyField { AnyField(self) }
}

/// Repair rules for a missing or invalid key.
enum Repair<T> {
    /// Missing -> default, flags repair.
    case orDefault
    /// Missing -> default, no repair flag (new keys heal silently).
    case silentDefault
    /// Missing or failing the predicate -> default, flags repair.
    case valid((T) -> Bool)
    /// Missing or below range -> default; above range -> the upper bound. Both
    /// flag repair. Stored as comparisons so `Repair` stays unconstrained.
    case clamped(upper: T, isBelow: (T) -> Bool, isAbove: (T) -> Bool)
    /// Clamps to whichever bound the value crossed, without a repair flag: the
    /// next save still writes the clamped value, but no load rewrites the file
    /// just for this.
    case silentClamped(lower: T, upper: T, isBelow: (T) -> Bool, isAbove: (T) -> Bool)
}

extension Repair where T: Comparable {
    static func clampAbove(_ range: ClosedRange<T>) -> Repair<T> {
        .clamped(
            upper: range.upperBound,
            isBelow: { $0 < range.lowerBound },
            isAbove: { $0 > range.upperBound }
        )
    }

    static func silentClampAbove(_ range: ClosedRange<T>) -> Repair<T> {
        .silentClamped(
            lower: range.lowerBound,
            upper: range.upperBound,
            isBelow: { $0 < range.lowerBound },
            isAbove: { $0 > range.upperBound }
        )
    }
}

/// Type-erased `Field` so one section is one array of heterogeneous keys.
struct AnyField {
    let key: String
    let section: String
    private let applyRaw: ([String: Any], inout SpacemapConfig, inout Bool) -> Void
    private let line: (SpacemapConfig) -> String
    private let block: (SpacemapConfig) -> String

    init<T>(_ field: Field<T>) {
        key = field.key
        section = field.section
        applyRaw = { object, config, needsRepair in
            let fallback = config[keyPath: field.keyPath]
            let raw = object[field.key].flatMap(field.decode)
            switch field.repair {
            case .orDefault:
                if raw == nil { needsRepair = true }
                config[keyPath: field.keyPath] = raw ?? fallback
            case .silentDefault:
                config[keyPath: field.keyPath] = raw ?? fallback
            case .valid(let predicate):
                if let raw, predicate(raw) {
                    config[keyPath: field.keyPath] = raw
                } else {
                    needsRepair = true
                    config[keyPath: field.keyPath] = fallback
                }
            case .clamped(let upper, let isBelow, let isAbove):
                if let raw {
                    if isBelow(raw) {
                        needsRepair = true
                        config[keyPath: field.keyPath] = fallback
                    } else if isAbove(raw) {
                        needsRepair = true
                        config[keyPath: field.keyPath] = upper
                    } else {
                        config[keyPath: field.keyPath] = raw
                    }
                } else {
                    needsRepair = true
                    config[keyPath: field.keyPath] = fallback
                }
            case .silentClamped(let lower, let upper, let isBelow, let isAbove):
                if let raw {
                    if isBelow(raw) {
                        config[keyPath: field.keyPath] = lower
                    } else if isAbove(raw) {
                        config[keyPath: field.keyPath] = upper
                    } else {
                        config[keyPath: field.keyPath] = raw
                    }
                } else {
                    config[keyPath: field.keyPath] = fallback
                }
            }
        }
        line = { config in
            "\(field.key) = \(field.encode(config[keyPath: field.keyPath]))"
        }
        block = { config in
            field.encode(config[keyPath: field.keyPath])
        }
    }

    /// Reads this key from one parsed document into `config`, applying its
    /// repair rule and flagging a rewrite when the rule asks for one.
    func apply(from object: [String: Any], into config: inout SpacemapConfig, needsRepair: inout Bool) {
        applyRaw(object, &config, &needsRepair)
    }

    /// One TOML line from the config value.
    func encodeLine(from config: SpacemapConfig) -> String {
        line(config)
    }

    /// Body of a table-shaped key. The writer supplies the `[section]` header.
    func encodeBody(from config: SpacemapConfig) -> String {
        block(config)
    }
}

enum ConfigSchema {
    /// Decoded and repaired through the grid array, and repeated in the
    /// behavior array so the writer keeps emitting its line under `[behavior]`.
    /// Both walks are idempotent for this key.
    private static let showThumbnailWallpaperField = Field(
        key: "showThumbnailWallpaper", section: "grid",
        keyPath: \.showThumbnailWallpaper,
        decode: bool, encode: { "\($0)" }, repair: .orDefault
    ).erased

    /// Upper bound keeps `GridLayout.idealSize` arithmetic (visible + cols - 1)
    /// away from `Int` overflow on a hand-edited `cols`.
    static let gridFields: [AnyField] = [
        Field(
            key: "cols", section: "grid",
            keyPath: \.cols,
            decode: positiveInt, encode: { "\($0)" }, repair: .clampAbove(1...32)
        ).erased,
        Field(
            key: "rows", section: "grid",
            keyPath: \.rows,
            decode: positiveInt, encode: { "\($0)" }, repair: .clampAbove(1...32)
        ).erased,
        Field(
            key: "cellStyle", section: "grid",
            keyPath: \.cellStyle,
            decode: { ($0 as? String).flatMap(cellStyle(from:)) },
            encode: { ConfigLoader.tomlString(ConfigLoader.cellStyleName($0)) },
            repair: .orDefault
        ).erased,
        Field(
            key: "showMode", section: "grid",
            keyPath: \.showMode,
            decode: { ($0 as? String).flatMap(showMode(from:)) },
            encode: { ConfigLoader.tomlString($0.rawValue) },
            repair: .orDefault
        ).erased,
        Field(
            key: "multiMonitorHUDMode", section: "grid",
            keyPath: \.multiMonitorHUDMode,
            decode: { ($0 as? String).flatMap(multiMonitorHUDMode(from:)) },
            encode: { ConfigLoader.tomlString($0.rawValue) },
            repair: .orDefault
        ).erased,
        Field(
            key: "unifiedHUDVisibility", section: "grid",
            keyPath: \.unifiedHUDVisibility,
            decode: { ($0 as? String).flatMap(hudVisibility(from:)) },
            encode: { ConfigLoader.tomlString($0.rawValue) },
            repair: .orDefault
        ).erased,
        Field(
            key: "separateHUDVisibility", section: "grid",
            keyPath: \.separateHUDVisibility,
            decode: { ($0 as? String).flatMap(hudVisibility(from:)) },
            encode: { ConfigLoader.tomlString($0.rawValue) },
            repair: .orDefault
        ).erased,
        Field(
            key: "maxSpaces", section: "grid",
            keyPath: \.maxSpaces,
            decode: positiveInt, encode: { "\($0)" }, repair: .clampAbove(1...16)
        ).erased,
        Field(
            key: "showSpaceNumbers", section: "grid",
            keyPath: \.showSpaceNumbers,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        Field(
            key: "showSpaceLayout", section: "grid",
            keyPath: \.showSpaceLayout,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        Field(
            key: "showIconStrip", section: "grid",
            keyPath: \.showIconStrip,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        Field(
            key: "showMultiAppIcons", section: "grid",
            keyPath: \.showMultiAppIcons,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        Field(
            key: "hudIconSource", section: "grid",
            keyPath: \.hudIconSource,
            decode: { ($0 as? String).flatMap(GlyphStripIconSource.iconSource(from:)) },
            encode: { "\"\($0.rawValue)\"" },
            repair: .silentDefault
        ).erased,
        Field(
            key: "hudIconStripSeparate", section: "grid",
            keyPath: \.hudIconStripSeparate,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        Field(
            key: "hudIconStripSource", section: "grid",
            keyPath: \.hudIconStripSource,
            decode: { ($0 as? String).flatMap(GlyphStripIconSource.iconSource(from:)) },
            encode: { "\"\($0.rawValue)\"" },
            repair: .silentDefault
        ).erased,
        // Sits here for decode and repair, but the writer emits it under
        // [behavior], where it has always lived.
        showThumbnailWallpaperField
    ]

    /// `[appearance]`. Array order is the writer's line order; the flatten
    /// list reads the keys from here so the two cannot drift apart.
    static let appearanceFields: [AnyField] = [
        // A theme that is not installed yet must not be repaired away: the HUD
        // already falls back to the default look at use time, and rewriting the
        // file would destroy the user's choice (catalog download pending, theme
        // file removed, or a build without bundled themes).
        Field(
            key: "theme", section: "appearance",
            keyPath: \.theme,
            decode: { ($0 as? String).map { String($0.prefix(128)) } },
            encode: { ConfigLoader.tomlString($0) }, repair: .orDefault
        ).erased,
        Field(
            key: "mode", section: "appearance",
            keyPath: \.mode,
            decode: { themeMode(from: $0) },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .orDefault
        ).erased,
        Field(
            key: "backgroundAlpha", section: "appearance",
            keyPath: \.backgroundAlpha,
            decode: { rangedDouble($0) }, encode: { "\($0)" },
            repair: .valid { (0...1).contains($0) }
        ).erased,
        Field(
            key: "backgroundStyle", section: "appearance",
            keyPath: \.backgroundStyle,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .orDefault
        ).erased,
        Field(
            key: "glassStyle", section: "appearance",
            keyPath: \.glassStyle,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .orDefault
        ).erased,
        Field(
            key: "glassClearVariant", section: "appearance",
            keyPath: \.glassClearVariant,
            decode: { variant($0) }, encode: { "\($0)" },
            repair: .silentClampAbove(0...21)
        ).erased,
        Field(
            key: "glassRegularVariant", section: "appearance",
            keyPath: \.glassRegularVariant,
            decode: { variant($0) }, encode: { "\($0)" },
            repair: .silentClampAbove(0...21)
        ).erased,
        Field(
            key: "glassTintedVariant", section: "appearance",
            keyPath: \.glassTintedVariant,
            decode: { variant($0) }, encode: { "\($0)" },
            repair: .silentClampAbove(0...21)
        ).erased,
        Field(
            key: "glassTintedMaterial", section: "appearance",
            keyPath: \.glassTintedMaterial,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .silentDefault
        ).erased,
        Field(
            key: "glassClearOpacity", section: "appearance",
            keyPath: \.glassClearOpacity,
            decode: { rangedDouble($0) }, encode: { "\($0)" },
            repair: .valid { (0...1).contains($0) }
        ).erased,
        Field(
            key: "glassRegularOpacity", section: "appearance",
            keyPath: \.glassRegularOpacity,
            decode: { rangedDouble($0) }, encode: { "\($0)" },
            repair: .valid { (0...1).contains($0) }
        ).erased,
        Field(
            key: "glassTintedOpacity", section: "appearance",
            keyPath: \.glassTintedOpacity,
            decode: { rangedDouble($0) }, encode: { "\($0)" },
            repair: .valid { (0...1).contains($0) }
        ).erased,
        Field(
            key: "solidOpacity", section: "appearance",
            keyPath: \.solidOpacity,
            decode: { rangedDouble($0) }, encode: { "\($0)" },
            repair: .valid { (0...1).contains($0) }
        ).erased,
        Field(
            key: "matchBackgroundOpacity", section: "appearance",
            keyPath: \.matchBackgroundOpacity,
            decode: bool, encode: { "\($0)" }, repair: .silentDefault
        ).erased,
        Field(
            key: "hudShadow", section: "appearance",
            keyPath: \.hudShadow,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        Field(
            key: "hudCornerRadius", section: "appearance",
            keyPath: \.hudCornerRadius,
            decode: { double($0) }, encode: { "\($0)" },
            repair: .valid { (0...60).contains($0) }
        ).erased,
        Field(
            key: "hudFontName", section: "appearance",
            keyPath: \.hudFontName,
            decode: { $0 as? String },
            encode: { ConfigLoader.tomlString($0) }, repair: .silentDefault
        ).erased,
        Field(
            key: "hudFontSize", section: "appearance",
            keyPath: \.hudFontSize,
            decode: { double($0) }, encode: { "\($0)" },
            repair: .valid { (8...48).contains($0) }
        ).erased,
        Field(
            key: "hudTextColor", section: "appearance",
            keyPath: \.hudTextColor,
            decode: { $0 as? String },
            encode: { ConfigLoader.tomlString($0) }, repair: .silentDefault
        ).erased,
        Field(
            key: "spacesMatchBackground", section: "appearance",
            keyPath: \.spacesMatchBackground,
            decode: bool, encode: { "\($0)" }, repair: .silentDefault
        ).erased,
        Field(
            key: "spacesBackgroundStyle", section: "appearance",
            keyPath: \.spacesBackgroundStyle,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .silentDefault
        ).erased,
        Field(
            key: "spacesGlassStyle", section: "appearance",
            keyPath: \.spacesGlassStyle,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .silentDefault
        ).erased,
        Field(
            key: "spacesGlassClearVariant", section: "appearance",
            keyPath: \.spacesGlassClearVariant,
            decode: { variant($0) }, encode: { "\($0)" },
            repair: .silentClampAbove(0...21)
        ).erased,
        Field(
            key: "spacesGlassRegularVariant", section: "appearance",
            keyPath: \.spacesGlassRegularVariant,
            decode: { variant($0) }, encode: { "\($0)" },
            repair: .silentClampAbove(0...21)
        ).erased,
        Field(
            key: "spacesGlassTintedVariant", section: "appearance",
            keyPath: \.spacesGlassTintedVariant,
            decode: { variant($0) }, encode: { "\($0)" },
            repair: .silentClampAbove(0...21)
        ).erased,
        Field(
            key: "spacesGlassTintedMaterial", section: "appearance",
            keyPath: \.spacesGlassTintedMaterial,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .silentDefault
        ).erased,
        Field(
            key: "spacesOpacity", section: "appearance",
            keyPath: \.spacesOpacity,
            decode: { rangedDouble($0) }, encode: { "\($0)" },
            repair: .silentClampAbove(0...1)
        ).erased,
        Field(
            key: "spacesCornerRadius", section: "appearance",
            keyPath: \.spacesCornerRadius,
            decode: { double($0) }, encode: { "\($0)" },
            repair: .silentClampAbove(0...60)
        ).erased,
        Field(
            key: "iconScale", section: "appearance",
            keyPath: \.iconScale,
            decode: { rangedDouble($0) }, encode: { "\($0)" },
            repair: .valid { (0...1).contains($0) }
        ).erased,
        Field(
            key: "uiScale", section: "appearance",
            keyPath: \.uiScale,
            decode: { rangedDouble($0) }, encode: { "\($0)" },
            repair: .valid { (0...1).contains($0) }
        ).erased
    ]

    /// `[behavior]` scalars. Array order is the writer's line order.
    static let behaviorFields: [AnyField] = [
        Field(
            key: "autoHideTimeout", section: "behavior",
            keyPath: \.autoHideTimeout,
            decode: nonNegativeInt, encode: { "\($0)" },
            repair: .valid { $0 >= 0 }
        ).erased,
        Field(
            key: "displayNavigationWrap", section: "behavior",
            keyPath: \.displayNavigationWrap,
            decode: { ($0 as? String).flatMap(displayNavigationWrap(from:)) },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .orDefault
        ).erased,
        Field(
            key: "jumpToSpaceEnabled", section: "behavior",
            keyPath: \.jumpToSpaceEnabled,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        Field(
            key: "fuzzySpaceJumpEnabled", section: "behavior",
            keyPath: \.fuzzySpaceJumpEnabled,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        Field(
            key: "focusSpaceOnWindowDrop", section: "behavior",
            keyPath: \.focusSpaceOnWindowDrop,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .orDefault
        ).erased,
        Field(
            key: "focusSpaceOnWindowDropModifier", section: "behavior",
            keyPath: \.focusSpaceOnWindowDropModifier,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .orDefault
        ).erased,
        Field(
            key: "showHUDOnSpaceChange", section: "behavior",
            keyPath: \.showHUDOnSpaceChange,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        Field(
            key: "showBSPLayoutBadge", section: "behavior",
            keyPath: \.showBSPLayoutBadge,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        Field(
            key: "showStackLayoutBadge", section: "behavior",
            keyPath: \.showStackLayoutBadge,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        Field(
            key: "showFloatLayoutBadge", section: "behavior",
            keyPath: \.showFloatLayoutBadge,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        Field(
            key: "showHUDInteractionFeedback", section: "behavior",
            keyPath: \.showHUDInteractionFeedback,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        // Unparsable names heal to their defaults without a rewrite.
        Field(
            key: "spaceDropMode", section: "behavior",
            keyPath: \.spaceDropMode,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .silentDefault
        ).erased,
        Field(
            key: "spaceDragFocus", section: "behavior",
            keyPath: \.spaceDragFocus,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .silentDefault
        ).erased,
        Field(
            key: "windowDragFocus", section: "behavior",
            keyPath: \.windowDragFocus,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .silentDefault
        ).erased,
        showThumbnailWallpaperField,
        Field(
            key: "hudAnimationsEnabled", section: "behavior",
            keyPath: \.hudAnimationsEnabled,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        Field(
            key: "hudAnimationStyle", section: "behavior",
            keyPath: \.hudAnimationStyle,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .silentDefault
        ).erased,
        Field(
            key: "hudEntranceStyle", section: "behavior",
            keyPath: \.hudEntranceStyle,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .silentDefault
        ).erased,
        Field(
            key: "presence", section: "behavior",
            keyPath: \.presence,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .orDefault
        ).erased,
        Field(
            key: "menuBarDisplayMode", section: "behavior",
            keyPath: \.menuBarDisplayMode,
            decode: { ($0 as? String).flatMap { TOMLConfigDecoder.parsedEnum(from: $0) } },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .orDefault
        ).erased,
        Field(
            key: "menuBarNearbyCount", section: "behavior",
            keyPath: \.menuBarNearbyCount,
            decode: positiveInt, encode: { "\($0)" }, repair: .clampAbove(1...16)
        ).erased,
        Field(
            key: "updateMode", section: "behavior",
            keyPath: \.updateMode,
            decode: { ($0 as? String).flatMap(updateMode(from:)) },
            encode: { ConfigLoader.tomlString($0.rawValue) }, repair: .orDefault
        ).erased
    ]

    /// Keys written as a TOML table. Array order is the writer's block order.
    static let tableFields: [AnyField] = [
        hotkeyField("hotkey", \.hotkey),
        hotkeyField("pinnedHotkey", \.pinnedHotkey),
        hotkeyField("glyphStripHotkey", \.glyphStripHotkey),
        hotkeyField("hudMoveSpaceBackHotkey", \.hudMoveSpaceBackHotkey),
        hotkeyField("hudMoveSpaceForwardHotkey", \.hudMoveSpaceForwardHotkey),
        hotkeyField("hudNewSpaceHotkey", \.hudNewSpaceHotkey),
        hotkeyField("hudDeleteSpaceHotkey", \.hudDeleteSpaceHotkey),
        hotkeyField("hudCycleLayoutHotkey", \.hudCycleLayoutHotkey),
        Field(
            key: "hudKeys", section: "hudKeys",
            keyPath: \.hudKeys,
            decode: hudKeysBindings, encode: hudKeysBody, repair: .orDefault
        ).erased,
        Field(
            key: "hudPosition", section: "behavior",
            keyPath: \.hudPosition,
            decode: hudPosition, encode: hudPositionBody, repair: .orDefault
        ).erased
    ]

    /// `[advanced]`. Array order is the writer's line order.
    static let advancedFields: [AnyField] = [
        Field(
            key: "socketHealthInterval", section: "advanced",
            keyPath: \.socketHealthInterval,
            decode: positiveInt, encode: { "\($0)" }, repair: .clampAbove(1...3600)
        ).erased,
        Field(
            key: "showExtraWindows", section: "advanced",
            keyPath: \.showExtraWindows,
            decode: bool, encode: { "\($0)" }, repair: .orDefault
        ).erased,
        // New flag: absent in old files heals silently without forcing a
        // config rewrite.
        Field(
            key: "refuseUntrustedYabai", section: "advanced",
            keyPath: \.refuseUntrustedYabai,
            decode: bool, encode: { "\($0)" }, repair: .silentDefault
        ).erased
    ]

    /// Keys a `[section]` table may hold, gathered from every field table so a
    /// new key needs no second list. `[hudKeys]` is its own root table.
    static func flattenedKeys(in section: String) -> [String] {
        (gridFields + appearanceFields + behaviorFields + tableFields + advancedFields)
            .filter { $0.section == section }
            .map(\.key)
    }

    private static func hotkeyField(
        _ key: String,
        _ keyPath: WritableKeyPath<SpacemapConfig, HotkeyConfig>
    ) -> AnyField {
        Field(
            key: key, section: "behavior",
            keyPath: keyPath,
            decode: { ($0 as? [String: Any]).flatMap(parseHotkeyTable) },
            encode: hotkeyBody, repair: .orDefault
        ).erased
    }

    /// `[behavior.<key>]` body. `modifiers` always closes the table.
    private static func hotkeyBody(_ hotkey: HotkeyConfig) -> String {
        var lines: [String]
        switch hotkey.key {
        case .none:
            lines = ["keyKind = \"none\""]
        case .keyCode(let keyCode):
            lines = ["keyKind = \"keyCode\"", "keyCode = \(keyCode)"]
        case .mediaKey(let mediaKey):
            lines = ["keyKind = \"mediaKey\"", "mediaKey = \(ConfigLoader.tomlString(mediaKey.rawValue))"]
        }
        lines.append("modifiers = \(ConfigLoader.tomlStringArray(Hotkey.modifierNames(for: hotkey.modifiers)))")
        return lines.joined(separator: "\n")
    }

    /// `[hudKeys]` body: every command is written, unbound ones as `[]`.
    private static func hudKeysBody(_ bindings: HUDKeyBindings) -> String {
        HUDCommand.allCases.map { command in
            let names = bindings[command].filter { !$0.isDisabled }.map(Hotkey.hotkeyToString)
            return "\(command.rawValue) = \(ConfigLoader.tomlStringArray(names))"
        }.joined(separator: "\n")
    }

    private static func hudKeysBindings(_ raw: Any) -> HUDKeyBindings? {
        guard let table = raw as? [String: Any] else { return nil }
        var bindings = HUDKeyBindings.default
        for (name, rawNames) in table {
            guard let command = HUDCommand(rawValue: name), let names = rawNames as? [String] else {
                continue
            }
            bindings[command] = names.compactMap { Hotkey.parseHotkey($0) }
        }
        return bindings
    }

    private static func hudPositionBody(_ position: HUDPosition) -> String {
        var lines = ["kind = \(ConfigLoader.tomlString(HUDPositionKind(from: position).rawValue))"]
        if case .custom(let x, let y, let screen) = position {
            lines += ["x = \(x)", "y = \(y)"]
            // Optional: a custom position without a display pairing keeps the
            // key out of the file, so old and new files round-trip unchanged.
            if let screen, !screen.isEmpty {
                lines.append("screen = \(ConfigLoader.tomlString(screen))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func hudPosition(_ raw: Any) -> HUDPosition? {
        guard let table = raw as? [String: Any], let kind = table["kind"] as? String else { return nil }
        switch kind.lowercased() {
        case "center": return .center
        case "top": return .top
        case "bottom": return .bottom
        case "custom":
            // Numeric and in range; no invented 0.5 fallback so repair heals it.
            guard let x = double(table["x"]), let y = double(table["y"]),
                  (0...1).contains(x), (0...1).contains(y) else { return nil }
            let screen = (table["screen"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .custom(x: x, y: y, screen: screen)
        default: return nil
        }
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

    private static func displayNavigationWrap(from name: String) -> DisplayNavigationWrap? {
        switch name.lowercased() {
        case "within": return .within
        case "between": return .between
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

    /// A fraction 0...1 from a raw TOML number. Out-of-range values decode nil
    /// so the key falls back to its default instead of clamping.
    private static func rangedDouble(_ raw: Any) -> Double? {
        guard let value = double(raw), (0...1).contains(value) else { return nil }
        return value
    }

    private static func double(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        return nil
    }

    /// Only an `Int` in 0...21 counts; `15.0` and oversized values decode nil
    /// so the key falls back to its default instead of clamping.
    private static func variant(_ raw: Any) -> Int? {
        guard let value = raw as? Int, (0...21).contains(value) else { return nil }
        return value
    }

    private static func themeMode(from raw: Any) -> ThemeMode? {
        guard let name = raw as? String else { return nil }
        switch name.lowercased() {
        case "light": return .light
        case "dark": return .dark
        case "auto": return .auto
        default: return nil
        }
    }

    private static func positiveInt(_ raw: Any) -> Int? {
        guard let value = raw as? Int, value > 0 else { return nil }
        return value
    }

    private static func nonNegativeInt(_ raw: Any) -> Int? {
        guard let value = raw as? Int, value >= 0 else { return nil }
        return value
    }

    private static func bool(_ raw: Any) -> Bool? {
        raw as? Bool
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
}
