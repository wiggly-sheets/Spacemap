import XCTest
import CoreGraphics
@testable import spacemap

final class SpaceNavigatorTests: XCTestCase {
    func testHUDKeyboardRoutingRecognizesNavigationKeys() {
        XCTAssertEqual(
            HUDInput.navigationDirection(
                keyCode: 4,
                flags: [],
                useArrowKeys: false,
                useVimKeys: true
            ),
            .left
        )
        XCTAssertEqual(
            HUDInput.navigationDirection(
                keyCode: 126,
                flags: [],
                useArrowKeys: true,
                useVimKeys: false
            ),
            .up
        )
        XCTAssertNil(
            HUDInput.navigationDirection(
                keyCode: 4,
                flags: [.maskCommand],
                useArrowKeys: true,
                useVimKeys: true
            )
        )
    }

    func testHUDKeyboardRoutingRecognizesSettingsShortcut() {
        XCTAssertTrue(
            HUDInput.isSettingsShortcut(
                keyCode: 43,
                flags: [.maskCommand]
            )
        )
        XCTAssertFalse(
            HUDInput.isSettingsShortcut(
                keyCode: 43,
                flags: []
            )
        )
    }

    func testNavigableSpacesExcludeEmptyPlaceholderCells() {
        let cells = SpaceNavigator.navigableSpaceIndices(
            activeSpaceIndices: [3, 1, 20, 3],
            maxSpaces: 16
        )

        XCTAssertEqual(cells, [1, 3])
        XCTAssertEqual(destination(from: 1, in: cells, columns: 8, direction: .left), 3)
    }

    func testHorizontalNavigationWrapsWithinFullRow() {
        let cells = [1, 2, 3]

        XCTAssertEqual(destination(from: 1, in: cells, columns: 3, direction: .left), 3)
        XCTAssertEqual(destination(from: 3, in: cells, columns: 3, direction: .right), 1)
    }

    func testHorizontalNavigationWrapsWithinPartialFinalRow() {
        let cells = [1, 2, 3, 4, 5]

        XCTAssertEqual(destination(from: 4, in: cells, columns: 3, direction: .left), 5)
        XCTAssertEqual(destination(from: 5, in: cells, columns: 3, direction: .right), 4)
    }

    func testVerticalNavigationWrapsWithinPartialColumn() {
        let cells = [1, 2, 3, 4, 5]

        XCTAssertEqual(destination(from: 1, in: cells, columns: 4, direction: .up), 5)
        XCTAssertEqual(destination(from: 5, in: cells, columns: 4, direction: .down), 1)
    }

    func testVerticalNavigationNeverMovesAcrossColumnsWhenFinalRowIsPartial() {
        let cells = [1, 2, 3, 4, 5]

        XCTAssertEqual(destination(from: 3, in: cells, columns: 3, direction: .up), 3)
        XCTAssertEqual(destination(from: 3, in: cells, columns: 3, direction: .down), 3)
        XCTAssertEqual(destination(from: 2, in: cells, columns: 3, direction: .down), 5)
        XCTAssertEqual(destination(from: 5, in: cells, columns: 3, direction: .up), 2)
    }

    func testNavigationSupportsNonContiguousVisibleSpaces() {
        let cells = [1, 3, 5]

        XCTAssertEqual(destination(from: 3, in: cells, columns: 2, direction: .right), 1)
        XCTAssertEqual(destination(from: 1, in: cells, columns: 2, direction: .down), 5)
        XCTAssertEqual(destination(from: 5, in: cells, columns: 2, direction: .up), 1)
    }

    func testNavigationHandlesEmptyHiddenAndInvalidColumnCases() {
        XCTAssertNil(destination(from: 1, in: [], columns: 3, direction: .right))
        XCTAssertEqual(destination(from: 9, in: [1, 2, 3], columns: 3, direction: .right), 1)
        XCTAssertEqual(destination(from: 1, in: [1, 2, 3], columns: 0, direction: .down), 2)
    }

    func testCrossDisplayNavigationEntersTheNextDisplayAtWrapEdges() {
        let displays = [[1, 2, 3, 4, 5], [6, 7]]

        XCTAssertEqual(crossDisplayDestination(from: 1, in: displays, columns: 3, direction: .right), 2)
        XCTAssertEqual(crossDisplayDestination(from: 5, in: displays, columns: 3, direction: .right), 6)
        XCTAssertEqual(crossDisplayDestination(from: 4, in: displays, columns: 3, direction: .left), 7)
        XCTAssertEqual(crossDisplayDestination(from: 5, in: displays, columns: 3, direction: .down), 6)
        XCTAssertEqual(crossDisplayDestination(from: 1, in: displays, columns: 3, direction: .up), 7)
    }

    func testCrossDisplayNavigationWrapsAndSkipsDisplaysOutsideTheSpaceLimit() {
        XCTAssertEqual(
            crossDisplayDestination(from: 4, in: [[1, 2], [17], [3, 4]], columns: 2, direction: .right),
            1
        )
        XCTAssertEqual(
            crossDisplayDestination(from: 2, in: [[1, 2], [17], [3, 4]], columns: 2, direction: .right),
            3
        )
        XCTAssertEqual(
            crossDisplayDestination(from: 2, in: [[1, 2]], columns: 2, direction: .right),
            1
        )
    }

    private func destination(
        from current: Int,
        in cells: [Int],
        columns: Int,
        direction: SpaceNavigationDirection
    ) -> Int? {
        SpaceNavigator.destination(
            from: current,
            visibleSpaceIndices: cells,
            columns: columns,
            direction: direction
        )
    }

    private func crossDisplayDestination(
        from current: Int,
        in displays: [[Int]],
        columns: Int,
        direction: SpaceNavigationDirection
    ) -> Int? {
        SpaceNavigator.destinationAcrossDisplays(
            from: current,
            displaySpaceIndices: displays,
            maxSpaces: 16,
            columns: columns,
            direction: direction
        )
    }
}
