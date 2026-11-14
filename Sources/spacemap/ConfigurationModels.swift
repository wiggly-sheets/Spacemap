import Foundation
import CoreGraphics

enum HUDDisplayMode {
    case unified
    case separate
    case hidden
}

enum CellStyle: Int, CaseIterable, Identifiable, Equatable {
    case rects, hybrid, icons, thumbnails, simple
    var id: Int { rawValue }
}

enum HUDBackgroundStyle: String, CaseIterable, Identifiable, Codable, Equatable {
    case glass, solid
    var id: String { rawValue }

    /// Legacy `transparent` loads as solid: a solid fill at zero opacity is the
    /// same result, so the third style had no separate behaviour to keep.
    init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "glass": self = .glass
        case "solid", "transparent": self = .solid
        default: return nil
        }
    }
}
enum HUDGlassStyle: String, CaseIterable, Identifiable, Codable, Equatable {
    /// Left end of the native Liquid Glass scale: minimal backing.
    case clear
    /// Standard frosted material.
    case regular
    /// Accent tint over either material.
    case tinted

    var id: String { rawValue }

    /// Material the style draws with. Tinted picks its own material; clear and
    /// regular are fixed. Hard rename: `opaque` and `frosted` no longer decode.
    func material(tintedMaterial: HUDGlassMaterial) -> HUDGlassMaterial {
        switch self {
        case .clear: return .clear
        case .regular: return .regular
        case .tinted: return tintedMaterial
        }
    }

    /// Lowest opacity the style may render at. Glass below this reads as a
    /// flat desktop hole rather than glass, so the value is a floor, not a
    /// default. Tinted sits higher so its accent stays visible.
    var minimumOpacity: Double {
        switch self {
        case .clear: return 0.35
        case .regular: return 0.40
        case .tinted: return 0.45
        }
    }
}

/// The two native materials `NSGlassEffectView` exposes.
enum HUDGlassMaterial: String, CaseIterable, Identifiable, Equatable {
    case clear, regular
    var id: String { rawValue }
}

/// What the HUD's space cells draw behind their content when they do not match
/// the panel background.
enum SpacesBackgroundStyle: String, CaseIterable, Identifiable, Equatable {
    case none, solid, glass
    var id: String { rawValue }
}

enum ShowMode: String, CaseIterable, Identifiable, Equatable { case all, active; var id: String { rawValue } }
enum MultiMonitorHUDMode: String, CaseIterable, Identifiable, Equatable {
    case unified
    case separate

    var id: String { rawValue }

    func hudMode(for displayIndex: Int, in state: GridState) -> HUDDisplayMode {
        switch self {
        case .unified:
            return .unified
        case .separate:
            let spaces = state.spaces(forDisplay: displayIndex)
            return spaces.isEmpty ? .hidden : .separate
        }
    }
}
enum SeparateHUDVisibility: String, CaseIterable, Identifiable, Equatable {
    case all
    case active

    var id: String { rawValue }
}
enum DisplayNavigationWrap: String, CaseIterable, Identifiable, Equatable {
    case within
    case between

    var id: String { rawValue }
}
enum ThemeMode: String, CaseIterable, Identifiable, Equatable { case light, dark, auto; var id: String { rawValue } }
enum UpdateMode: String, CaseIterable, Identifiable, Equatable { case auto, notify, off; var id: String { rawValue } }
/// Update policy for the bundled sketchybar-app-font glyph font (distinct from
/// `UpdateMode`, which drives Sparkle app updates).
enum AppFontUpdateMode: String, CaseIterable, Identifiable, Equatable {
    case manual
    case auto

    var id: String { rawValue }
}
enum AppPresence: String, CaseIterable, Identifiable, Equatable {
    case dock = "dock"
    case menuBar = "menuBar"
    case both = "both"
    case none = "none"

    var id: String { rawValue }

