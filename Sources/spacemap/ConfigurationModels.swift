import Foundation
import CoreGraphics

enum HUDDisplayMode {
    case unified
    case separate
    case hidden
}

enum CellStyle: Int, CaseIterable, Identifiable {
    case rects, hybrid, icons, thumbnails, simple
    var id: Int { rawValue }
}
enum ShowMode: String, CaseIterable, Identifiable { case all, active; var id: String { rawValue } }
enum MultiMonitorHUDMode: String, CaseIterable, Identifiable {
    case unified
    case separate

    var id: String { rawValue }

    /// Returns the appropriate HUD display mode for the given display index.
    /// For unified mode, always returns .unified.
    /// For separate mode, returns .separate if the display has spaces, otherwise .hidden.
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
enum SeparateHUDVisibility: String, CaseIterable, Identifiable {
    case all
    case active

    var id: String { rawValue }
}
enum DisplayNavigationWrap: String, CaseIterable, Identifiable {
    case within
    case between

    var id: String { rawValue }
}
enum ThemeMode: String, CaseIterable, Identifiable { case light, dark, auto; var id: String { rawValue } }
enum UpdateMode: String, CaseIterable, Identifiable { case auto, notify, off; var id: String { rawValue } }
enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case icon
    case dots
    case current
    case nearby
    case all

    var id: String { rawValue }
}
enum WindowDropFocusMode: String, CaseIterable, Identifiable {
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
enum WindowDropFocusModifier: String, CaseIterable, Identifiable {
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

enum HUDPosition: Equatable, Hashable {
    case center, top, bottom
    case custom(x: Double, y: Double) // percentage of screen (0.0–1.0)

    static let allPresets: [HUDPosition] = [.center, .top, .bottom]

    var label: String {
        switch self {
        case .center: return "Center"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .custom: return "Custom"
        }
    }



    /// Returns the panel origin point for the given panel size and screen.
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

struct HotkeyConfig {
    var key: HotkeyKey
    var modifiers: CGEventFlags

    // Default: Ctrl+Page Down
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

enum MediaKey: String, Codable, CaseIterable {
    case playPause = "play-pause"
    case nextTrack = "next-track"
    case previousTrack = "previous-track"
    case volumeUp = "volume-up"
    case volumeDown = "volume-down"
    case mute = "mute"
    case brightnessUp = "brightness-up"
    case brightnessDown = "brightness-down"
}

struct GridConfig {
    var cols: Int
    var rows: Int
    var cellStyle: CellStyle
    var hotkey: HotkeyConfig
    var pinnedHotkey: HotkeyConfig = HotkeyConfig(key: .none, modifiers: [])
    var socketHealthInterval: Int
    var uiScale: Double // 0.0 to 1.0, maps to effective scale
    var autoHideTimeout: Int // seconds
    var theme: String // "default", "tokyonight", etc.
    var showMode: ShowMode // "all" or "active"
    var multiMonitorHUDMode: MultiMonitorHUDMode // one combined grid or a panel per display
    var unifiedHUDVisibility: SeparateHUDVisibility // all displays or only the display with the focused space
    var separateHUDVisibility: SeparateHUDVisibility // all displays or only the display with the focused space
    var displayNavigationWrap: DisplayNavigationWrap // stay within the focused display or wrap across displays
    var maxSpaces: Int // 1-16, default 16
    var backgroundAlpha: Double // 0.0 to 1.0, 0=transparent 1=opaque
    var hudShadow: Bool = true // draw a shadow behind the HUD panel
    var mode: ThemeMode // light, dark, or auto (follow system)
    var iconScale: Double // 0.0 to 1.0, maps to effective icon multiplier
    var showSpaceNumbers: Bool // show space index numbers in cells
    var showSpaceNames: Bool // show configured space name text in cells
    var showIconStrip: Bool // show icon strip at the bottom of each cell
    var showMultiAppIcons: Bool // show one icon per window (true) or one per unique app (false)
    var hideMenuBarIcon: Bool // hide the menu bar icon (settings accessible via re-launch or Cmd+, in HUD)
    var menuBarDisplayMode: MenuBarDisplayMode = .icon
    var menuBarNearbyCount: Int = 3
    var spaceNames: [Int: String] // space id to name mapping
    var useVimKeys: Bool // navigate spaces with hjkl when HUD is visible
    var useArrowKeys: Bool // navigate spaces with arrow keys when HUD is visible
    var jumpToSpaceEnabled: Bool = false // jump to a space by typing its number
    var hudPosition: HUDPosition // where to show the HUD on screen
    var customHUDX: Double = 0.5 // last custom HUD X position (0-1)
    var customHUDY: Double = 0.5 // last custom HUD Y position (0-1)
    var showExtraWindows: Bool // show nonstandard utility/background window records
    var focusSpaceOnWindowDrop: WindowDropFocusMode = .never
    var focusSpaceOnWindowDropModifier: WindowDropFocusModifier = .command
    var showHUDOnSpaceChange: Bool = false // show the HUD after any yabai space change
    var updateMode: UpdateMode // auto | notify | off

    static let `default` = GridConfig(
        cols: 8, rows: 2, cellStyle: .rects, hotkey: .default,
        pinnedHotkey: HotkeyConfig(key: .none, modifiers: []),
        socketHealthInterval: 60, uiScale: 0.5, autoHideTimeout: 5,
        theme: "default", showMode: .all, multiMonitorHUDMode: .unified,
        unifiedHUDVisibility: .active, separateHUDVisibility: .all,
        displayNavigationWrap: .within, maxSpaces: 16, backgroundAlpha: 0.3, hudShadow: true,
        mode: .auto, iconScale: 0.5, showSpaceNumbers: true,
        showSpaceNames: true, showIconStrip: true, showMultiAppIcons: false,
        hideMenuBarIcon: false, menuBarDisplayMode: .icon,
        menuBarNearbyCount: 3, spaceNames: [:], useVimKeys: false,
        useArrowKeys: false, jumpToSpaceEnabled: false, hudPosition: .center, customHUDX: 0.5,
        customHUDY: 0.5, showExtraWindows: false,
        focusSpaceOnWindowDrop: .never, focusSpaceOnWindowDropModifier: .command,
        showHUDOnSpaceChange: false,
        updateMode: .notify
    )
}
