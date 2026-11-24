import Foundation
import CoreGraphics


extension SpacemapConfig {
    /// The legacy `[behavior]` HUD hotkeys, still decoded for older configs.
    var legacyHUDHotkeys: [HUDCommand: HotkeyConfig] {
        [
            .moveSpaceBack: hudMoveSpaceBackHotkey,
            .moveSpaceForward: hudMoveSpaceForwardHotkey,
            .newSpace: hudNewSpaceHotkey,
            .deleteSpace: hudDeleteSpaceHotkey,
            .cycleLayout: hudCycleLayoutHotkey
        ]
    }

    /// The one map HUD input matches: legacy scalars first, then `[hudKeys]`.
    var hudKeyBindings: HUDKeyBindings {
        hudKeys.withLegacy(legacyHUDHotkeys)
    }
}

/// `[appFont]` table: how the glyph font gets updated, plus install state so
/// auto mode does not re-download the release every launch.
struct AppFontConfig: Equatable {
    /// Auto by default: the bundled ttf is a fallback, and a fresh install
    /// should not stay on an old glyph set until someone opens Settings.
    var updateMode: AppFontUpdateMode = .auto
    /// Release tag of the last font installed by the updater, e.g. "v3.0.5".
    /// Empty = only the bundled copy exists.
    var installedVersion: String = ""
    /// Unix epoch of the last release check, 0 = never checked.
    var lastCheck: Int = 0

    static let `default` = AppFontConfig()
}

/// Where a space's displayed name comes from: the active profile's typed names,
/// or the apps of the space's visible windows in reading order. Auto names are
/// computed on read and never written to `[spaceNames.names]`.
enum SpaceNamingMode: String, CaseIterable, Identifiable, Equatable {
    case custom
    case auto

    var id: String { rawValue }
}

struct SpaceNameProfile: Equatable, Identifiable {
    var id = UUID()
    var name: String
    var spaceNames: [Int: String] = [:]

    static let `default` = SpaceNameProfile(name: "Default", spaceNames: [:])
}

struct SpacemapConfig: Equatable {
    var cols: Int
    var rows: Int
    var cellStyle: CellStyle
    var hotkey: HotkeyConfig
    var pinnedHotkey: HotkeyConfig = HotkeyConfig(key: .none, modifiers: [])
    /// Show/hide hotkey for the menu-bar glyph strip. `.none` = unbound.
    var glyphStripHotkey: HotkeyConfig = HotkeyConfig(key: .none, modifiers: [])
    /// Move the focused space one slot left/right while the HUD is open.
    var hudMoveSpaceBackHotkey: HotkeyConfig = HotkeyConfig(key: .none, modifiers: [])
    var hudMoveSpaceForwardHotkey: HotkeyConfig = HotkeyConfig(key: .none, modifiers: [])
    /// Create, destroy, and cycle the focused space's layout while the HUD is open.
    var hudNewSpaceHotkey: HotkeyConfig = HotkeyConfig(key: .none, modifiers: [])
    var hudDeleteSpaceHotkey: HotkeyConfig = HotkeyConfig(key: .none, modifiers: [])
    var hudCycleLayoutHotkey: HotkeyConfig = HotkeyConfig(key: .none, modifiers: [])
    /// Navigation and HUD actions while the HUD is open.
    var hudKeys: HUDKeyBindings = .default
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
    /// Empty uses the system font. The font panel stores the family name and
    /// the space-number point size; other HUD text scales from it.
    var hudFontName: String = ""
    var hudFontSize: Double = 12
    /// Empty follows the theme's text colour. A hex value overrides text in
    /// the HUD so dark or low-contrast themes stay readable.
    var hudTextColor: String = ""
    var mode: ThemeMode
    var iconScale: Double
    /// HUD cells' space-index toggle. The strip reads
    /// `GlyphStripConfig.showSpaceNumbers` under `[glyphStrip]`.
    var showSpaceNumbers: Bool
    var showSpaceLayout: Bool = false
    var showSpaceNames: Bool
    var showIconStrip: Bool
    var showMultiAppIcons: Bool
    /// HUD app icons: native macOS images or the bundled-lookup app-font glyphs.
    var hudIconSource: GlyphStripIconSource
    /// Opt-in separate icon source for the HUD icon strip. Off by default, so
    /// the strip follows `hudIconSource`.
    var hudIconStripSeparate: Bool = false
    var hudIconStripSource: GlyphStripIconSource = .nativeIcons
    /// Where Spacemap appears outside the HUD: dock, menu bar, both, or neither.
    var presence: AppPresence = .menuBar
    var glyphStrip: GlyphStripConfig = .default
    var menuBarDisplayMode: MenuBarDisplayMode = .icon
    var menuBarNearbyCount: Int = 3
    var spaceNames: [Int: String]
    /// Displayed names: the profile's typed names, or each space's visible apps.
    var namingMode: SpaceNamingMode = .custom
    /// How many apps auto naming lists per space, 1-3, joined by "·".
    var autoNameAppCount: Int = 3
    var jumpToSpaceEnabled: Bool = false
    /// Letters typed while the HUD is open fuzzy-match space names. Effective
    /// only when space names are shown, so hiding them turns this off too.
    var fuzzySpaceJumpEnabled: Bool = true
    var effectiveFuzzySpaceJumpEnabled: Bool {
        fuzzySpaceJumpEnabled && showSpaceNames
    }
    var hudPosition: HUDPosition
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
    /// What dropping a dragged space does: swap window contents, or move the
    /// spaces themselves.
    var spaceDropMode: SpaceDropMode = .content
    /// Focus after dragging a space.
    var spaceDragFocus: DragFocusMode = .stay
    /// Focus after dragging an app icon to another space.
    var windowDragFocus: DragFocusMode = .destination
    /// Draw the desktop wallpaper behind thumbnail cells. Off renders windows
    /// over a transparent background, which is easier to read on busy desktops.
    var showThumbnailWallpaper: Bool = true
    /// Fade panels and animate cell changes. Off keeps every HUD change instant.
    var hudAnimationsEnabled: Bool = true
    var hudAnimationStyle: HUDAnimationStyle = .natural
    var hudEntranceStyle: HUDEntranceStyle = .fade
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

