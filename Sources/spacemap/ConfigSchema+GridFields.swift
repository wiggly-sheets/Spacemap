import Foundation
import CoreGraphics

extension ConfigSchema {
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
}
