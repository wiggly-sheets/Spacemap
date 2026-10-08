import Foundation
import CoreGraphics

struct YabaiSpace: Decodable, Equatable {
    let id: Int
    let index: Int
    let display: Int
    let hasFocus: Bool
    let isVisible: Bool?
    let label: String?
    var type: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, index, display
        case hasFocus = "has-focus"
        case isVisible = "is-visible"
        case label, type
    }
}

struct YabaiDisplay: Decodable, Equatable {
    struct Frame: Decodable, Equatable {
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
    var opacity: Double? = nil
    var isSticky: Bool? = nil

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
        case opacity
        case isSticky = "is-sticky"
    }

    func shouldDisplay(showExtraWindows: Bool) -> Bool {
        guard !isHidden,
              !isMinimized,
              // Sticky windows already follow the user to every space.
              isSticky != true,
              // Fully transparent windows are phantoms; partially dimmed
              // inactive windows (~0.8) are legitimate.
              (opacity ?? 1) > 0,
              id > 0,
              !app.isEmpty,
              space > 0,
              frame.w > 0,
              frame.h > 0 else {
            return false
        }

        let isStandardUserWindow =
            role == "AXWindow" &&
            subrole == "AXStandardWindow" &&
            isRootWindow != false
        // Standard root windows remain visible regardless of yabai tiling state.
        if isStandardUserWindow { return true }

        return showExtraWindows
    }

    /// Left-to-right, then top-to-bottom, with id as a stable tiebreaker.
    static func inReadingOrder(_ windows: [YabaiWindow]) -> [YabaiWindow] {
        windows.sorted { lhs, rhs in
            if lhs.frame.x != rhs.frame.x { return lhs.frame.x < rhs.frame.x }
            if lhs.frame.y != rhs.frame.y { return lhs.frame.y < rhs.frame.y }
            return lhs.id < rhs.id
        }
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
}
