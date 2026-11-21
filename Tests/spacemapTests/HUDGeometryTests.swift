import XCTest
import CoreGraphics
@testable import spacemap

final class ScreenContextGeometryTests: XCTestCase {

    /// uiScale 0.5 → scale 2.25: cell 180×112.5, gap 13.5, pad 27.
    private func config(cols: Int = 2) -> SpacemapConfig {
        var config = SpacemapConfig.default
        config.cols = cols
        config.uiScale = 0.5
        return config
    }

    func testCellFramesUsePanelTopWithoutAddingCellHeight() {
        // Panel in AppKit coords: origin bottom-left, maxY 500.
        let panelFrame = CGRect(x: 100, y: 200, width: 500, height: 300)
        let quartzMaxY: CGFloat = 1440

        let frames = ScreenContext.cellFrames(
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

        let frames = ScreenContext.cellFrames(
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
        XCTAssertTrue(ScreenContext.cellFrames(
            for: [],
            panelFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            config: config(),
            quartzMaxY: 1000
        ).isEmpty)
    }

    func testCellFramesClampColumnsToCellCount() {
        let frames = ScreenContext.cellFrames(
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
            ScreenContext.quartzPoint(fromAppKit: CGPoint(x: 10, y: 100), quartzMaxY: 1440),
            CGPoint(x: 10, y: 1340)
        )
    }

    func testQuartzFlipIsItsOwnInverse() {
        let quartzMaxY: CGFloat = 1080
        let quartz = CGRect(x: 100, y: 200, width: 800, height: 600)

        let appKit = ScreenContext.appKitFrame(forQuartzFrame: quartz, quartzMaxY: quartzMaxY)
        XCTAssertEqual(appKit, CGRect(x: 100, y: 280, width: 800, height: 600))
        XCTAssertEqual(
            ScreenContext.appKitFrame(forQuartzFrame: appKit, quartzMaxY: quartzMaxY),
            quartz
        )

        let point = CGPoint(x: 10, y: 100)
        let flipped = ScreenContext.quartzPoint(fromAppKit: point, quartzMaxY: quartzMaxY)
        XCTAssertEqual(flipped, CGPoint(x: 10, y: 980))
        XCTAssertEqual(
            ScreenContext.quartzPoint(fromAppKit: flipped, quartzMaxY: quartzMaxY),
            point
        )
    }

    func testMenuBarRowWithoutScreenUsesTheFallbackHeight() {
        XCTAssertEqual(ScreenContext.menuBarRow(on: nil), CGRect(x: 0, y: 0, width: 0, height: 24))
    }

    func testBestScreenIndexAcceptsNearFramesWithinToleranceAndRejectsStaleOnes() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let near = CGRect(x: 4, y: -3, width: 1920, height: 1076)
        let stale = CGRect(x: 0, y: 2400, width: 1920, height: 1080)

        XCTAssertEqual(ScreenContext.bestScreenIndex(for: near, screenFrames: [primary]), 0)
        XCTAssertNil(
            ScreenContext.bestScreenIndex(for: stale, screenFrames: [primary]),
            "a display frame beyond the tolerance is stale, not the main screen"
        )
    }

    func testSafeScreenFrameReservesOnlyDockLikeEdgeObstacles() {
        let full = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let dock = CGRect(x: 200, y: 0, width: 1040, height: 60)
        // A floating window and a corner window are not edge furniture.
        let floating = CGRect(x: 500, y: 300, width: 400, height: 300)
        let corner = CGRect(x: 0, y: 0, width: 200, height: 200)

        let safe = ScreenContext.safeScreenFrame(
            visibleFrame: visible,
            screenFrame: full,
            obstacles: [floating, corner, dock]
        )

        XCTAssertEqual(safe.minY, 64, accuracy: 0.0001, "the dock plus a 4pt gap")
        XCTAssertEqual(safe.width, 1440, accuracy: 0.0001, "side and floating windows change nothing")
    }

    func testMissionControlNeedsFullScreenWindowManagerShield() {
        let screen = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        func window(layer: Int, width: CGFloat, height: CGFloat) -> [String: Any] {
            [
                kCGWindowLayer as String: layer,
                kCGWindowOwnerPID as String: 1,
                kCGWindowBounds as String: [
                    "X": 0, "Y": 0, "Width": width, "Height": height,
                ],
            ]
        }
        let isWindowManager: (pid_t) -> Bool = { _ in true }

        XCTAssertTrue(ScreenContext.isMissionControlActive(
            windows: [window(layer: 19, width: screen.width, height: screen.height)],
            isWindowManager: isWindowManager
        ))
        XCTAssertFalse(ScreenContext.isMissionControlActive(
            windows: [window(layer: 18, width: screen.width, height: screen.height)],
            isWindowManager: isWindowManager
        ), "another layer is not the Mission Control shield")
        XCTAssertFalse(ScreenContext.isMissionControlActive(
            windows: [window(layer: 19, width: 300, height: 200)],
            isWindowManager: isWindowManager
        ), "a small layer-19 window is not a full-screen shield")
        XCTAssertFalse(ScreenContext.isMissionControlActive(
            windows: [window(layer: 19, width: screen.width, height: screen.height)],
            isWindowManager: { _ in false }
        ), "a shield from another process is ignored")
    }
}
