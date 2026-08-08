import Foundation
import CoreGraphics

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

struct YabaiWindow: Decodable, Equatable {
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

    struct WindowFrame: Decodable, Equatable {
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

    func shouldDisplay(showExtraWindows: Bool) -> Bool {
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

