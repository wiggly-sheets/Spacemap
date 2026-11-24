import XCTest
import CoreGraphics
@testable import spacemap

final class HUDInputNavigationTests: HUDInputTestCase {
    func testNavigateToFirstAndLastMoveAcrossUnifiedGrid() {
        let input = HUDInput(panel: nil)
        var config = SpacemapConfig.default
        config.showMode = .active
        config.maxSpaces = 8
        let spaces = [
            YabaiSpace(id: 1, index: 3, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 5, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 3, index: 8, display: 1, hasFocus: false, isVisible: nil, label: nil)
        ]
        input.currentState = GridState(config: config, spaces: spaces, windows: [], displayBounds: .zero, focusedIndex: 5)
        input.lastFocusedSpaceIndex = 5

        input.navigateToFirst()

        XCTAssertEqual(input.lastFocusedSpaceIndex, 3)

        input.navigateToLast()

        XCTAssertEqual(input.lastFocusedSpaceIndex, 8)
    }

    func testNextAndPreviousSpaceStepAndWrap() {
        let input = HUDInput(panel: nil)
        var config = SpacemapConfig.default
        // `.all` pads the grid to maxSpaces with cells for spaces that do not
        // exist; stepping must stay on real spaces.
        config.showMode = .all
        config.maxSpaces = 8
        let spaces = [
            YabaiSpace(id: 1, index: 3, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 5, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 3, index: 8, display: 1, hasFocus: false, isVisible: nil, label: nil)
        ]
        input.currentState = GridState(config: config, spaces: spaces, windows: [], displayBounds: .zero, focusedIndex: 5)
        input.lastFocusedSpaceIndex = 5

        input.navigateToNextSpace()
        XCTAssertEqual(input.lastFocusedSpaceIndex, 8)

        input.navigateToNextSpace()
        XCTAssertEqual(input.lastFocusedSpaceIndex, 3, "next past the last space wraps to the first")

        input.navigateToPreviousSpace()
        XCTAssertEqual(input.lastFocusedSpaceIndex, 8, "previous before the first space wraps to the last")
    }

    func testNavigateToFirstAndLastStayWithinFocusedDisplayInSeparateMode() {
        let input = HUDInput(panel: nil)
        var config = SpacemapConfig.default
        config.multiMonitorHUDMode = .separate
        config.maxSpaces = 8
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 3, index: 4, display: 2, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 4, index: 7, display: 2, hasFocus: false, isVisible: nil, label: nil)
        ]
        input.currentState = GridState(config: config, spaces: spaces, windows: [], displayBounds: .zero, focusedIndex: 4)
        input.lastFocusedSpaceIndex = 4

        input.navigateToLast()

        XCTAssertEqual(input.lastFocusedSpaceIndex, 7)

        input.navigateToFirst()

        XCTAssertEqual(input.lastFocusedSpaceIndex, 4)

        input.navigateToNextSpace()
        XCTAssertEqual(input.lastFocusedSpaceIndex, 7, "next stays within the focused display")

        input.navigateToNextSpace()
        XCTAssertEqual(input.lastFocusedSpaceIndex, 4, "next wraps within the focused display")
    }

}
