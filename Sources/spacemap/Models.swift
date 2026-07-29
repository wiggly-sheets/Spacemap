import Foundation
import CoreGraphics

enum CellStyle: Int, CaseIterable, Identifiable {
    case rects, hybrid, icons, thumbnails, simple
    var id: Int { rawValue }
}
enum ShowMode: String, CaseIterable, Identifiable { case all, active; var id: String { rawValue } }
enum MultiMonitorHUDMode: String, CaseIterable, Identifiable {
    case unified
    case separate

    var id: String { rawValue }
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
    var mode: ThemeMode // light, dark, or auto (follow system)
    var iconScale: Double // 0.0 to 1.0, maps to effective icon multiplier
    var showSpaceNumbers: Bool // show space index numbers in cells
    var showSpaceNames: Bool // show configured space name text in cells
    var showIconStrip: Bool // show icon strip at the bottom of each cell
    var showMultiAppIcons: Bool // show one icon per window (true) or one per unique app (false)
    var hideMenuBarIcon: Bool // hide the menu bar icon (settings accessible via re-launch or Cmd+, in HUD)
    var spaceNames: [Int: String] // space id to name mapping
    var useVimKeys: Bool // navigate spaces with hjkl when HUD is visible
    var useArrowKeys: Bool // navigate spaces with arrow keys when HUD is visible
    var hudPosition: HUDPosition // where to show the HUD on screen
    var customHUDX: Double = 0.5 // last custom HUD X position (0-1)
    var customHUDY: Double = 0.5 // last custom HUD Y position (0-1)
    var showExtraWindows: Bool // show nonstandard utility/background window records
    var focusSpaceOnWindowDrop: Bool = false // focus the destination after a successful drag-and-drop
    var updateMode: UpdateMode // auto | notify | off

    static let `default` = GridConfig(cols: 8, rows: 2, cellStyle: .rects, hotkey: .default, pinnedHotkey: HotkeyConfig(key: .none, modifiers: []), socketHealthInterval: 60, uiScale: 0.5, autoHideTimeout: 5, theme: "default", showMode: .all, multiMonitorHUDMode: .unified, unifiedHUDVisibility: .active, separateHUDVisibility: .all, displayNavigationWrap: .within, maxSpaces: 16, backgroundAlpha: 0.3, mode: .auto, iconScale: 0.5, showSpaceNumbers: true, showSpaceNames: true, showIconStrip: true, showMultiAppIcons: false, hideMenuBarIcon: false, spaceNames: [:], useVimKeys: false, useArrowKeys: false, hudPosition: .center, customHUDX: 0.5, customHUDY: 0.5, showExtraWindows: false, focusSpaceOnWindowDrop: false, updateMode: .notify)
}

struct AppTheme: Equatable {
    let background: UInt32      // HUD grid background
    let focused: UInt32         // Focused space border/highlight
    let text: UInt32            // Text color
    let dropTarget: UInt32      // Drop target highlight
    let cellBg: UInt32          // Unfocused cell fill
    let cellBgFocused: UInt32   // Focused cell fill
    let rect1: UInt32           // Window rect color 1
    let rect2: UInt32           // Window rect color 2
    let rect3: UInt32           // Window rect color 3

