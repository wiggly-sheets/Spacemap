import XCTest
import CoreGraphics
import SwiftUI
@testable import spacemap

final class CellViewGridLayoutTests: CellViewGridViewTestCase {
    func testVisibleIndicesShowAll() {
        let indices = GridLayout.visibleSpaceIndices(
            maxSpaces: 8, showMode: .all, activeIndices: Set([1, 3])
        )
        XCTAssertEqual(indices, [1, 2, 3, 4, 5, 6, 7, 8])
    }

    func testVisibleIndicesShowActiveOnly() {
        let indices = GridLayout.visibleSpaceIndices(
            maxSpaces: 8, showMode: .active, activeIndices: Set([1, 3, 5])
        )
        XCTAssertEqual(indices, [1, 3, 5])
    }

    func testVisibleIndicesMaxSpacesLimitsOutput() {
        let indices = GridLayout.visibleSpaceIndices(
            maxSpaces: 4, showMode: .all, activeIndices: Set([1, 2, 3, 4, 5, 6])
        )
        XCTAssertEqual(indices, [1, 2, 3, 4])
    }

    func testVisibleIndicesMaxSpacesClampedTo16() {
        let indices = GridLayout.visibleSpaceIndices(
            maxSpaces: 20, showMode: .all, activeIndices: Set()
        )
        XCTAssertEqual(indices.count, 16)
    }

    func testGridViewUsesSuppliedSpaceIndicesForItsLayout() {
        var config = SpacemapConfig.default
        config.cols = 8
        config.maxSpaces = 8
        config.showMode = .all
        let state = GridState(
            config: config,
            spaces: makeSpaces(1...8),
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            focusedIndex: 1
        )

        let view = GridView(
            state: state,
            hoveredCell: nil,
            onSelect: { _ in },
            resolvedTheme: .default,
            spaceIndices: [6, 5]
        )

        XCTAssertEqual(view.visibleSpaceIndices, [5, 6])
        XCTAssertEqual(
            view.idealSize,
            GridLayout.idealSize(visibleIndices: 2, cols: 8, uiScale: 1)
        )
    }

    func testHoverStateMutationDrivesTheDropTargetCell() {
        var config = SpacemapConfig.default
        config.cols = 4
        config.maxSpaces = 4
        config.showMode = .all
        let state = GridState(
            config: config,
            spaces: makeSpaces(1...4),
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            focusedIndex: 1
        )
        let hover = HUDHoverState()
        let view = GridView(
            state: state,
            hoveredCell: nil,
            hoverState: hover,
            onSelect: { _ in },
            resolvedTheme: .default
        )

        XCTAssertNil(view.dropTargetSpaceIndex)

        hover.cell = 2
        XCTAssertEqual(view.dropTargetSpaceIndex, 2,
            "mutating hover must repaint cell 2 as the drop target")

        hover.cell = 4
        XCTAssertEqual(view.dropTargetSpaceIndex, 4)
        XCTAssertNotEqual(view.dropTargetSpaceIndex, 2,
            "the previous drop target must not linger")

        hover.cell = nil
        XCTAssertNil(view.dropTargetSpaceIndex)
    }

    func testVisibleIndicesActiveNoOverlap() {
        let indices = GridLayout.visibleSpaceIndices(
            maxSpaces: 4, showMode: .active, activeIndices: Set([5, 6])
        )
        XCTAssertTrue(indices.isEmpty)
    }


    func testIdealSizeSingleCell() {
        let size = GridLayout.idealSize(visibleIndices: 1, cols: 8, uiScale: 19.0 / 7.0)
        XCTAssertEqual(size.width, 1040, accuracy: 0.1)
        XCTAssertEqual(size.height, 740, accuracy: 0.1)
    }

    func testIdealSizeMultipleRows() {
        let size = GridLayout.idealSize(visibleIndices: 16, cols: 8, uiScale: 19.0 / 7.0)
        XCTAssertEqual(size.width, 7060, accuracy: 0.1)
        XCTAssertEqual(size.height, 1300, accuracy: 0.1)
    }

    func testIdealSizeZeroCells() {
        let size = GridLayout.idealSize(visibleIndices: 0, cols: 8, uiScale: 19.0 / 7.0)
        XCTAssertEqual(size.width, 180, accuracy: 0.1)
        XCTAssertEqual(size.height, 180, accuracy: 0.1)
    }

