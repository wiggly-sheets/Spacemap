import XCTest
import CoreGraphics
import SwiftUI
@testable import spacemap

final class CellViewGeometryTests: CellViewGridViewTestCase {
    func testSpaceNumberPositionScalesWithHUD() {
        XCTAssertEqual(GridLayout.spaceNumberPosition(for: 0.5), CGPoint(x: 4, y: 5))
        XCTAssertEqual(GridLayout.spaceNumberPosition(for: 1), CGPoint(x: 8, y: 10))
        XCTAssertEqual(GridLayout.spaceNumberPosition(for: 4), CGPoint(x: 32, y: 40))
    }

    func testSpaceNamePositionStaysCenteredAcrossCellSizes() {
        XCTAssertEqual(
            GridLayout.spaceNamePosition(in: CGSize(width: 40, height: 25)),
            CGPoint(x: 20, y: 12.5)
        )
        XCTAssertEqual(
            GridLayout.spaceNamePosition(in: CGSize(width: 320, height: 200)),
            CGPoint(x: 160, y: 100)
        )
    }

    func testScaledWindowFramePreservesRectangleGeometry() throws {
        let frame = try XCTUnwrap(GridLayout.scaledWindowFrame(
            windowFrame: CGRect(x: 960, y: 0, width: 960, height: 540),
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            cellSize: CGSize(width: 80, height: 50)
        ))

        XCTAssertEqual(frame, CGRect(x: 40, y: 0, width: 40, height: 25))
    }

    func testHybridIconSizeKeepsSameProportionAcrossUIScales() {
        let baseSize = GridLayout.hybridIconSize(
            uiScale: 1,
            windowFrame: CGRect(x: 0, y: 0, width: 80, height: 50)
        )
        let largeSize = GridLayout.hybridIconSize(
            uiScale: 4,
            windowFrame: CGRect(x: 0, y: 0, width: 320, height: 200)
        )

        XCTAssertEqual(baseSize, 26.25, accuracy: 0.001)
        XCTAssertEqual(largeSize, 105, accuracy: 0.001)
        XCTAssertEqual(largeSize / baseSize, 4, accuracy: 0.001)
    }

    func testHybridIconSizeCapsProportionallyInsideSmallRectangles() {
        let baseSize = GridLayout.hybridIconSize(
            uiScale: 1,
            windowFrame: CGRect(x: 0, y: 0, width: 8, height: 6)
        )
        let largeSize = GridLayout.hybridIconSize(
            uiScale: 3,
            windowFrame: CGRect(x: 0, y: 0, width: 24, height: 18)
        )

        XCTAssertEqual(baseSize, 4.5, accuracy: 0.001)
        XCTAssertEqual(largeSize, 13.5, accuracy: 0.001)
        XCTAssertEqual(largeSize / baseSize, 3, accuracy: 0.001)
    }

    func testEffectiveScaleMinimum() {
        let s = GridLayout.effectiveScale(for: 0.0)
        XCTAssertEqual(s, 0.5, accuracy: 0.001)
    }

    func testEffectiveScaleMidpoint() {
        let s = GridLayout.effectiveScale(for: 0.5)
        XCTAssertEqual(s, 2.25, accuracy: 0.001)
    }

    func testEffectiveScaleMaximum() {
        let s = GridLayout.effectiveScale(for: 1.0)
        XCTAssertEqual(s, 4.0, accuracy: 0.001)
    }

    func testEffectiveScaleMonotonic() {
        var prev = GridLayout.effectiveScale(for: 0.0)
        for i in stride(from: 0.1, through: 1.0, by: 0.1) {
            let cur = GridLayout.effectiveScale(for: i)
            XCTAssertGreaterThan(cur, prev, "scale must increase at \(i)")
            prev = cur
        }
    }

    func testEffectiveIconScaleMinimum() {
        let s = GridLayout.effectiveIconScale(for: 0.0)
        XCTAssertEqual(s, 0.2, accuracy: 0.001)
    }

    func testEffectiveIconScaleMaximum() {
        let s = GridLayout.effectiveIconScale(for: 1.0)
        XCTAssertEqual(s, 1.0, accuracy: 0.001)
    }

    func testEffectiveIconScaleMonotonic() {
        var prev = GridLayout.effectiveIconScale(for: 0.0)
        for i in stride(from: 0.1, through: 1.0, by: 0.1) {
            let cur = GridLayout.effectiveIconScale(for: i)
            XCTAssertGreaterThan(cur, prev, "icon scale must increase at \(i)")
            prev = cur
        }
    }

    func testCellWidthRange() {
        let base: CGFloat = 80
        let minW = base * GridLayout.effectiveScale(for: 0.0)
        let maxW = base * GridLayout.effectiveScale(for: 1.0)
        XCTAssertEqual(minW, 40, accuracy: 0.001)
        XCTAssertEqual(maxW, 320, accuracy: 0.001)
    }

}
