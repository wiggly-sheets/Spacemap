import Foundation
import CoreGraphics

extension ConfigSchema {
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
}
