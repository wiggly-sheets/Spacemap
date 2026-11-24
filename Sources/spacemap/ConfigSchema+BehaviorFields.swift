import Foundation
import CoreGraphics

extension ConfigSchema {
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
}
