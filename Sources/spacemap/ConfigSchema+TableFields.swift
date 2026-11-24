import Foundation
import CoreGraphics

extension ConfigSchema {
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
}