    static let `default` = SpacemapConfig(
        cols: 8, rows: 2, cellStyle: .rects, hotkey: .default,
        pinnedHotkey: HotkeyConfig(key: .none, modifiers: []),
        socketHealthInterval: 60, uiScale: 0.5, autoHideTimeout: 5,
        theme: "default", showMode: .all, multiMonitorHUDMode: .unified,
        unifiedHUDVisibility: .active, separateHUDVisibility: .all,
        displayNavigationWrap: .within, maxSpaces: 16, backgroundAlpha: 0.3,
        backgroundStyle: .glass, glassStyle: .regular, hudShadow: true,
        hudFontName: "", hudFontSize: 12, hudTextColor: "",
        mode: .auto, iconScale: 0.5, showSpaceNumbers: true,
        showSpaceNames: true, showIconStrip: true, showMultiAppIcons: false,
        hudIconSource: .nativeIcons, hudIconStripSeparate: false,
        hudIconStripSource: .nativeIcons,
        presence: .menuBar, glyphStrip: .default, menuBarDisplayMode: .icon,
        menuBarNearbyCount: 3, spaceNames: [:], jumpToSpaceEnabled: false, hudPosition: .center,
        showExtraWindows: false,
        focusSpaceOnWindowDrop: .never, focusSpaceOnWindowDropModifier: .command,
        showHUDOnSpaceChange: false,
        showBSPLayoutBadge: true,
        showStackLayoutBadge: true,
        showFloatLayoutBadge: true,
        showHUDInteractionFeedback: true,
        spaceDropMode: .content,
        spaceDragFocus: .stay,
        windowDragFocus: .destination,
        showThumbnailWallpaper: true,
        hudAnimationsEnabled: true,
        hudAnimationStyle: .natural,
        hudEntranceStyle: .fade,
        updateMode: .notify
    )
}

extension SpacemapConfig {
    /// The icon strip can use its own source while cell styles keep
    /// `hudIconSource`; separate mode is off by default.
    var resolvedHUDIconStripSource: GlyphStripIconSource {
        hudIconStripSeparate ? hudIconStripSource : hudIconSource
    }

    /// The menu bar preview and the strip are the only surfaces that need
    /// workspace membership; skip yabai queries when both are off.
    var needsWorkspacePreviews: Bool {
        glyphStrip.enabled || (presence.showsMenuBar && menuBarDisplayMode != .icon)
    }

    var needsWindowGeometryPreviews: Bool {
        glyphStrip.enabled || (needsWorkspacePreviews && menuBarDisplayMode != .dots)
    }
}
