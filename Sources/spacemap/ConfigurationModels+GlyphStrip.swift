import Foundation
import CoreGraphics


enum GlyphStripBackgroundMaterial: String, CaseIterable, Identifiable, Equatable {
    case none
    case solid
    /// Native glass behind the glyphs rather than a flat fill.
    case liquidGlass

    var id: String { rawValue }

    /// Materials that draw something behind the glyphs. `none` is the only one
    /// that does not, which is what the settings pane keys the opacity control
    /// off.
    var drawsBackdrop: Bool { self != .none }
}

enum GlyphStripAction: String, CaseIterable, Identifiable, Equatable {
    case none
    case focusSpace
    case destroySpace
    case moveWindowHere
    case toggleFullscreen
    case floatWindow
    case balanceWindows
    case mergeWindows

    var id: String { rawValue }

    /// Actions that operate on the focused window rather than a space index.
    var needsWindow: Bool {
        switch self {
        case .toggleFullscreen, .floatWindow, .balanceWindows: return true
        case .none, .focusSpace, .destroySpace, .moveWindowHere, .mergeWindows: return false
        }
    }
}

/// Floating overlay or a native menu-bar item. The status item is limited to
/// the horizontal row and drops shape, glass and free placement.
enum GlyphStripDisplayMode: String, CaseIterable, Identifiable, Equatable {
    case floating
    case menuBarItem

    var id: String { rawValue }
}

enum GlyphStripPosition: String, CaseIterable, Identifiable, Equatable {
    case leftOfNotch
    case rightOfNotch
    case center
    /// Free placement: a screen fraction plus a screen identity.
    case custom

    var id: String { rawValue }
}

/// How the strip stacks its spaces. `horizontal` is the menu-bar row;
/// `vertical` stacks one space per row for a side-of-screen strip.
enum GlyphStripOrientation: String, CaseIterable, Identifiable, Equatable {
    case horizontal
    case vertical

    var id: String { rawValue }
}

/// How a vertical strip lays out one space. `inline` keeps the index and its
/// icons on one line; `stacked` puts the index on top and stacks the icons
/// underneath it.
enum GlyphStripVerticalLayout: String, CaseIterable, Identifiable, Equatable {
    case inline
    case stacked

    var id: String { rawValue }
}

/// Where the strip's per-window icons come from. `sbarFont` draws
/// sketchybar-app-font glyphs (current look, default); `native` draws the app's
/// own icon via IconCache with sbar-glyph-then-initials fallback.
enum GlyphStripIconSource: String, CaseIterable, Identifiable, Equatable {
    case sbarFont = "sbarFont"
    case nativeIcons = "native"

    var id: String { rawValue }

    /// Accepts both spellings users reach for: "sbarFont" and "native".
    static func iconSource(from name: String) -> GlyphStripIconSource? {
        switch name.lowercased() {
        case "sbarfont", "sbar": return .sbarFont
        case "native", "nativeicons": return .nativeIcons
        default: return nil
        }
    }
}

/// What a strip's leading label run shows: the space number (today's look), the
/// space's name from the active name profile, or both.
enum GlyphStripSpaceLabelStyle: String, CaseIterable, Identifiable, Equatable {
    case numbers
    case names
    case both

    var id: String { rawValue }
}

