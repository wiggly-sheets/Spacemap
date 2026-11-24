import XCTest
import CoreGraphics
@testable import spacemap

final class YabaiModelTests: ModelTestCase {
    func testDecodeYabaiSpace() throws {
        let json = """
        {"id":1,"index":1,"display":1,"has-focus":true,"is-visible":true,"label":"Term"}
        """.data(using: .utf8)!
        let space = try JSONDecoder().decode(YabaiSpace.self, from: json)
        XCTAssertEqual(space.id, 1)
        XCTAssertEqual(space.index, 1)
        XCTAssertEqual(space.display, 1)
        XCTAssertTrue(space.hasFocus)
        XCTAssertEqual(space.isVisible, true)
        XCTAssertEqual(space.label, "Term")
    }

    func testDecodeYabaiSpaceNoLabel() throws {
        let json = """
        {"id":2,"index":2,"display":1,"has-focus":false}
        """.data(using: .utf8)!
        let space = try JSONDecoder().decode(YabaiSpace.self, from: json)
        XCTAssertNil(space.label)
    }

    func testDecodeYabaiDisplay() throws {
        let json = """
        {"index":2,"frame":{"x":1440,"y":0,"w":1920,"h":1080},"has-focus":false}
        """.data(using: .utf8)!
        let display = try JSONDecoder().decode(YabaiDisplay.self, from: json)
        XCTAssertEqual(display.index, 2)
        XCTAssertEqual(display.frame.cgFrame, CGRect(x: 1440, y: 0, width: 1920, height: 1080))
        XCTAssertFalse(display.hasFocus)
    }


