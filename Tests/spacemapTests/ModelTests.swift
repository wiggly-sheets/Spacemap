import XCTest
import CoreGraphics
@testable import spacemap

final class ModelTests: XCTestCase {
    func testWindowDropFocusModesRespectHeldModifier() {
        XCTAssertFalse(
            WindowDropFocusMode.never.shouldFocus(
                eventFlags: [.maskCommand],
                requiredModifier: .command
            )
        )
        XCTAssertTrue(
            WindowDropFocusMode.always.shouldFocus(
                eventFlags: [],
                requiredModifier: .command
            )
        )
        XCTAssertTrue(
            WindowDropFocusMode.modifier.shouldFocus(
                eventFlags: [.maskAlternate, .maskShift],
                requiredModifier: .option
            )
        )
        XCTAssertFalse(
            WindowDropFocusMode.modifier.shouldFocus(
                eventFlags: [.maskShift],
                requiredModifier: .option
            )
        )
    }



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

    func testGridStateEquality() {
        let a = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: 1)
        let b = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: 1)
        let c = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: 2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testGridStateWindowsEmpty() {
        let state = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertTrue(state.windows(forSpace: 1).isEmpty)
    }

    func testGridStateGroupsSpacesAndUsesOwningDisplayBounds() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 2, hasFocus: false, isVisible: true, label: nil),
            YabaiSpace(id: 3, index: 3, display: 1, hasFocus: false, isVisible: false, label: nil)
        ]
        let displays = [
            YabaiDisplay(index: 1, frame: .init(x: 0, y: 0, w: 1440, h: 900), hasFocus: true),
            YabaiDisplay(index: 2, frame: .init(x: 1440, y: 0, w: 1920, h: 1080), hasFocus: false)
        ]
        let state = GridState(
            config: .default,
            spaces: spaces,
            windows: [],
            displayBounds: .zero,
            focusedIndex: 1,
            displays: displays
        )

        XCTAssertEqual(state.populatedDisplayIndices, [1, 2])
        XCTAssertEqual(state.spaces(forDisplay: 1).map(\.index), [1, 3])
        XCTAssertEqual(state.spaces(forDisplay: 2).map(\.index), [2])
        XCTAssertEqual(state.displayIndex(forSpace: 2), 2)
        XCTAssertEqual(state.displayBounds(forSpace: 2), CGRect(x: 1440, y: 0, width: 1920, height: 1080))
    }


    func testHotkeyConfigDefault() {
        let hk = HotkeyConfig.default
        XCTAssertEqual(hk.keyCode, 121)
        XCTAssertTrue(hk.modifiers.contains(.maskControl))
    }


    func testGridConfigDefault() {
        let c = GridConfig.default
        XCTAssertEqual(c.cols, 8)
        XCTAssertEqual(c.rows, 2)
        XCTAssertEqual(c.cellStyle, .rects)
        XCTAssertEqual(c.theme, "default")
        XCTAssertEqual(c.maxSpaces, 16)
        XCTAssertEqual(c.multiMonitorHUDMode, .unified)
        XCTAssertEqual(c.unifiedHUDVisibility, .active)
        XCTAssertEqual(c.separateHUDVisibility, .all)
        XCTAssertEqual(c.displayNavigationWrap, .within)
        XCTAssertFalse(c.useVimKeys)
        XCTAssertFalse(c.useArrowKeys)
        XCTAssertTrue(c.pinnedHotkey.isDisabled)
        XCTAssertEqual(c.hudPosition, .center)
    }


    func testHUDPositionCenterLabel() {
        XCTAssertEqual(HUDPosition.center.label, "Center")
    }

    func testHUDPositionTopLabel() {
        XCTAssertEqual(HUDPosition.top.label, "Top")
    }

    func testHUDPositionBottomLabel() {
        XCTAssertEqual(HUDPosition.bottom.label, "Bottom")
    }

    func testHUDPositionCustomLabel() {
        XCTAssertEqual(HUDPosition.custom(x: 0.3, y: 0.7).label, "Custom")
    }

    func testHUDPositionCenterPoint() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panelSize = CGSize(width: 400, height: 200)
        let point = HUDPosition.center.point(for: panelSize, screen: screen)
        XCTAssertEqual(point.x, 760)
        XCTAssertEqual(point.y, 440)
    }

    func testHUDPositionTopPoint() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panelSize = CGSize(width: 400, height: 200)
        let point = HUDPosition.top.point(for: panelSize, screen: screen)
        XCTAssertEqual(point.x, 760)
        XCTAssertEqual(point.y, 840)
    }

    func testHUDPositionBottomPoint() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panelSize = CGSize(width: 400, height: 200)
        let point = HUDPosition.bottom.point(for: panelSize, screen: screen)
        XCTAssertEqual(point.x, 760)
        XCTAssertEqual(point.y, 40)
    }

    func testHUDPositionCustomPoint() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panelSize = CGSize(width: 400, height: 200)
        let point = HUDPosition.custom(x: 0.0, y: 1.0).point(for: panelSize, screen: screen)
        XCTAssertEqual(point.x, 0)
        XCTAssertEqual(point.y, 880)
    }


    func testAppThemeDefaultValues() {
        let t = AppTheme.default
        XCTAssertEqual(t.background, 0xf2f2f7)
        XCTAssertEqual(t.focused, 0x007aff)
        XCTAssertEqual(t.text, 0x333333)
        XCTAssertEqual(t.rect1, 0x007aff)
        XCTAssertEqual(t.rect2, 0x5ac8fa)
        XCTAssertEqual(t.rect3, 0x34c759)
    }

    func testAppThemeBuiltinThemesHaveDistinctColors() {
        let themes: [AppTheme] = [.default, .tokyonight, .catppuccin, .dracula, .nord]
        for (i, a) in themes.enumerated() {
            for (j, b) in themes.enumerated() where i != j {
                XCTAssertNotEqual(a.background, b.background, "Themes \(i) and \(j) share background color")
            }
        }
    }


    func testDisplayIndexForMissingSpaceReturnsNil() {
        let state = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertNil(state.displayIndex(forSpace: 99), "Unknown space should return nil")
    }

    func testDisplayBoundsForMissingSpaceReturnsFallback() {
        let fallback = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let state = GridState(config: .default, spaces: [], windows: [], displayBounds: fallback, focusedIndex: nil)
        XCTAssertEqual(state.displayBounds(forSpace: 99), fallback, "Unknown space should return displayBounds")
    }

    func testDisplayBoundsForSpaceWithDisplay() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 2, hasFocus: false, isVisible: true, label: nil),
        ]
        let displays = [
            YabaiDisplay(index: 2, frame: .init(x: 1440, y: 0, w: 1920, h: 1080), hasFocus: false),
        ]
        let state = GridState(
            config: .default,
            spaces: spaces,
            windows: [],
            displayBounds: .zero,
            focusedIndex: nil,
            displays: displays
        )
        XCTAssertEqual(state.displayBounds(forSpace: 1), CGRect(x: 1440, y: 0, width: 1920, height: 1080))
    }

    func testPopulatedDisplayIndicesEmpty() {
        let state = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertTrue(state.populatedDisplayIndices.isEmpty, "No spaces should mean no display indices")
    }

    func testPopulatedDisplayIndicesDeduplicatedAndSorted() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 2, hasFocus: false, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 3, index: 3, display: 2, hasFocus: false, isVisible: true, label: nil),
            YabaiSpace(id: 4, index: 4, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        let state = GridState(config: .default, spaces: spaces, windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertEqual(state.populatedDisplayIndices, [1, 2], "Should be deduplicated and sorted")
    }

    func testSpacesForDisplayEmpty() {
        let state = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertTrue(state.spaces(forDisplay: 1).isEmpty, "No spaces should return empty array")
    }

    func testSpacesForDisplayFilteredAndSorted() {
        let spaces = [
            YabaiSpace(id: 1, index: 3, display: 1, hasFocus: false, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 3, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        let state = GridState(config: .default, spaces: spaces, windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertEqual(state.spaces(forDisplay: 1).map(\.index), [1, 2, 3], "Should be sorted by index")
    }

    func testSpacesForDisplayDifferentDisplay() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 2, hasFocus: false, isVisible: true, label: nil),
        ]
        let state = GridState(config: .default, spaces: spaces, windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertEqual(state.spaces(forDisplay: 1).map(\.index), [1])
        XCTAssertEqual(state.spaces(forDisplay: 2).map(\.index), [2])
        XCTAssertTrue(state.spaces(forDisplay: 3).isEmpty)
    }

    func testWindowsForSpaceEmpty() {
        let state = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertTrue(state.windows(forSpace: 1).isEmpty, "No windows should return empty array")
    }

    func testWindowsForSpaceGroupedCorrectly() {
        let windows = [
            YabaiWindow(id: 1, app: "A", space: 1, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 2, app: "B", space: 1, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 3, app: "C", space: 2, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "normal"),
        ]
        let state = GridState(config: .default, spaces: [], windows: windows, displayBounds: .zero, focusedIndex: nil)
        XCTAssertEqual(state.windows(forSpace: 1).count, 2)
        XCTAssertEqual(state.windows(forSpace: 2).count, 1)
        XCTAssertEqual(state.windows(forSpace: 3).count, 0)
    }


    func testGridStateWithDisplays() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
        ]
        let displays = [
            YabaiDisplay(index: 1, frame: .init(x: 0, y: 0, w: 1440, h: 900), hasFocus: true),
        ]
        let state = GridState(
            config: .default,
            spaces: spaces,
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: 1,
            displays: displays
        )
        XCTAssertEqual(state.displays.count, 1)
        XCTAssertEqual(state.displays.first?.index, 1)
    }


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