/// Settings for the always-visible menu-bar glyph strip (theme-driven colours).
/// `[glyphStrip]` table, strip only; HUD cells use `SpacemapConfig.showSpaceNumbers`.
struct GlyphStripConfig: Equatable {
    var enabled: Bool = false
    /// Hide the strip while another app is in native fullscreen, so the strip
    /// never floats over a fullscreen window or its menu bar reveal.
    var hideInFullscreen: Bool = false
    var showSpaceNumbers: Bool = true
    var spaceLabelStyle: GlyphStripSpaceLabelStyle = .numbers
    var showLayoutSuffix: Bool = true
    var showBSPLayoutBadge: Bool = true
    var showStackLayoutBadge: Bool = true
    var showFloatLayoutBadge: Bool = true
    var showAppIcons: Bool = true
    var iconSource: GlyphStripIconSource = .sbarFont
    var dedupeAppsPerSpace: Bool = true
    var maxIconsPerSpace: Int = 8
    var iconSize: Double = 11
    var indexSize: Double = 11
    var highlightCurrentSpace: Bool = true
    var backgroundMaterial: GlyphStripBackgroundMaterial = .none
    var glassStyle: HUDGlassStyle = .regular
    var glassClearVariant: Int = 11
    var glassRegularVariant: Int = 5
    var glassTintedVariant: Int = 2
    var glassTintedMaterial: HUDGlassMaterial = .clear
    var matchHUDAppearance: Bool = false
    var matchBackgroundOpacity: Bool = false
    var backgroundOpacity: Double = 0.35
    var glassClearOpacity: Double = 0.05
    var glassRegularOpacity: Double = 0.35
    var glassTintedOpacity: Double = 0.35
    var solidOpacity: Double = 0.35
    var cornerRadius: Double = 20
    var margin: Double = 6
    /// Gap to the screen edge on a display without a notch.
    var plainMargin: Double = 6
    /// Inner padding around the glyphs. `lockPadding` keeps all sides equal.
    var padding: Double = 4
    var lockPadding: Bool = true
    var horizontalPadding: Double = 4
    /// Menu-bar item mode ignores shape, glass and placement.
    var displayMode: GlyphStripDisplayMode = .floating
    var hoverPadding: Double = 1
    var hoverCornerRadius: Double = 4
    var autoResizeMaxLength: Double = 0
    var verticalPadding: Double = 4
    var iconSpacing: Double = 3
    var indexPadding: Double = 6
    var showDisplaySeparators: Bool = true
    var showAddSpaceButton: Bool = true
    var showPlaceholders: Bool = true
    var leftClickAction: GlyphStripAction = .focusSpace
    var rightClickAction: GlyphStripAction = .destroySpace
    var middleClickAction: GlyphStripAction = .none
    /// Placement on a display with a notch. Plain displays use
    /// `plainPosition` instead, so a notch anchor never parks the strip
    /// against a screen edge on a display that has no housing to anchor to.
    var position: GlyphStripPosition = .leftOfNotch
    /// Placement on a display without a notch. Centred by default.
    var plainPosition: GlyphStripPosition = .center
    var orientation: GlyphStripOrientation = .horizontal
    var verticalLayout: GlyphStripVerticalLayout = .inline
    /// Free-placement X on a display with a notch, as a fraction of the
    /// screen's spare width; only for `.custom`. 0 is the left edge, 1 the
    /// right edge.
    var customX: Double = 0.5
    /// Free-placement Y on a display with a notch; only for `.custom`. 0 is
    /// the bottom edge, 1 the top edge (AppKit grows upward).
    var customY: Double = 0.5
    /// Display the notch free placement belongs to, so the position survives
    /// monitor changes. Empty means no identity: the strip uses its usual
    /// target screen.
    var customScreen: String = ""
    /// Free-placement X on a display without a notch. Separate from the notch
    /// point so each screen type keeps its own physical position.
    var plainCustomX: Double = 0.5
    /// Free-placement Y on a display without a notch.
    var plainCustomY: Double = 0.5
    /// Display the plain free placement belongs to.
    var plainCustomScreen: String = ""
    /// One lock for both screen types. It applies wherever a display type
    /// resolves to `.custom`.
    var lockPosition: Bool = false
    var theme: String = ""
    var borderEnabled: Bool = true

    static let `default` = GlyphStripConfig()

    var resolvedHorizontalPadding: Double { lockPadding ? padding : horizontalPadding }
    var resolvedVerticalPadding: Double { lockPadding ? padding : verticalPadding }

    /// Placement and margin for a display, keyed on whether it has a notch.
    /// Notch anchors need the camera housing, so a plain display reads its own
    /// pair instead of collapsing to the screen edge.
    func placement(hasNotch: Bool) -> (position: GlyphStripPosition, margin: CGFloat) {
        hasNotch
            ? (position, CGFloat(margin))
            : (plainPosition, CGFloat(plainMargin))
    }

    /// Saved free-placement point and display identity for a screen type.
    func customPlacement(hasNotch: Bool) -> (x: Double, y: Double, screen: String) {
        hasNotch
            ? (customX, customY, customScreen)
            : (plainCustomX, plainCustomY, plainCustomScreen)
    }

    /// Stores a free-placement point for one screen type only.
    mutating func setCustomPlacement(
        hasNotch: Bool,
        x: Double,
        y: Double,
        screen: String
    ) {
        if hasNotch {
            customX = x
            customY = y
            customScreen = screen
        } else {
            plainCustomX = x
            plainCustomY = y
            plainCustomScreen = screen
        }
    }

    /// Stores the display identity for one screen type, keeping its point.
    mutating func setCustomScreen(_ screen: String, hasNotch: Bool) {
        if hasNotch {
            customScreen = screen
        } else {
            plainCustomScreen = screen
        }
    }