    var showsMenuBar: Bool { self == .menuBar || self == .both }
    var showsDock: Bool { self == .dock || self == .both }
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Equatable {
    case icon
    case dots
    case current
    case nearby
    case all

    var id: String { rawValue }
}
enum WindowDropFocusMode: String, CaseIterable, Identifiable, Equatable {
    case never
    case always
    case modifier

    var id: String { rawValue }

    func shouldFocus(
        eventFlags: CGEventFlags,
        requiredModifier: WindowDropFocusModifier
    ) -> Bool {
        switch self {
        case .never: return false
        case .always: return true
        case .modifier: return eventFlags.contains(requiredModifier.eventFlag)
        }
    }
}
enum WindowDropFocusModifier: String, CaseIterable, Identifiable, Equatable {
    case command
    case function = "fn"
    case option
    case control
    case shift

    var id: String { rawValue }

    var eventFlag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .function: return .maskSecondaryFn
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .shift: return .maskShift
        }
    }
}

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

enum GlyphStripShape: String, CaseIterable, Identifiable, Equatable {
    /// No background shape — just glyphs. Border can still be enabled.
    case none
    /// Fully rounded ends — a capsule.
    case pill
    /// Explicit radius from `cornerRadius`, capped to half the strip height.
    case roundedRect
    /// Square ends — one continuous bar.
    case bar

    var id: String { rawValue }
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

enum GlyphStripPosition: String, CaseIterable, Identifiable, Equatable {
    case leftOfNotch
    case rightOfNotch
    case center
    /// Free placement: `xOffset` points right of the menu bar row's left edge.
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

/// Settings for the always-visible menu-bar glyph strip (theme-driven colours).
/// `[glyphStrip]` table, strip only; HUD cells use `GridConfig.showSpaceNumbers`.
struct GlyphStripConfig: Equatable {
    var enabled: Bool = false
    /// Hide the strip while another app is in native fullscreen, so the strip
    /// never floats over a fullscreen window or its menu bar reveal.
    var hideInFullscreen: Bool = false
    var showSpaceNumbers: Bool = true
    var showLayoutSuffix: Bool = true
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
    var shape: GlyphStripShape = .none
    var cornerRadius: Double = 20
    var margin: Double = 6
    var hoverPadding: Double = 1
    var hoverCornerRadius: Double = 4
    var iconSpacing: Double = 3
    var indexPadding: Double = 6
    var showDisplaySeparators: Bool = true
    var showAddSpaceButton: Bool = true
    var showPlaceholders: Bool = true
    var leftClickAction: GlyphStripAction = .focusSpace
    var rightClickAction: GlyphStripAction = .destroySpace
    var middleClickAction: GlyphStripAction = .none
    var position: GlyphStripPosition = .leftOfNotch
    var orientation: GlyphStripOrientation = .horizontal
    var verticalLayout: GlyphStripVerticalLayout = .inline
    /// Free-placement X, from the screen's left edge; only for `.custom`.
    var xOffset: Int = 0
    /// Anchored nudge down from the row; custom inset from the screen top.
    var yOffset: Double = 0
    var lockPosition: Bool = false
    var theme: String = ""
    var borderEnabled: Bool = true

    static let `default` = GlyphStripConfig()

    /// True when the current placement must not follow a drag.
    var isPositionLocked: Bool { position == .custom && lockPosition }

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
        copy.hoverPadding = min(max(hoverPadding, 0), 12)
        copy.hoverCornerRadius = min(max(hoverCornerRadius, 0), 20)
        copy.iconSpacing = min(max(iconSpacing, 0), 20)
        copy.indexPadding = min(max(indexPadding, 0), 20)
        copy.xOffset = min(max(xOffset, -4000), 4000)
        copy.yOffset = position == .custom
            ? min(max(yOffset, 0), 4000)
            : min(max(yOffset, -10), 10)
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
    func resolvedBackgroundOpacity(hud: GridConfig) -> Double {
        if matchHUDAppearance {
            return hud.effectiveBackgroundOpacity(for: hud.backgroundStyle)
        }
        return effectiveBackgroundOpacity(for: backgroundMaterial)
    }

