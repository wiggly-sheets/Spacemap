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

enum GlyphStripGlassAmount {
    /// Clear glass at/below this amount: no tint, fill overlay at its floor.
    static let clearThreshold: Double = 0.02
    /// System Settings > Appearance > Liquid Glass centre notch.
    static let `default`: Double = 0.5
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

/// Settings for the always-visible menu-bar glyph strip.
///
/// Appearance is theme-driven. The strip resolves a fixed role palette against
/// its theme (or the main HUD's when `theme` is empty): the current space, the
/// add button and the hover highlight use `focused`, resting glyphs use `text`,
/// and the solid material fills with `cellBg`. There are no per-element colour
/// keys.
/// `[glyphStrip]` table: the always-visible menu-bar strip. Scoped to the
/// strip only — `GridConfig.showSpaceNumbers` is the separate HUD-cells key
/// with the same TOML name under `[grid]`; the two do not interact.
struct GlyphStripConfig: Equatable {
    var enabled: Bool = false
    /// Strip's own space-index toggle. HUD cells read `GridConfig.showSpaceNumbers`.
    var showSpaceNumbers: Bool = true
    var showLayoutSuffix: Bool = true
    var showAppIcons: Bool = true
    var dedupeAppsPerSpace: Bool = true
    var maxIconsPerSpace: Int = 8
    var iconSize: Double = 11
    var indexSize: Double = 11
    var highlightCurrentSpace: Bool = true
    /// What sits behind the glyphs: nothing, a flat `cellBg` fill, or the
    /// native glass layer.
    var backgroundMaterial: GlyphStripBackgroundMaterial = .none
    /// Continuous glass tint, 0 = ultraclear, 1 = opaque/tinted. Only read
    /// when `backgroundMaterial == .liquidGlass`. Mirrors the System
    /// Settings > Appearance > Liquid Glass slider (centre default).
    var glassAmount: Double = 0.5
    /// When true the glass tints with the theme/backdrop color; when false
    /// the glass stays neutral (no hue, frost only). Only read when
    /// `backgroundMaterial == .liquidGlass`.
    var useThemeTint: Bool = true
    /// Outline the material is drawn in. With material `.none` it shapes the border.
    var shape: GlyphStripShape = .none
    /// HUD translucency 0...1 for the grid overlay. The strip's own fill key
    /// is `GlyphStripConfig.backgroundOpacity` (solid material only) — the
    /// names differ because the scopes differ.
    var backgroundOpacity: Double = 0.35
    var cornerRadius: Double = 20
    /// Gap between the strip and the notch edge it hugs, in points.
    var margin: Double = 6
    /// Vertical nudge in screen-reading terms: positive moves the strip DOWN into
    /// the screen interior, away from the menu bar's top edge.
    var yOffset: Double = 0
    /// Gap grown around the hovered segment's glyphs, on both axes, in points.
    var hoverPadding: Double = 1
    /// Corner radius of the hover highlight. Separate from `cornerRadius`, which
    /// shapes the background.
    var hoverCornerRadius: Double = 4
    /// Extra advance inserted between two adjacent app glyphs and before the
    /// +N overflow. Not applied around separators, nor between the space
    /// index and the first glyph — that gap is `indexPadding`.
    var iconSpacing: Double = 3
    /// Gap between a space's index number and its first app glyph or placeholder.
    var indexPadding: Double = 6
    var showDisplaySeparators: Bool = true
    var showAddSpaceButton: Bool = true
    var showPlaceholders: Bool = true
    var leftClickAction: GlyphStripAction = .focusSpace
    var rightClickAction: GlyphStripAction = .destroySpace
    var middleClickAction: GlyphStripAction = .none
    var position: GlyphStripPosition = .leftOfNotch
    /// Horizontal offset in points from the menu bar row's left edge, used only
    /// when `position == .custom`.
    var xOffset: Int = 0
    /// Draw the hairline border around the strip. Independent of the
    /// background: with no background it follows the selected shape; shape `.none` = no outline.
    var borderEnabled: Bool = true
    /// Theme for the strip's own colours, or `""` to follow the main HUD's
    /// `GridConfig.theme`.
    var theme: String = ""

    static let `default` = GlyphStripConfig()

    /// Numeric ranges are enforced here so a hand-edited TOML cannot push the
    /// panel into a degenerate layout, independent of what the UI allows.
    func clamped() -> GlyphStripConfig {
        var copy = self
        copy.maxIconsPerSpace = min(max(maxIconsPerSpace, 0), 16)
        copy.iconSize = min(max(iconSize, 6), 24)
        copy.indexSize = min(max(indexSize, 6), 24)
        copy.backgroundOpacity = min(max(backgroundOpacity, 0.01), 1)
        copy.glassAmount = min(max(glassAmount, 0), 1)
        copy.cornerRadius = min(max(cornerRadius, 0), 40)
        copy.margin = min(max(margin, 0), 40)
        copy.iconSpacing = min(max(iconSpacing, 0), 20)
        copy.indexPadding = min(max(indexPadding, 0), 20)
        copy.yOffset = min(max(yOffset, -10), 10)
        // Only meaningful once the frame clamp pins the strip inside the row,
        // but bounded so a hand-edited config cannot hold a silly number.
        copy.xOffset = min(max(xOffset, -4000), 4000)
        copy.hoverPadding = min(max(hoverPadding, 0), 12)
        copy.hoverCornerRadius = min(max(hoverCornerRadius, 0), 20)
        return copy
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
    var hudShadow: Bool = true
    var mode: ThemeMode
    var iconScale: Double
    /// HUD cells' space-index toggle. The strip reads
    /// `GlyphStripConfig.showSpaceNumbers` under `[glyphStrip]`.
    var showSpaceNumbers: Bool
    var showSpaceNames: Bool
    var showIconStrip: Bool
    var showMultiAppIcons: Bool
    var hideMenuBarIcon: Bool
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
    var updateMode: UpdateMode
    var appFont: AppFontConfig = .default

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
        displayNavigationWrap: .within, maxSpaces: 16, backgroundAlpha: 0.3, hudShadow: true,
        mode: .auto, iconScale: 0.5, showSpaceNumbers: true,
        showSpaceNames: true, showIconStrip: true, showMultiAppIcons: false,
        hideMenuBarIcon: false, glyphStrip: .default, menuBarDisplayMode: .icon,
        menuBarNearbyCount: 3, spaceNames: [:], useVimKeys: false,
        useArrowKeys: false, jumpToSpaceEnabled: false, hudPosition: .center, customHUDX: 0.5,
        customHUDY: 0.5, showExtraWindows: false,
        focusSpaceOnWindowDrop: .never, focusSpaceOnWindowDropModifier: .command,
        showHUDOnSpaceChange: false,
        updateMode: .notify
    )
}