    func testDecodeYabaiWindow() throws {
        let json = """
        {"id":10,"pid":123,"app":"Firefox","space":1,"frame":{"x":0,"y":0,"w":800,"h":600},"is-hidden":false,"is-minimized":false,"sub-layer":"below","role":"AXWindow","subrole":"AXStandardWindow","root-window":true,"has-ax-reference":true,"is-visible":true,"is-floating":false}
        """.data(using: .utf8)!
        let window = try JSONDecoder().decode(YabaiWindow.self, from: json)
        XCTAssertEqual(window.id, 10)
        XCTAssertEqual(window.pid, 123)
        XCTAssertEqual(window.app, "Firefox")
        XCTAssertEqual(window.space, 1)
        XCTAssertFalse(window.isHidden)
        XCTAssertFalse(window.isMinimized)
        XCTAssertEqual(window.subLayer, "below")
        XCTAssertEqual(window.role, "AXWindow")
        XCTAssertEqual(window.subrole, "AXStandardWindow")
        XCTAssertEqual(window.isRootWindow, true)
        XCTAssertEqual(window.hasAXReference, true)
        XCTAssertEqual(window.isVisible, true)
        XCTAssertEqual(window.isFloating, false)
        XCTAssertEqual(window.cgFrame, CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    func testDecodeYabaiWindowHidden() throws {
        let json = """
        {"id":11,"app":"Safari","space":2,"frame":{"x":100,"y":50,"w":400,"h":300},"is-hidden":true,"is-minimized":true,"sub-layer":"normal"}
        """.data(using: .utf8)!
        let window = try JSONDecoder().decode(YabaiWindow.self, from: json)
        XCTAssertTrue(window.isHidden)
        XCTAssertTrue(window.isMinimized)
        XCTAssertEqual(window.subLayer, "normal")
    }

    func testNonAXRootProxyRequiresShowExtraWindows() {
        var window = YabaiWindow(
            id: 12,
            app: "Notes",
            space: 2,
            frame: .init(x: 0, y: 0, w: 800, h: 600),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal"
        )
        window.isRootWindow = true
        window.hasAXReference = false
        window.isVisible = false
        window.isFloating = false

        XCTAssertFalse(window.shouldDisplay(showExtraWindows: false))
        XCTAssertTrue(window.shouldDisplay(showExtraWindows: true))
    }

    func testClosedNotesBackgroundRecordIsNotDisplayable() {
        var window = YabaiWindow(
            id: 34959,
            app: "Notes",
            space: 4,
            frame: .init(x: 855, y: 40, w: 853, h: 1047),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal"
        )
        window.pid = 15032
        window.role = ""
        window.subrole = ""
        window.isRootWindow = true
        window.hasAXReference = false
        window.isVisible = false
        window.isFloating = false

        XCTAssertFalse(window.shouldDisplay(showExtraWindows: false))
        XCTAssertTrue(window.shouldDisplay(showExtraWindows: true))
    }

    func testVisibleStandardWindowIsDisplayableRegardlessOfSubLayer() {
        var window = YabaiWindow(
            id: 14,
            app: "Safari",
            space: 1,
            frame: .init(x: 0, y: 0, w: 800, h: 600),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal"
        )
        window.role = "AXWindow"
        window.subrole = "AXStandardWindow"
        window.isRootWindow = true
        window.hasAXReference = true
        window.isVisible = true
        window.isFloating = false

        XCTAssertTrue(window.shouldDisplay(showExtraWindows: false))

        window.isFloating = true
        XCTAssertTrue(window.shouldDisplay(showExtraWindows: false))
    }

    func testUtilityWindowRequiresShowExtraWindows() {
        var window = YabaiWindow(
            id: 15,
            app: "System Settings",
            space: 1,
            frame: .init(x: 100, y: 100, w: 500, h: 400),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal"
        )
        window.role = "AXWindow"
        window.subrole = "AXDialog"
        window.isRootWindow = false
        window.hasAXReference = true
        window.isVisible = true
        window.isFloating = true

        XCTAssertFalse(window.shouldDisplay(showExtraWindows: false))
        XCTAssertTrue(window.shouldDisplay(showExtraWindows: true))
    }

    func testInvalidInactiveSpacePlaceholderStaysFiltered() {
        let window = YabaiWindow(
            id: 13,
            app: "Helper",
            space: 2,
            frame: .init(x: 0, y: 0, w: 0, h: 0),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal"
        )

        XCTAssertFalse(window.shouldDisplay(showExtraWindows: false))
    }


    func testGridStateWindowGrouping() {
        let windows = [
            YabaiWindow(id: 1, app: "A", space: 1, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "below"),
            YabaiWindow(id: 2, app: "B", space: 1, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "below"),
            YabaiWindow(id: 3, app: "C", space: 2, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "below"),
        ]
        let state = GridState(config: .default, spaces: [], windows: windows, displayBounds: .zero, focusedIndex: nil)
        XCTAssertEqual(state.windows(forSpace: 1).count, 2)
        XCTAssertEqual(state.windows(forSpace: 2).count, 1)
        XCTAssertEqual(state.windows(forSpace: 3).count, 0)
    }

    /// Real yabai windows are standard user windows. Fixtures use this so they
    /// pass the same display rules the HUD applies.
    func testYabaiWindowCGFrame() {
        let window = YabaiWindow(
            id: 1,
            app: "Test",
            space: 1,
            frame: .init(x: 100, y: 200, w: 300, h: 400),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal"
        )
        XCTAssertEqual(window.cgFrame, CGRect(x: 100, y: 200, width: 300, height: 400))
    }


    func testShouldDisplayHiddenWindow() {
        let window = YabaiWindow(
            id: 1,
            app: "Test",
            space: 1,
            frame: .init(x: 0, y: 0, w: 100, h: 100),
            isHidden: true,
            isMinimized: false,
            subLayer: "normal"
        )
        XCTAssertFalse(window.shouldDisplay(showExtraWindows: true))
    }

    func testShouldDisplayMinimizedWindow() {
        let window = YabaiWindow(
            id: 1,
            app: "Test",
            space: 1,
            frame: .init(x: 0, y: 0, w: 100, h: 100),
            isHidden: false,
            isMinimized: true,
            subLayer: "normal"
        )
        XCTAssertFalse(window.shouldDisplay(showExtraWindows: true))
    }

    func testShouldDisplayZeroWidthWindow() {
        let window = YabaiWindow(
            id: 1,
            app: "Test",
            space: 1,
            frame: .init(x: 0, y: 0, w: 0, h: 100),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal"
        )
        XCTAssertFalse(window.shouldDisplay(showExtraWindows: true))
    }

    func testShouldDisplayZeroHeightWindow() {
        let window = YabaiWindow(
            id: 1,
            app: "Test",
            space: 1,
            frame: .init(x: 0, y: 0, w: 100, h: 0),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal"
        )
        XCTAssertFalse(window.shouldDisplay(showExtraWindows: true))
    }

    func testShouldDisplayNegativeSpace() {
        let window = YabaiWindow(
            id: 1,
            app: "Test",
            space: -1,
            frame: .init(x: 0, y: 0, w: 100, h: 100),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal"
        )
        XCTAssertFalse(window.shouldDisplay(showExtraWindows: true))
    }

    func testShouldDisplayZeroIDWindow() {
        let window = YabaiWindow(
            id: 0,
            app: "Test",
            space: 1,
            frame: .init(x: 0, y: 0, w: 100, h: 100),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal"
        )
        XCTAssertFalse(window.shouldDisplay(showExtraWindows: true))
    }

    func testShouldDisplayEmptyAppName() {
        var window = YabaiWindow(
            id: 1,
            app: "",
            space: 1,
            frame: .init(x: 0, y: 0, w: 100, h: 100),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal"
        )
        XCTAssertFalse(window.shouldDisplay(showExtraWindows: true))
        window.role = "AXWindow"
        window.subrole = "AXStandardWindow"
        window.isRootWindow = true
        XCTAssertFalse(window.shouldDisplay(showExtraWindows: true), "Empty app name should still be filtered")
    }


    func testYabaiWindowEquality() {
        let w1 = YabaiWindow(id: 1, app: "A", space: 1, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "normal")
        let w2 = YabaiWindow(id: 1, app: "A", space: 1, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "normal")
        let w3 = YabaiWindow(id: 2, app: "A", space: 1, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "normal")
        XCTAssertEqual(w1, w2, "Same fields should be equal")
        XCTAssertNotEqual(w1, w3, "Different id should not be equal")
    }
}