    /// Material actually drawn. Matching the HUD copies its style.
    func resolvedBackgroundMaterial(hud: GridConfig) -> GlyphStripBackgroundMaterial {
        guard matchHUDAppearance else { return backgroundMaterial }
        return hud.backgroundStyle == .glass ? .liquidGlass : .solid
    }

    /// Glass sub-type actually drawn. Matching the HUD also copies its type.
    func resolvedGlassStyle(hud: GridConfig) -> HUDGlassStyle {
        matchHUDAppearance ? hud.glassStyle : glassStyle
    }

    /// Material under the accent for tinted glass.
    func resolvedGlassTintedMaterial(hud: GridConfig) -> HUDGlassMaterial {
        matchHUDAppearance ? hud.glassTintedMaterial : glassTintedMaterial
    }

    /// Private finish for the resolved glass style.
    func resolvedGlassVariant(hud: GridConfig) -> Int {
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

    /// Theme actually painted. Empty means follow the HUD.
    func resolvedThemeName(hud: GridConfig) -> String {
        if matchHUDAppearance { return hud.theme }
        return theme.isEmpty ? hud.theme : theme
    }
}

enum HUDPosition: Equatable, Hashable {
    case center, top, bottom
    case custom(x: Double, y: Double)

    static let allPresets: [HUDPosition] = [.center, .top, .bottom]

    var label: String {
        switch self {
        case .center: return "Center"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .custom: return "Custom"
        }
    }

    

    func point(for panelSize: CGSize, screen: CGRect) -> CGPoint {
        let x: CGFloat
        let y: CGFloat
        switch self {
        case .center:
            x = screen.midX - panelSize.width / 2
            y = screen.midY - panelSize.height / 2
        case .top:
            x = screen.midX - panelSize.width / 2
            y = screen.maxY - panelSize.height - 40
        case .bottom:
            x = screen.midX - panelSize.width / 2
            y = screen.minY + 40
        case .custom(let px, let py):
            x = screen.minX + (screen.width - panelSize.width) * px
            y = screen.minY + (screen.height - panelSize.height) * py
        }
        return CGPoint(x: x, y: y)
    }
}
enum HUDPositionKind: String, CaseIterable {
    case center, top, bottom, custom

    init(from position: HUDPosition) {
        switch position {
        case .center: self = .center
        case .top: self = .top
        case .bottom: self = .bottom
        case .custom: self = .custom
        }
    }
}

struct HotkeyConfig: Equatable {
    var key: HotkeyKey
    var modifiers: CGEventFlags

    static let `default` = HotkeyConfig(key: .keyCode(121), modifiers: .maskControl)

    var keyCode: CGKeyCode? {
        if case .keyCode(let code) = key { return code }
        return nil
    }

    var mediaKey: MediaKey? {
        if case .mediaKey(let key) = key { return key }
        return nil
    }

    var isDisabled: Bool {
        if case .none = key { return true }
        return false
    }
}

enum HotkeyKey: Equatable {
    case none
    case keyCode(CGKeyCode)
    case mediaKey(MediaKey)
}

enum MediaKey: String, Codable, CaseIterable, Equatable {
    case playPause = "play-pause"
    case nextTrack = "next-track"
    case previousTrack = "previous-track"
    case volumeUp = "volume-up"
    case volumeDown = "volume-down"
    case mute = "mute"
    case brightnessUp = "brightness-up"
    case brightnessDown = "brightness-down"
}

/// `[appFont]` table: how the glyph font gets updated, plus install state so
/// auto mode does not re-download the release every launch.
struct AppFontConfig: Equatable {
    var updateMode: AppFontUpdateMode = .manual
    /// Release tag of the last font installed by the updater, e.g. "v3.0.5".
    /// Empty = only the bundled copy exists.
    var installedVersion: String = ""
    /// Unix epoch of the last release check, 0 = never checked.
    var lastCheck: Int = 0

