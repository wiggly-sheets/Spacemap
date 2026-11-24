import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


final class GlyphStripClickActionTests: GlyphStripTestCase {

    // MARK: - Click actions

    func testFocusAndDestroyCarryTheSegmentIndex() {
        XCTAssertEqual(
            GlyphStrip.command(for: .focusSpace, spaceIndex: 3, focusedSpaceIndex: 1),
            .focusSpace(3)
        )
        XCTAssertEqual(
            GlyphStrip.command(for: .destroySpace, spaceIndex: 3, focusedSpaceIndex: 1),
            .destroySpace(3)
        )
    }

    func testSpaceActionsNeedASegmentIndex() {
        for action in [GlyphStripAction.focusSpace, .destroySpace, .moveWindowHere] {
            XCTAssertNil(GlyphStrip.command(for: action, spaceIndex: nil, focusedSpaceIndex: 1))
        }
    }

    func testNoneNeverProducesACommand() {
        XCTAssertNil(GlyphStrip.command(for: .none, spaceIndex: 2, focusedSpaceIndex: 1))
    }

    func testWindowScopedActionsIgnoreTheSegmentIndex() {
        XCTAssertEqual(GlyphStrip.command(for: .toggleFullscreen, spaceIndex: 2, focusedSpaceIndex: 1), .toggleFullscreen)
        XCTAssertEqual(GlyphStrip.command(for: .floatWindow, spaceIndex: 2, focusedSpaceIndex: 1), .floatWindow)
        XCTAssertEqual(GlyphStrip.command(for: .balanceWindows, spaceIndex: 2, focusedSpaceIndex: 1), .balanceWindows)
    }

    func testMergeIsRejectedOnTheCurrentSpace() {
        XCTAssertNil(GlyphStrip.command(for: .mergeWindows, spaceIndex: 2, focusedSpaceIndex: 2))
        XCTAssertEqual(
            GlyphStrip.command(for: .mergeWindows, spaceIndex: 4, focusedSpaceIndex: 2),
            .mergeIntoSpace(4)
        )
    }
}