    static let `default` = AppTheme(
        background: 0xf2f2f7, focused: 0x007aff, text: 0x333333,
        dropTarget: 0x007aff, cellBg: 0xe5e5ea, cellBgFocused: 0xd1d1d6,
        rect1: 0x007aff, rect2: 0x5ac8fa, rect3: 0x34c759
    )
    static let tokyonight = AppTheme(
        background: 0x1a1b26, focused: 0x7aa2f7, text: 0xa9b1d6,
        dropTarget: 0xbb9af7, cellBg: 0x1a1b26, cellBgFocused: 0x1a1b26,
        rect1: 0x7aa2f7, rect2: 0xbb9af7, rect3: 0x9ece6a
    )
    static let catppuccin = AppTheme(
        background: 0x1e1e2e, focused: 0xcba6f7, text: 0xcdd6f4,
        dropTarget: 0xf5c2e7, cellBg: 0x313244, cellBgFocused: 0x45475a,
        rect1: 0xcba6f7, rect2: 0xf5c2e7, rect3: 0xa6e3a1
    )
    static let monokaiDark = AppTheme(
        background: 0x272822, focused: 0xa6e22e, text: 0xf8f8f2,
        dropTarget: 0xfd971f, cellBg: 0x3e3d32, cellBgFocused: 0x49483e,
        rect1: 0xa6e22e, rect2: 0xfd971f, rect3: 0x66d9ef
    )
    static let monokaiLight = AppTheme(
        background: 0xfafafa, focused: 0xa6e22e, text: 0x272822,
        dropTarget: 0xfd971f, cellBg: 0xe8e8d8, cellBgFocused: 0xd6d6c8,
        rect1: 0x7ec837, rect2: 0xf38634, rect3: 0x2cc5a6
    )
    static let dracula = AppTheme(
        background: 0x282a36, focused: 0xbd93f9, text: 0xf8f8f2,
        dropTarget: 0xff79c6, cellBg: 0x44475a, cellBgFocused: 0x565a79,
        rect1: 0xbd93f9, rect2: 0xff79c6, rect3: 0x50fa7b
    )
    static let ayu = AppTheme(
        background: 0x0b0e14, focused: 0xff8f40, text: 0xbfbdb6,
        dropTarget: 0xf07178, cellBg: 0x1a1f29, cellBgFocused: 0x2a3140,
        rect1: 0xff8f40, rect2: 0xf07178, rect3: 0xc2d94c
    )
    static let github = AppTheme(
        background: 0x0d1117, focused: 0x3fb950, text: 0xc9d1d9,
        dropTarget: 0x58a6ff, cellBg: 0x161b22, cellBgFocused: 0x21262d,
        rect1: 0x3fb950, rect2: 0x58a6ff, rect3: 0xd2a8ff
    )
    static let vscode = AppTheme(
        background: 0x1e1e1e, focused: 0x007acc, text: 0xcccccc,
        dropTarget: 0x4ec9b0, cellBg: 0x252526, cellBgFocused: 0x333333,
        rect1: 0x007acc, rect2: 0x4ec9b0, rect3: 0xdcdcaa
    )
    static let xcode = AppTheme(
        background: 0x1f1f24, focused: 0x5e9eff, text: 0xffffff,
        dropTarget: 0x6c5ce7, cellBg: 0x2c2c32, cellBgFocused: 0x3a3a42,
        rect1: 0x5e9eff, rect2: 0x6c5ce7, rect3: 0xff6b6b
    )
    static let nord = AppTheme(
        background: 0x2e3440, focused: 0x88c0d0, text: 0xd8dee9,
        dropTarget: 0x81a1c1, cellBg: 0x3b4252, cellBgFocused: 0x434c5e,
        rect1: 0x88c0d0, rect2: 0x81a1c1, rect3: 0xa3be8c
    )
    static let atomOneDark = AppTheme(
        background: 0x282c34, focused: 0x61afef, text: 0xabb2bf,
        dropTarget: 0x98c379, cellBg: 0x2c323c, cellBgFocused: 0x3a404a,
        rect1: 0x61afef, rect2: 0x98c379, rect3: 0xc678dd
    )

    static func named(_ name: String) -> AppTheme {
        ThemeManager.shared.named(name)
    }
}

struct YabaiSpace: Decodable {
    let id: Int
    let index: Int
    let display: Int
    let hasFocus: Bool
    let isVisible: Bool?
    let label: String? // space name from yabai

    enum CodingKeys: String, CodingKey {
        case id, index, display
        case hasFocus = "has-focus"
        case isVisible = "is-visible"
        case label
    }
}

struct YabaiDisplay: Decodable {
    struct Frame: Decodable {
        let x: CGFloat
        let y: CGFloat
        let w: CGFloat
        let h: CGFloat

        var cgFrame: CGRect {
            CGRect(x: x, y: y, width: w, height: h)
        }
    }

    let index: Int
    let frame: Frame
    let hasFocus: Bool

    enum CodingKeys: String, CodingKey {
        case index, frame
        case hasFocus = "has-focus"
    }
}

struct YabaiWindow: Decodable {
    let id: Int
    let app: String
    let space: Int
    let frame: WindowFrame
    let isHidden: Bool
    let isMinimized: Bool
    let subLayer: String
    var pid: Int? = nil
    var role: String? = nil
    var subrole: String? = nil
    var isRootWindow: Bool? = nil
    var hasAXReference: Bool? = nil
    var isVisible: Bool? = nil
    var isFloating: Bool? = nil