    static let `default` = AppFontConfig()
}

struct SpaceNameProfile: Equatable, Identifiable {
    var id = UUID()
    var name: String
    var spaceNames: [Int: String] = [:]

    static let `default` = SpaceNameProfile(name: "Default", spaceNames: [:])
}

struct GridConfig: Equatable {
    var cols: Int
    var rows: Int
    var cellStyle: CellStyle
    var hotkey: HotkeyConfig
    var pinnedHotkey: HotkeyConfig = HotkeyConfig(key: .none, modifiers: [])
    /// Show/hide hotkey for the menu-bar glyph strip. `.none` = unbound.
    var glyphStripHotkey: HotkeyConfig = HotkeyConfig(key: .none, modifiers: [])
    var socketHealthInterval: Int
    var uiScale: Double
    var autoHideTimeout: Int
    var theme: String
    var showMode: ShowMode
    var multiMonitorHUDMode: MultiMonitorHUDMode
    var unifiedHUDVisibility: SeparateHUDVisibility
    var separateHUDVisibility: SeparateHUDVisibility
    var displayNavigationWrap: DisplayNavigationWrap
    var maxSpaces: Int
    /// HUD overlay translucency 0...1. Not the strip fill — that is
    /// `GlyphStripConfig.backgroundOpacity` under `[glyphStrip]`.
    var backgroundAlpha: Double
    /// HUD background style, independent of the theme.
    var backgroundStyle: HUDBackgroundStyle = .glass
    /// Glass sub-type, only read when `backgroundStyle == .glass`.
    var glassStyle: HUDGlassStyle = .regular
    /// Private `NSGlassEffectView._variant` finish per glass style, 0...21.
    var glassClearVariant: Int = 11
    var glassRegularVariant: Int = 5
    var glassTintedVariant: Int = 2
    /// Material tinted glass draws over; tint is the theme accent.
    var glassTintedMaterial: HUDGlassMaterial = .clear
    /// Per-style background opacities. Used unless `matchBackgroundOpacity`.
    var glassClearOpacity: Double = 0.05
    var glassRegularOpacity: Double = 0.3
    var glassTintedOpacity: Double = 0.3
    var solidOpacity: Double = 1.0
    /// Space cells copy the panel background unless this is false.
    var spacesMatchBackground: Bool = true
    var spacesBackgroundStyle: SpacesBackgroundStyle = .glass
    var spacesGlassStyle: HUDGlassStyle = .clear
    var spacesGlassClearVariant: Int = 11
    var spacesGlassRegularVariant: Int = 5
    var spacesGlassTintedVariant: Int = 2
    var spacesGlassTintedMaterial: HUDGlassMaterial = .clear
    var spacesOpacity: Double = 0.5
    var spacesCornerRadius: Double = 4
    /// When true, every style shares `backgroundAlpha` instead of its own value.
    var matchBackgroundOpacity: Bool = false
    var hudShadow: Bool = true
    /// Corner radius of the HUD's outer panel, not the space cells.
    var hudCornerRadius: Double = 10
    var mode: ThemeMode
    var iconScale: Double
    /// HUD cells' space-index toggle. The strip reads
    /// `GlyphStripConfig.showSpaceNumbers` under `[glyphStrip]`.
    var showSpaceNumbers: Bool
    var showSpaceLayout: Bool = false
    var showSpaceNames: Bool
    var showIconStrip: Bool
    var showMultiAppIcons: Bool
    /// Where Spacemap appears outside the HUD: dock, menu bar, both, or neither.
    var presence: AppPresence = .menuBar
    var glyphStrip: GlyphStripConfig = .default
    var menuBarDisplayMode: MenuBarDisplayMode = .icon
    var menuBarNearbyCount: Int = 3
    var spaceNames: [Int: String]
    var useVimKeys: Bool
    var useArrowKeys: Bool
    var useExtendedKeys: Bool = true
    var jumpToSpaceEnabled: Bool = false
    var hudPosition: HUDPosition
    var customHUDX: Double = 0.5
    var customHUDY: Double = 0.5
    var showExtraWindows: Bool
    var focusSpaceOnWindowDrop: WindowDropFocusMode = .never
    var focusSpaceOnWindowDropModifier: WindowDropFocusModifier = .command
    var showHUDOnSpaceChange: Bool = false
    /// Which layout letters the HUD badge shows. Read only when
    /// `showSpaceLayout` is on; the default keeps every letter.
    var showBSPLayoutBadge: Bool = true
    var showStackLayoutBadge: Bool = true
    var showFloatLayoutBadge: Bool = true
    /// Draw number and action notices over the HUD. Actions still run when off.
    var showHUDInteractionFeedback: Bool = true
    /// Draw the desktop wallpaper behind thumbnail cells. Off renders windows
    /// over a transparent background, which is easier to read on busy desktops.
    var showThumbnailWallpaper: Bool = true
    /// Fade panels and animate cell changes. Off keeps every HUD change instant.
    var hudAnimationsEnabled: Bool = true
    var hudAnimationStyle: HUDAnimationStyle = .natural
    var updateMode: UpdateMode
    var appFont: AppFontConfig = .default
    /// Refuse to execute a yabai binary that fails the ownership/signature
    /// trust check. Default false: warn-only so legit installs never brick.
    var refuseUntrustedYabai: Bool = false

