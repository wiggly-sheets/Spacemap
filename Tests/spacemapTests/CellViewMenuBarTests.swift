import XCTest
import CoreGraphics
import SwiftUI
@testable import spacemap

final class CellViewMenuBarTests: CellViewGridViewTestCase {
    func testMenuBarCurrentModeReturnsFocusedSpace() {
        XCTAssertEqual(
            MenuBarPreviewRenderer.spaceIndices(
                mode: .current,
                nearbyCount: 3,
                spaces: makeSpaces(1...6),
                focusedIndex: 4
            ),
            [4]
        )
    }

    func testMenuBarNearbyModeCentersAndShiftsAtEdges() {
        let spaces = makeSpaces(1...6)
        XCTAssertEqual(
            MenuBarPreviewRenderer.spaceIndices(
                mode: .nearby,
                nearbyCount: 3,
                spaces: spaces,
                focusedIndex: 4
            ),
            [3, 4, 5]
        )
        XCTAssertEqual(
            MenuBarPreviewRenderer.spaceIndices(
                mode: .nearby,
                nearbyCount: 3,
                spaces: spaces,
                focusedIndex: 1
            ),
            [1, 2, 3]
        )
        XCTAssertEqual(
            MenuBarPreviewRenderer.spaceIndices(
                mode: .nearby,
                nearbyCount: 3,
                spaces: spaces,
                focusedIndex: 6
            ),
            [4, 5, 6]
        )
    }

    func testMenuBarAllModeUsesEveryActiveSpace() {
        XCTAssertEqual(
            MenuBarPreviewRenderer.spaceIndices(
                mode: .all,
                nearbyCount: 3,
                spaces: makeSpaces(1...6),
                focusedIndex: 3
            ),
            [1, 2, 3, 4, 5, 6]
        )
    }

    func testMenuBarDotsModeExpandsForLegibility() throws {
        var config = SpacemapConfig.default
        config.menuBarDisplayMode = .dots
        config.cols = 8
        config.rows = 2
        config.maxSpaces = 16
        let state = GridState(
            config: config,
            spaces: makeSpaces(1...6),
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            focusedIndex: 3
        )

        let image = try XCTUnwrap(MenuBarPreviewRenderer.image(for: state))
        XCTAssertEqual(image.size, CGSize(width: 46.5, height: 20))
    }

    func testMenuBarWindowFramesLeaveVisiblePaneGaps() throws {
        let separated = try XCTUnwrap(
            MenuBarPreviewRenderer.separatedWindowFrame(
                CGRect(x: 0, y: 0, width: 15, height: 7)
            )
        )

        XCTAssertEqual(separated, CGRect(x: 0.55, y: 0.55, width: 13.9, height: 5.9))
    }


}
