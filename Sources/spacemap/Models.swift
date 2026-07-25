import Foundation
import CoreGraphics
import AppKit

enum CellStyle: Int, CaseIterable, Identifiable {
    case rects, icons, thumbnails, simple
    var id: Int { rawValue }
}
enum ShowMode: String, CaseIterable, Identifiable { case all, active; var id: String { rawValue } }
enum ThemeMode: String, CaseIterable, Identifiable { case light, dark, auto; var id: String { rawValue } }
enum UpdateMode: String, CaseIterable, Identifiable { case auto, notify, off; var id: String { rawValue } }

enum Mode: String, CaseIterable, Identifiable {
    case light, dark, auto
    var id: String { rawValue }
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
}

struct AppTemplate: Equatable {
    let name: String
    let bundleIdentifier: String
}

struct WindowFrame: Decodable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

struct YabaiSpace: Decodable {
    let id: Int
    let index: Int
    let display: Int
    let hasFocus: Bool
    let label: String? // space name from yabai

    enum CodingKeys: String, CodingKey {
        case id, index, display
        case hasFocus = "has-focus"
        case label
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

    enum CodingKeys: String, CodingKey {
        case id, app, space, frame
        case isHidden = "is-hidden"
        case isMinimized = "is-minimized"
        case subLayer = "sub-layer"
    }

    var isRealWindow: Bool {
        !isHidden && !isMinimized && subLayer == "below"
    }

    var cgFrame: CGRect {
        CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }
}

struct GridState: Equatable {

    let config: GridConfig
    let spaces: [YabaiSpace]
    let windows: [YabaiWindow]
    let displayBounds: CGRect
    let focusedIndex: Int?
    // ponytail: pre-grouped windows by space for O(1) per-cell lookup
    private let windowsBySpace: [Int: [YabaiWindow]]

    init(config: GridConfig, spaces: [YabaiSpace], windows: [YabaiWindow], displayBounds: CGRect, focusedIndex: Int?) {
        self.config = config
        self.spaces = spaces
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

    static func == (lhs: GridState, rhs: GridState) -> Bool {
        lhs.focusedIndex == rhs.focusedIndex
    }
}

struct AppTheme: Equatable {
    let background: UInt32
    let focused: UInt32
    let text: UInt32
    let dropTarget: UInt32
    let cellBg: UInt32
    let cellBgFocused: UInt32
    let rect1: UInt32
    let rect2: UInt32
    let rect3: UInt32
    
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
    static let dracula = AppTheme(
        background: 0x282a36, focused: 0xbd93f9, text: 0xf8f8f2,
        dropTarget: 0xff79c6, cellBg: 0x44475a, cellBgFocused: 0x565a79,
        rect1: 0xbd93f9, rect2: 0xff79c6, rect3: 0x50fa7b
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
}

struct GridConfig {
    let cols: Int
    let rows: Int
    let cellStyle: CellStyle
    let hotkey: HotkeyConfig
    let socketHealthInterval: Int
    let uiScale: Double
    let autoHideTimeout: Int
    let theme: String
    let showMode: ShowMode
    let maxSpaces: Int
    let backgroundAlpha: Double
    let mode: Mode
    let iconScale: Double
    let showSpaceNumbers: Bool
    let showSpaceNames: Bool
    let showIconStrip: Bool
    let showMultiAppIcons: Bool
    let hideMenuBarIcon: Bool
    let spaceNames: [Int: String]
    let useVimKeys: Bool
    let useArrowKeys: Bool
    let hudPosition: HUDPosition
    let customHUDX: Double
    let customHUDY: Double
    let showExtraWindows: Bool
    let updateMode: UpdateMode
    let windowManager: WindowManagerType
}

extension GridConfig {
    static var `default`: GridConfig {
        GridConfig(
            cols: 10,
            rows: 2,
            cellStyle: .rects,
            hotkey: HotkeyConfig(keyCode: 49, modifiers: [.maskControl]), // Ctrl+Space
            socketHealthInterval: 60,
            uiScale: 1.0,
            autoHideTimeout: 5,
            theme: "default",
            showMode: .all,
            maxSpaces: 16,
            backgroundAlpha: 0.8,
            mode: .auto,
            iconScale: 1.0,
            showSpaceNumbers: true,
            showSpaceNames: false,
            showIconStrip: true,
            showMultiAppIcons: false,
            hideMenuBarIcon: false,
            spaceNames: [:],
            useVimKeys: false,
            useArrowKeys: true,
            hudPosition: .center,
            customHUDX: 0.5,
            customHUDY: 0.5,
            showExtraWindows: false,
            updateMode: .notify,
            windowManager: .yabai
        )
    }
}

struct HotkeyConfig {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
}