    /// True when the placement resolved for a display must not follow a drag.
    /// The lock itself is global and covers both screen types.
    func isPositionLocked(hasNotch: Bool) -> Bool {
        lockPosition && placement(hasNotch: hasNotch).position == .custom
    }

    func clamped() -> GlyphStripConfig {
        var copy = self
        copy.maxIconsPerSpace = min(max(maxIconsPerSpace, 0), 16)
        copy.iconSize = min(max(iconSize, 6), 24)
        copy.indexSize = min(max(indexSize, 6), 24)
        copy.glassClearVariant = min(max(glassClearVariant, 0), 21)
        copy.glassRegularVariant = min(max(glassRegularVariant, 0), 21)
        copy.glassTintedVariant = min(max(glassTintedVariant, 0), 21)
        copy.backgroundOpacity = min(max(backgroundOpacity, 0.01), 1)
        copy.glassClearOpacity = min(max(glassClearOpacity, 0.01), 1)
        copy.glassRegularOpacity = min(max(glassRegularOpacity, 0.01), 1)
        copy.glassTintedOpacity = min(max(glassTintedOpacity, 0.01), 1)
        copy.solidOpacity = min(max(solidOpacity, 0.01), 1)
        copy.cornerRadius = min(max(cornerRadius, 0), 40)
        copy.margin = min(max(margin, 0), 40)
        copy.plainMargin = min(max(plainMargin, 0), 40)
        copy.padding = min(max(padding, 0), 40)
        copy.horizontalPadding = min(max(horizontalPadding, 0), 40)
        copy.hoverPadding = min(max(hoverPadding, 0), 12)
        copy.hoverCornerRadius = min(max(hoverCornerRadius, 0), 20)
        copy.autoResizeMaxLength = min(max(autoResizeMaxLength, 0), 4000)
        copy.verticalPadding = min(max(verticalPadding, 0), 40)
        copy.iconSpacing = min(max(iconSpacing, 0), 20)
        copy.indexPadding = min(max(indexPadding, 0), 20)
        copy.customX = min(max(customX, 0), 1)
        copy.customY = min(max(customY, 0), 1)
        copy.plainCustomX = min(max(plainCustomX, 0), 1)
        copy.plainCustomY = min(max(plainCustomY, 0), 1)
        return copy
    }

    /// Effect opacity for a material, without the HUD's shared overall value.
    func effectiveBackgroundOpacity(for material: GlyphStripBackgroundMaterial) -> Double {
        switch material {
        case .none:
            return 0
        case .solid:
            return matchBackgroundOpacity ? backgroundOpacity : solidOpacity
        case .liquidGlass:
            let raw: Double
            if matchBackgroundOpacity {
                raw = backgroundOpacity
            } else {
                switch glassStyle {
                case .clear: raw = glassClearOpacity
                case .regular: raw = glassRegularOpacity
                case .tinted: raw = glassTintedOpacity
                }
            }
            return max(raw, glassStyle.minimumOpacity)
        }
    }

    /// Effect opacity after `matchHUDAppearance`, which copies the HUD's.
    func resolvedBackgroundOpacity(hud: SpacemapConfig) -> Double {
        if matchHUDAppearance {
            return hud.effectiveBackgroundOpacity(for: hud.backgroundStyle)
        }
        return effectiveBackgroundOpacity(for: backgroundMaterial)
    }

    /// Material actually drawn. Matching the HUD copies its style.
    func resolvedBackgroundMaterial(hud: SpacemapConfig) -> GlyphStripBackgroundMaterial {
        guard matchHUDAppearance else { return backgroundMaterial }
        return hud.backgroundStyle == .glass ? .liquidGlass : .solid
    }

    /// Glass sub-type actually drawn. Matching the HUD also copies its type.
    func resolvedGlassStyle(hud: SpacemapConfig) -> HUDGlassStyle {
        matchHUDAppearance ? hud.glassStyle : glassStyle
    }

    /// Material under the accent for tinted glass.
    func resolvedGlassTintedMaterial(hud: SpacemapConfig) -> HUDGlassMaterial {
        matchHUDAppearance ? hud.glassTintedMaterial : glassTintedMaterial
    }

    /// Private finish for the resolved glass style.
    func resolvedGlassVariant(hud: SpacemapConfig) -> Int {
        let style = resolvedGlassStyle(hud: hud)
        if matchHUDAppearance {
            switch style {
            case .clear: return hud.glassClearVariant
            case .regular: return hud.glassRegularVariant
            case .tinted: return hud.glassTintedVariant
            }
        }
        switch style {
        case .clear: return glassClearVariant
        case .regular: return glassRegularVariant
        case .tinted: return glassTintedVariant
        }
    }
}
