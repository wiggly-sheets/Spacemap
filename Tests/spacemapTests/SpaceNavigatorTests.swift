import XCTest
@testable import spacemap

final class SpaceNavigatorTests: XCTestCase {
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
}
