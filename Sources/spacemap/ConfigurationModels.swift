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
/// What a dragged space does when it lands on another space.
enum SpaceDropMode: String, CaseIterable, Identifiable, Equatable {
    /// Swap the windows between the two spaces. Works with any yabai build.
    case content
    /// Reorder the spaces themselves. Needs a yabai build that can move
    /// spaces on this macOS version.
    case spaces

    var id: String { rawValue }

    var label: String {
        switch self {
        case .content: return "Swap Contents"
        case .spaces: return "Move Spaces"
        }
    }
}

/// Where focus goes after a drag moves an app or rearranges spaces.
enum DragFocusMode: String, CaseIterable, Identifiable, Equatable {
    case stay
    case destination
    case source

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stay: return "Stay"
        case .destination: return "Dropped-On Space"
        case .source: return "Original Space"
        }
    }
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

enum HUDPosition: Equatable, Hashable {
    case center, top, bottom
    /// Fraction of the screen's spare width/height plus the display it was
    /// dragged on. `screen` is nil when the position has no display pairing.
    case custom(x: Double, y: Double, screen: String?)

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
        case .custom(let px, let py, _):
            x = screen.minX + (screen.width - panelSize.width) * px
            y = screen.minY + (screen.height - panelSize.height) * py
        }
        return CGPoint(x: x, y: y)
    }

    /// Display identity of a custom position, nil for presets and for custom
    /// positions saved before the screen pairing existed.
    var screenIdentifier: String? {
        guard case .custom(_, _, let screen) = self else { return nil }
        return screen
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

/// One configurable HUD key action. The raw value is the `[hudKeys]` TOML key.
enum HUDCommand: String, CaseIterable, Equatable {
    case left, right, up, down
    case first, last, recent, close
    case newSpace, newSpaceAndFocus, deleteSpace
    case layoutBSP, layoutStack, layoutFloat
    case cycleLayout, moveSpaceBack, moveSpaceForward
    case previousSpace, nextSpace

    /// Display name. Settings is the only place these are shown.
    var label: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .up: return "Up"
        case .down: return "Down"
        case .first: return "First Space"
        case .last: return "Last Space"
        case .recent: return "Recent Space"
        case .close: return "Close HUD"
        case .newSpace: return "New Space"
        case .newSpaceAndFocus: return "New Space and Focus"
        case .deleteSpace: return "Delete Space"
        case .layoutBSP: return "BSP Layout"
        case .layoutStack: return "Stack Layout"
        case .layoutFloat: return "Float Layout"
        case .cycleLayout: return "Cycle Layout"
        case .moveSpaceBack: return "Move Space Left"
        case .moveSpaceForward: return "Move Space Right"
        case .previousSpace: return "Previous Space"
        case .nextSpace: return "Next Space"
        }
    }
}

/// One map for every HUD key action: `[hudKeys]` plus the legacy `[behavior]`
/// scalar keys, which are matched before the table like they always were.
struct HUDKeyBindings: Equatable {
    private var keys: [HUDCommand: [HotkeyConfig]]
    /// Dissolved `[behavior]` scalar keys. Matched before `keys`.
    private var legacy: [HUDCommand: HotkeyConfig]

    init(
        _ keys: [HUDCommand: [HotkeyConfig]] = [:],
        legacy: [HUDCommand: HotkeyConfig] = [:]
    ) {
        // Empty lists are the same as unbound, so they are never stored: a
        // decoded `[]` must equal a map that never had the entry.
        self.keys = keys.filter { !$0.value.isEmpty }
        self.legacy = legacy.filter { !$0.value.isDisabled }
    }

    subscript(command: HUDCommand) -> [HotkeyConfig] {
        get { keys[command] ?? [] }
        set {
            if newValue.isEmpty {
                keys.removeValue(forKey: command)
            } else {
                keys[command] = newValue
            }
        }
    }

    /// Original `[behavior]` check order, kept so a scalar key still wins.
    static let legacyOrder: [HUDCommand] = [
        .moveSpaceBack, .moveSpaceForward, .newSpace, .deleteSpace, .cycleLayout
    ]

    /// Legacy scalar keys as the first-match layer over this table.
    func withLegacy(_ legacy: [HUDCommand: HotkeyConfig]) -> HUDKeyBindings {
        HUDKeyBindings(keys, legacy: legacy)
    }

    /// The same map with the legacy scalars folded into their commands, so a
    /// settings save keeps them once the scalar keys are written unbound.
    func foldingLegacy() -> HUDKeyBindings {
        var folded = self
        for command in Self.legacyOrder {
            guard let hotkey = legacy[command] else { continue }
            let existing = folded.keys[command] ?? []
            // The folded map is written back on save, so a scalar that already
            // matches a table binding must not add a second identical row.
            let identity = Hotkey.bindingIdentity(hotkey)
            if existing.contains(where: { Hotkey.bindingIdentity($0) == identity }) { continue }
            folded.keys[command] = [hotkey] + existing
        }
        folded.legacy = [:]
        return folded
    }

    /// First matching command overall: legacy scalars, then the table.
    func command(for keyCode: CGKeyCode, flags: CGEventFlags) -> HUDCommand? {
        legacyCommand(for: keyCode, flags: flags) ?? tableCommand(for: keyCode, flags: flags)
    }

    /// First matching legacy scalar key, in its original check order.
    func legacyCommand(for keyCode: CGKeyCode, flags: CGEventFlags) -> HUDCommand? {
        Self.legacyOrder.first {
            legacy[$0]?.matches(keyCode: keyCode, flags: flags) == true
        }
    }

    /// First matching `[hudKeys]` binding.
    func tableCommand(for keyCode: CGKeyCode, flags: CGEventFlags) -> HUDCommand? {
        HUDCommand.allCases.first { command in
            self[command].contains { $0.matches(keyCode: keyCode, flags: flags) }
        }
    }

    private static func key(_ name: String) -> HotkeyConfig {
        Hotkey.parseHotkey(name) ?? HotkeyConfig(key: .none, modifiers: [])
    }

    /// Vim and arrow defaults. Editing one action does not touch the others.
    static let `default` = HUDKeyBindings([
        .left: [key("h"), key("left")],
        .right: [key("l"), key("right")],
        .up: [key("k"), key("up")],
        .down: [key("j"), key("down")],
        .first: [key("f")],
        .last: [key("e")],
        .recent: [key("r")],
        .close: [key("escape"), key("c")],
        .newSpace: [key("a")],
        .newSpaceAndFocus: [key("t")],
        .deleteSpace: [key("w")],
        .layoutBSP: [key("b")],
        .layoutStack: [key("s")],
        .layoutFloat: [key("u")],
        .previousSpace: [key("p")],
        .nextSpace: [key("n")]
    ])
}

extension HotkeyConfig {
    /// Key-code and modifier match, following `Hotkey.modifierMatches`.
    func matches(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard case .keyCode(let target) = key, !isDisabled else { return false }
        return keyCode == target && Hotkey.modifierMatches(
            keyCode: keyCode,
            eventFlags: flags,
            bindingModifiers: modifiers
        )
    }
}

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
