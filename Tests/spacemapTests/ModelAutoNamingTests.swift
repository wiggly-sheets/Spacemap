import XCTest
import CoreGraphics
@testable import spacemap

final class ModelAutoNamingTests: ModelTestCase {
    func testAutoNamingDerivesEachSpaceNameFromItsLeftmostVisibleWindow() {
        let spaces = [1, 2, 3].map {
            YabaiSpace(id: $0, index: $0, display: 1, hasFocus: false, isVisible: true, label: nil)
        }
        let hideLeftmost = YabaiWindow(
            id: 1, app: "Hidden", space: 1,
            frame: .init(x: -100, y: 0, w: 10, h: 10),
            isHidden: true, isMinimized: false, subLayer: "normal"
        )
        let windows = [
            hideLeftmost,
            YabaiWindow(id: 2, app: "Notes", space: 1, frame: .init(x: 0, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 3, app: "Safari", space: 1, frame: .init(x: 100, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 4, app: "Mail", space: 2, frame: .init(x: -50, y: 0, w: 10, h: 10), isHidden: false, isMinimized: true, subLayer: "normal"),
            YabaiWindow(id: 5, app: "  Xcode  ", space: 2, frame: .init(x: 0, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal"),
        ].map(standard)
        var config = SpacemapConfig.default
        config.namingMode = .auto
        config.spaceNames = [1: "Typed"]
        let state = GridState(config: config, spaces: spaces, windows: windows, displayBounds: .zero, focusedIndex: nil)

        XCTAssertEqual(state.resolvedSpaceNames, [1: "Notes · Safari", 2: "Xcode"],
                       "visible apps join in reading order, padded app names are trimmed, and space 3 stays nameless")

        config.namingMode = .custom
        let custom = GridState(config: config, spaces: spaces, windows: windows, displayBounds: .zero, focusedIndex: nil)
        XCTAssertEqual(custom.resolvedSpaceNames, [1: "Typed"],
                       "custom mode keeps the profile's typed names")
    }

    /// Auto naming must skip windows the HUD never draws, even though they are
    /// neither hidden nor minimized: zero-size placeholders, sticky followers,
    /// and fully transparent windows.
    func testAutoNamingIgnoresWindowsTheHUDNeverDraws() {
        let spaces = [1, 2].map {
            YabaiSpace(id: $0, index: $0, display: 1, hasFocus: false, isVisible: true, label: nil)
        }
        var placeholder = YabaiWindow(
            id: 1, app: "Placeholder", space: 1, frame: .init(x: -300, y: 0, w: 0, h: 0),
            isHidden: false, isMinimized: false, subLayer: "normal"
        )
        placeholder.isVisible = true
        var sticky = YabaiWindow(
            id: 2, app: "Sticky", space: 1, frame: .init(x: -200, y: 0, w: 10, h: 10),
            isHidden: false, isMinimized: false, subLayer: "normal"
        )
        sticky.isSticky = true
        var transparent = YabaiWindow(
            id: 3, app: "Transparent", space: 1, frame: .init(x: -100, y: 0, w: 10, h: 10),
            isHidden: false, isMinimized: false, subLayer: "normal"
        )
        transparent.opacity = 0
        let windows = [
            placeholder,
            sticky,
            transparent,
            YabaiWindow(id: 4, app: "Finder", space: 1, frame: .init(x: 0, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 5, app: "Ghost", space: 2, frame: .init(x: 0, y: 0, w: 0, h: 0), isHidden: false, isMinimized: false, subLayer: "normal"),
        ].map(standard)
        var config = SpacemapConfig.default
        config.namingMode = .auto
        let state = GridState(config: config, spaces: spaces, windows: windows, displayBounds: .zero, focusedIndex: nil)

        XCTAssertEqual(state.resolvedSpaceNames, [1: "Finder"],
                       "undrawn windows skip naming, and the leftmost drawn window still wins")
    }

    /// A window the HUD refuses to draw must not name a space, even though
    /// yabai lists it there. That is what leaked helper windows such as
    /// Plexamp into auto names.
    func testAutoNamingUsesTheHUDDisplayRules() {
        let spaces = [YabaiSpace(id: 1, index: 1, display: 1, hasFocus: false, isVisible: true, label: nil)]
        let helperWindow = YabaiWindow(
            id: 1, app: "Plexamp", space: 1,
            frame: .init(x: 0, y: 0, w: 10, h: 10),
            isHidden: false, isMinimized: false, subLayer: "normal"
        )
        let windows = [
            helperWindow,
            standard(YabaiWindow(id: 2, app: "Safari", space: 1, frame: .init(x: 100, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal")),
        ]
        var config = SpacemapConfig.default
        config.namingMode = .auto

        func names(extraWindows: Bool) -> [Int: String] {
            config.showExtraWindows = extraWindows
            let state = GridState(config: config, spaces: spaces, windows: windows, displayBounds: .zero, focusedIndex: nil)
            return state.resolvedSpaceNames
        }

        XCTAssertEqual(names(extraWindows: false), [1: "Safari"],
                       "non-standard helper windows never name a space")
        XCTAssertEqual(names(extraWindows: true), [1: "Plexamp · Safari"],
                       "Extra Windows admits them, exactly as the HUD draws them")
    }

    func testAutoNamingJoinsConfiguredAppCountAndMarksExtraApps() {
        let spaces = [1, 2].map {
            YabaiSpace(id: $0, index: $0, display: 1, hasFocus: false, isVisible: true, label: nil)
        }
        let windows = [
            YabaiWindow(id: 1, app: "Notes", space: 1, frame: .init(x: 0, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 2, app: "Safari", space: 1, frame: .init(x: 100, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 3, app: "Notes", space: 1, frame: .init(x: 200, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 4, app: "Mail", space: 1, frame: .init(x: 300, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 5, app: "Finder", space: 2, frame: .init(x: 0, y: 0, w: 10, h: 10), isHidden: false, isMinimized: false, subLayer: "normal"),
        ].map(standard)
        var config = SpacemapConfig.default
        config.namingMode = .auto

        func names(_ count: Int) -> [Int: String] {
            config.autoNameAppCount = count
            let state = GridState(config: config, spaces: spaces, windows: windows, displayBounds: .zero, focusedIndex: nil)
            return state.resolvedSpaceNames
        }

        XCTAssertEqual(names(1), [1: "Notes…", 2: "Finder"],
                       "one app plus an ellipsis when the space has more")
        XCTAssertEqual(names(2), [1: "Notes · Safari…", 2: "Finder"],
                       "repeated apps are not listed twice")
        XCTAssertEqual(names(3), [1: "Notes · Safari · Mail", 2: "Finder"],
                       "no ellipsis when every distinct app fits")
        XCTAssertEqual(names(9), names(3),
                       "out-of-range counts behave like three")
    }

    func testFuzzyJumpTurnsOffWithHiddenSpaceNames() {
        var config = SpacemapConfig.default
        XCTAssertTrue(config.effectiveFuzzySpaceJumpEnabled,
                      "name jumps are on by default while names are visible")

        config.showSpaceNames = false
        XCTAssertFalse(config.effectiveFuzzySpaceJumpEnabled,
                       "hiding space names also turns name jumps off")

        config.showSpaceNames = true
        config.fuzzySpaceJumpEnabled = false
        XCTAssertFalse(config.effectiveFuzzySpaceJumpEnabled,
                       "the toggle alone can turn name jumps off")
    }

}
