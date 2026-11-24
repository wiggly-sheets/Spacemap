import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


final class GlyphStripPlacementTests: GlyphStripTestCase {

    // MARK: - Notch-aware placement

    /// Synthetic 16" MacBook Pro geometry: 1728x1117 screen, 32pt menu bar row,
    /// notch from x=720 to x=1008.

    func testLeftOfNotchHugsTheLeftNotchEdge() {
        let frame = placed(width: 200, position: .leftOfNotch, margin: 6)
        // The strip sits to the LEFT of the notch, so its RIGHT edge is the
        // anchor. Anchoring minX here would render it inside the notch.
        XCTAssertEqual(frame.maxX, leftArea.maxX - 6)
        XCTAssertEqual(frame.width, 200)
        XCTAssertEqual(frame.minY, row.minY, "must sit on the menu bar row, not float above it")
        XCTAssertEqual(frame.height, row.height)
    }

    func testRightOfNotchHugsTheRightNotchEdge() {
        let frame = placed(width: 200, position: .rightOfNotch, margin: 6)
        XCTAssertEqual(frame.minX, rightArea.minX + 6)
    }

    /// The bug this whole block exists for: the strip must never overlap the
    /// notch cutout, whichever side it is anchored to.
    func testNeitherNotchPositionOverlapsTheNotchGap() {
        let gap = CGRect(x: leftArea.maxX, y: row.minY, width: rightArea.minX - leftArea.maxX, height: row.height)
        for position in [GlyphStripPosition.leftOfNotch, .rightOfNotch] {
            let frame = placed(width: 220, position: position, margin: 0)
            XCTAssertFalse(
                frame.intersects(gap),
                "\(position) frame \(frame) overlaps the notch gap \(gap)"
            )
            XCTAssertTrue(row.contains(frame), "\(position) frame \(frame) escaped the menu bar row \(row)")
        }
    }

    func testCenterSitsInsideTheNotchGap() {
        let frame = placed(width: 200, position: .center)
        XCTAssertEqual(frame.midX, (leftArea.maxX + rightArea.minX) / 2, accuracy: 0.001)
    }

    func testMarginMovesTheStripAwayFromTheNotch() {
        XCTAssertEqual(placed(width: 200, position: .leftOfNotch, margin: 0).maxX, leftArea.maxX)
        XCTAssertEqual(placed(width: 200, position: .leftOfNotch, margin: 40).maxX, leftArea.maxX - 40)
        XCTAssertEqual(placed(width: 200, position: .rightOfNotch, margin: 0).minX, rightArea.minX)
        XCTAssertEqual(placed(width: 200, position: .rightOfNotch, margin: 40).minX, rightArea.minX + 40)
    }

    /// Anchored positions centre vertically in the menu bar row; the strip
    /// holds no user nudge of its own.
    func testAnchoredPlacementCentresVerticallyInTheRow() {
        let level = placed(width: 200, position: .leftOfNotch)
        XCTAssertEqual(level.midY, row.midY, accuracy: 0.001)

        let tall = placed(width: 200, position: .rightOfNotch, notched: false)
        XCTAssertEqual(tall.midY, row.midY, accuracy: 0.001)
    }

    func testPlacementFallsBackToTheRowWhenTheDisplayHasNoNotch() {
        // AppKit reports empty auxiliary rects on a plain display, so the strip
        // must fall back to the row edges rather than collapsing to zero width.
        let left = placed(width: 200, position: .leftOfNotch, notched: false)
        XCTAssertEqual(left.minX, row.minX + 6)

        let right = placed(width: 200, position: .rightOfNotch, notched: false)
        XCTAssertEqual(right.maxX, row.maxX - 6)

        let center = placed(width: 200, position: .center, notched: false)
        XCTAssertEqual(center.midX, row.midX, accuracy: 0.001)
    }

    func testEmptyNotchAreasAreTreatedAsNoNotch() {
        let empty = CGRect.zero
        let frame = GlyphStrip.frame(
            contentSize: CGSize(width: 200, height: 32),
            menuBarRow: row,
            leftNotchArea: empty,
            rightNotchArea: empty,
            position: .leftOfNotch,
            margin: 6
        )
        XCTAssertEqual(frame.minX, row.minX + 6)
    }

    func testStripIsClampedInsideTheRowWhenWiderThanTheAnchorSpace() {
        let frame = placed(width: 900, position: .rightOfNotch, margin: 6, notched: false)
        XCTAssertGreaterThanOrEqual(frame.minX, row.minX)
        XCTAssertLessThanOrEqual(frame.maxX, row.maxX)
    }

    /// Non-notch secondary display: the row starts at a non-zero x, and all
    /// three positions must still anchor to *that* row — `.center` in
    /// particular centres on the row's midpoint, not on the screen origin.
    func testNonNotchPositionsAnchorToAnOffsetRow() {
        let offsetRow = CGRect(x: 1920, y: 1085, width: 2560, height: 32)
        func placedOnOffsetRow(width: CGFloat, position: GlyphStripPosition) -> CGRect {
            GlyphStrip.frame(
                contentSize: CGSize(width: width, height: offsetRow.height),
                menuBarRow: offsetRow,
                leftNotchArea: nil,
                rightNotchArea: nil,
                position: position,
                margin: 6
            )
        }

        let left = placedOnOffsetRow(width: 200, position: .leftOfNotch)
        XCTAssertEqual(left.minX, offsetRow.minX + 6)

        let center = placedOnOffsetRow(width: 200, position: .center)
        XCTAssertEqual(center.midX, offsetRow.midX, accuracy: 0.001)

        let right = placedOnOffsetRow(width: 200, position: .rightOfNotch)
        XCTAssertEqual(right.maxX, offsetRow.maxX - 6)

        for frame in [left, center, right] {
            XCTAssertTrue(offsetRow.contains(frame), "\(frame) escaped the offset row \(offsetRow)")
        }
    }

    // MARK: - Custom placement

    func testCustomPositionUsesFractionsOfTheSpareArea() {
        let frame = placed(width: 200, position: .custom, xFraction: 0.5)
        // (1728 - 200) / 2
        XCTAssertEqual(frame.minX, 764, accuracy: 0.001)
        // Margin does not apply to free placement.
        XCTAssertEqual(placed(width: 200, position: .custom, margin: 40, xFraction: 0.5), frame)
    }

    func testCustomFractionsAreClampedInsideTheArea() {
        let tooFarRight = placed(width: 200, position: .custom, xFraction: 2)
        XCTAssertEqual(tooFarRight.maxX, row.maxX)

        let tooFarLeft = placed(width: 200, position: .custom, xFraction: -1)
        XCTAssertEqual(tooFarLeft.minX, row.minX)
    }

    func testCustomPositionIgnoresNotchAreas() {
        let frame = placed(width: 200, position: .custom, xFraction: 0.5)
        XCTAssertEqual(frame.minX, 764, accuracy: 0.001, "custom must not be pulled toward the notch")
    }
}