    struct WindowFrame: Decodable {
        let x: CGFloat
        let y: CGFloat
        let w: CGFloat
        let h: CGFloat
    }

    enum CodingKeys: String, CodingKey {
        case id, app, space, frame, pid, role, subrole
        case isHidden = "is-hidden"
        case isMinimized = "is-minimized"
        case subLayer = "sub-layer"
        case isRootWindow = "root-window"
        case hasAXReference = "has-ax-reference"
        case isVisible = "is-visible"
        case isFloating = "is-floating"
    }

    var isRealWindow: Bool {
        shouldDisplay(showExtraWindows: false)
    }

    func shouldDisplay(
        showExtraWindows: Bool,
        ownerIsRegularApplication: Bool = false
    ) -> Bool {
        guard !isHidden,
              !isMinimized,
              id > 0,
              !app.isEmpty,
              space > 0,
              frame.w > 0,
              frame.h > 0 else {
            return false
        }

        // A standard root app window is user-facing regardless of whether
        // yabai tiles or floats it, and regardless of active-space AX access.
        let isStandardUserWindow =
            role == "AXWindow" &&
            subrole == "AXStandardWindow" &&
            isRootWindow != false
        if isStandardUserWindow { return true }

        // yabai can lose AX metadata for an otherwise real window. A root
        // proxy owned by a normal Dock/Cmd-Tab application is still user-facing.
        let isRegularApplicationProxy =
            ownerIsRegularApplication &&
            (role ?? "").isEmpty &&
            (subrole ?? "").isEmpty &&
            isRootWindow == true &&
            hasAXReference == false
        if isRegularApplicationProxy { return true }

        // Preserve compatibility with older yabai payloads that did not expose
        // classification metadata. Modern non-AX placeholders use empty role
        // fields and therefore do not take this fallback.
        let hasClassificationMetadata =
            role != nil ||
            subrole != nil ||
            isRootWindow != nil ||
            hasAXReference != nil ||
            isVisible != nil ||
            isFloating != nil
        if !hasClassificationMetadata, subLayer == "below" { return true }

        return showExtraWindows
    }

    var cgFrame: CGRect {
        CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)
    }
}

struct GridState: Equatable {

    let config: GridConfig
    let spaces: [YabaiSpace]
    let displays: [YabaiDisplay]
    let windows: [YabaiWindow]
    let displayBounds: CGRect
    let focusedIndex: Int?
    // ponytail: pre-grouped windows by space for O(1) per-cell lookup
    private let windowsBySpace: [Int: [YabaiWindow]]

    init(
        config: GridConfig,
        spaces: [YabaiSpace],
        windows: [YabaiWindow],
        displayBounds: CGRect,
        focusedIndex: Int?,
        displays: [YabaiDisplay] = []
    ) {
        self.config = config
        self.spaces = spaces
        self.displays = displays
        self.windows = windows
        self.displayBounds = displayBounds
        self.focusedIndex = focusedIndex
        var grouped: [Int: [YabaiWindow]] = [:]
        for w in windows {
            grouped[w.space, default: []].append(w)
        }
        self.windowsBySpace = grouped
    }

    func windows(forSpace index: Int) -> [YabaiWindow] {
        return windowsBySpace[index] ?? []
    }

    func spaces(forDisplay displayIndex: Int) -> [YabaiSpace] {
        spaces.filter { $0.display == displayIndex }.sorted { $0.index < $1.index }
    }

    func displayIndex(forSpace spaceIndex: Int) -> Int? {
        spaces.first { $0.index == spaceIndex }?.display
    }

    func displayBounds(forSpace spaceIndex: Int) -> CGRect {
        guard let displayIndex = displayIndex(forSpace: spaceIndex) else { return displayBounds }
        return displays.first { $0.index == displayIndex }?.frame.cgFrame ?? displayBounds
    }

    var populatedDisplayIndices: [Int] {
        Array(Set(spaces.map(\.display))).sorted()
    }

    static func == (lhs: GridState, rhs: GridState) -> Bool {
        lhs.focusedIndex == rhs.focusedIndex
    }
}