    /// Opacity for the active background style. Shared when the user opts to
    /// match all styles, otherwise each style keeps its own remembered value.
    /// Glass never renders below its style's minimum: at zero the effect would
    /// be a flat hole instead of glass. Solid may go fully transparent.
    func effectiveBackgroundOpacity(for style: HUDBackgroundStyle) -> Double {
        switch style {
        case .solid:
            return matchBackgroundOpacity ? backgroundAlpha : solidOpacity
        case .glass:
            let raw: Double
            if matchBackgroundOpacity {
                raw = backgroundAlpha
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

    /// Space name profiles — each stores a set of space names and a glyph strip config.
    var spaceNameProfiles: [SpaceNameProfile] = [SpaceNameProfile.default]
    /// Index of the currently active space name profile.
    var activeSpaceNameProfileIndex: Int = 0

    static let `default` = GridConfig(
        cols: 8, rows: 2, cellStyle: .rects, hotkey: .default,
        pinnedHotkey: HotkeyConfig(key: .none, modifiers: []),
        socketHealthInterval: 60, uiScale: 0.5, autoHideTimeout: 5,
        theme: "default", showMode: .all, multiMonitorHUDMode: .unified,
        unifiedHUDVisibility: .active, separateHUDVisibility: .all,
        displayNavigationWrap: .within, maxSpaces: 16, backgroundAlpha: 0.3,
        backgroundStyle: .glass, glassStyle: .regular, hudShadow: true,
        mode: .auto, iconScale: 0.5, showSpaceNumbers: true,
        showSpaceNames: true, showIconStrip: true, showMultiAppIcons: false,
        presence: .menuBar, glyphStrip: .default, menuBarDisplayMode: .icon,
        menuBarNearbyCount: 3, spaceNames: [:], useVimKeys: false,
        useArrowKeys: false, jumpToSpaceEnabled: false, hudPosition: .center, customHUDX: 0.5,
        customHUDY: 0.5, showExtraWindows: false,
        focusSpaceOnWindowDrop: .never, focusSpaceOnWindowDropModifier: .command,
        showHUDOnSpaceChange: false,
        showBSPLayoutBadge: true,
        showStackLayoutBadge: true,
        showFloatLayoutBadge: true,
        showHUDInteractionFeedback: true,
        showThumbnailWallpaper: true,
        hudAnimationsEnabled: true,
        hudAnimationStyle: .natural,
        updateMode: .notify
    )
}
