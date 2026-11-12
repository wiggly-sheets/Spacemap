import XCTest
import CoreGraphics
@testable import spacemap

final class HUDGeometryTests: XCTestCase {

    /// uiScale 0.5 → scale 2.25: cell 180×112.5, gap 13.5, pad 27.
    private func config(cols: Int = 2) -> GridConfig {
        var config = GridConfig.default
        config.cols = cols
        config.uiScale = 0.5
        return config
    }

    func testCellFramesUsePanelTopWithoutAddingCellHeight() {
        // Panel in AppKit coords: origin bottom-left, maxY 500.
        let panelFrame = CGRect(x: 100, y: 200, width: 500, height: 300)
        let quartzMaxY: CGFloat = 1440

        let frames = HUDGeometry.cellFrames(
            for: [1, 2, 3],
            panelFrame: panelFrame,
            config: config(),
            quartzMaxY: quartzMaxY
        )

        XCTAssertEqual(frames.map(\.spaceIndex), [1, 2, 3])
        // Local cellFrame(0) = x 20.25, y 20.25; panel top in Quartz = 940.
        XCTAssertEqual(frames[0].frame.origin.x, 120.25, accuracy: 0.0001)
        XCTAssertEqual(frames[0].frame.origin.y, 960.25, accuracy: 0.0001)
        XCTAssertEqual(frames[1].frame.origin.x, 313.75, accuracy: 0.0001)
        XCTAssertEqual(frames[1].frame.origin.y, 960.25, accuracy: 0.0001)
        // Second row is exactly one slot (126) lower, not another 126 more.
        XCTAssertEqual(frames[2].frame.origin.x, 120.25, accuracy: 0.0001)
        XCTAssertEqual(frames[2].frame.origin.y, 1086.25, accuracy: 0.0001)
    }

    func testFirstRowMatchesPanelTopPlusLocalOffset() {
        let panelFrame = CGRect(x: -50, y: 40, width: 400, height: 240)
        let quartzMaxY: CGFloat = 1080
        let config = config()

        let frames = HUDGeometry.cellFrames(
            for: [7],
            panelFrame: panelFrame,
            config: config,
            quartzMaxY: quartzMaxY
        )
        let local = GridLayout.cellFrame(offset: 0, cols: 1, uiScale: config.uiScale)

        XCTAssertEqual(frames[0].frame.origin.x, local.minX - 50, accuracy: 0.0001)
        XCTAssertEqual(
            frames[0].frame.origin.y,
            (quartzMaxY - panelFrame.maxY) + local.minY,
            accuracy: 0.0001
        )
        XCTAssertLessThan(
            frames[0].frame.origin.y,
            quartzMaxY - panelFrame.maxY + local.minY + local.height,
            "hit rect must not be shifted down by its own height"
        )
    }

    func testCellFramesEmptyInputReturnsEmpty() {
        XCTAssertTrue(HUDGeometry.cellFrames(
            for: [],
            panelFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            config: config(),
            quartzMaxY: 1000
        ).isEmpty)
    }

    func testCellFramesClampColumnsToCellCount() {
        let frames = HUDGeometry.cellFrames(
            for: [1, 2],
            panelFrame: CGRect(x: 0, y: 0, width: 500, height: 300),
            config: config(cols: 8),
            quartzMaxY: 1000
        )

        XCTAssertEqual(frames[0].frame.minX, frames[1].frame.minX - 193.5, accuracy: 0.0001)
        XCTAssertEqual(frames[0].frame.minY, frames[1].frame.minY, accuracy: 0.0001)
    }

    func testQuartzPointFlipsAppKitY() {
        XCTAssertEqual(
            HUDGeometry.quartzPoint(fromAppKit: CGPoint(x: 10, y: 100), quartzMaxY: 1440),
            CGPoint(x: 10, y: 1340)
        )
    }
}