    func testIdealSizePartialRow() {
        let size = GridLayout.idealSize(visibleIndices: 3, cols: 8, uiScale: 19.0 / 7.0)
        XCTAssertEqual(size.width, 2760, accuracy: 0.1)
        XCTAssertEqual(size.height, 740, accuracy: 0.1)
    }


    func testRowChunking() {
        let cells = [1, 2, 3, 4, 5, 6, 7, 8]
        let cols = 3
        let rows = stride(from: 0, to: cells.count, by: cols).map {
            Array(cells[$0..<min($0 + cols, cells.count)])
        }
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], [1, 2, 3])
        XCTAssertEqual(rows[1], [4, 5, 6])
        XCTAssertEqual(rows[2], [7, 8])
    }

    func testRowChunkingExactMultiple() {
        let cells = [1, 2, 3, 4, 5, 6]
        let cols = 3
        let rows = stride(from: 0, to: cells.count, by: cols).map {
            Array(cells[$0..<min($0 + cols, cells.count)])
        }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], [1, 2, 3])
        XCTAssertEqual(rows[1], [4, 5, 6])
    }

    func testRowChunkingSingleRow() {
        let cells = [1, 2, 3]
        let cols = 8
        let rows = stride(from: 0, to: cells.count, by: cols).map {
            Array(cells[$0..<min($0 + cols, cells.count)])
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0], [1, 2, 3])
    }

    func testRowChunkingEmpty() {
        let cells: [Int] = []
        let cols = 3
        let rows = stride(from: 0, to: cells.count, by: cols).map {
            Array(cells[$0..<min($0 + cols, cells.count)])
        }
        XCTAssertTrue(rows.isEmpty)
    }


    func testHitTestReturnsIndexForPointInsideFrame() {
        let frames = [CGRect(x: 0, y: 0, width: 80, height: 50),
                      CGRect(x: 86, y: 0, width: 80, height: 50)]
        XCTAssertEqual(GridLayout.hitTest(point: CGPoint(x: 10, y: 10), in: frames), 0)
        XCTAssertEqual(GridLayout.hitTest(point: CGPoint(x: 90, y: 10), in: frames), 1)
    }

    func testHitTestReturnsNilForPointOutsideAllFrames() {
        let frames = [CGRect(x: 0, y: 0, width: 80, height: 50)]
        XCTAssertNil(GridLayout.hitTest(point: CGPoint(x: 200, y: 200), in: frames))
    }

    func testHitTestReturnsFirstMatchForOverlappingFrames() {
        let frames = [CGRect(x: 0, y: 0, width: 100, height: 100),
                      CGRect(x: 50, y: 50, width: 100, height: 100)]
        XCTAssertEqual(GridLayout.hitTest(point: CGPoint(x: 75, y: 75), in: frames), 0)
    }

    func testSpaceLayoutBadgeMapping() {
        XCTAssertEqual(CellView.spaceLayoutBadge(for: "float"), "f")
        XCTAssertEqual(CellView.spaceLayoutBadge(for: "stack"), "s")
        XCTAssertEqual(CellView.spaceLayoutBadge(for: "bsp"), "b")
        XCTAssertEqual(CellView.spaceLayoutBadge(for: nil), "")
        XCTAssertEqual(CellView.spaceLayoutBadge(for: "unknown"), "")
        XCTAssertEqual(CellView.spaceLayoutBadge(for: "bsp", showBSP: false), "")
        XCTAssertEqual(CellView.spaceLayoutBadge(for: "stack", showStack: false), "")
        XCTAssertEqual(CellView.spaceLayoutBadge(for: "float", showFloat: false), "")
    }

    func testShowSpaceLayoutDefaultsOff() {
        XCTAssertFalse(SpacemapConfig.default.showSpaceLayout)
    }

    func testShowSpaceLayoutPlumbsThroughTheConfig() throws {
        XCTAssertFalse(SpacemapConfig.default.showSpaceLayout)
        var config = SpacemapConfig.default
        config.showSpaceLayout = true
        let toml = ConfigLoader.tomlConfigString(from: config, includeHeaderComments: false)
        XCTAssertEqual(try TOMLParser.parse(toml).config.showSpaceLayout, true)
    }

}
