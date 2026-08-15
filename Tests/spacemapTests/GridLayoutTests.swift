import XCTest
@testable import spacemap

final class GridLayoutTests: XCTestCase {

    func testBasicFunctionality() throws {
        let config = GridConfig.default

        let spacesIndices = GridLayout.visibleSpaceIndices(
            maxSpaces: config.maxSpaces,
            showMode: .active,
            activeIndices: Set([1, 2, 3, 4, 5, 6, 7, 8, 9])
        )

        XCTAssertEqual(spacesIndices.count, 9, "Should show 9 cells for 9 active spaces")
        XCTAssertTrue(spacesIndices.contains(7), "Should include space index 7")
        XCTAssertTrue(spacesIndices.contains(8), "Should include space index 8")
        XCTAssertTrue(spacesIndices.contains(9), "Should include space index 9")
    }

    func testActiveModeShowsOnlyActive() throws {
        let config = GridConfig.default

        let spacesIndices = GridLayout.visibleSpaceIndices(
            maxSpaces: config.maxSpaces,
            showMode: .active,
            activeIndices: Set([1, 3, 5])
        )

        XCTAssertEqual(spacesIndices.count, 3, "Should show only active spaces")
        XCTAssertEqual(spacesIndices.sorted(), [1, 3, 5], "Should contain only active space indices")
    }

    func testAllModeShowsAllSpaces() throws {
        let config = GridConfig.default

        let spacesIndices = GridLayout.visibleSpaceIndices(
            maxSpaces: 5,
            showMode: .all,
            activeIndices: Set([1, 2])
        )

        XCTAssertEqual(spacesIndices.count, 5, "Should show all spaces up to maxSpaces")
        XCTAssertEqual(spacesIndices.sorted(), [1, 2, 3, 4, 5], "Should show all space indices")
    }

    func testGridCellFrames() throws {
        let config = GridConfig.default

        let cells = GridLayout.visibleSpaceIndices(
            maxSpaces: 4,
            showMode: .all,
            activeIndices: Set([1, 2, 3, 4])
        )

        let frames = GridLayout.cellFrames(count: cells.count, cols: 2, uiScale: config.uiScale)

        XCTAssertEqual(frames.count, 4, "Should calculate frames for all cells")

        let firstFrame = frames[0]
        XCTAssertGreaterThan(firstFrame.origin.x, 0, "First cell x should be positive")
        XCTAssertGreaterThan(firstFrame.origin.y, 0, "First cell y should be positive")
        XCTAssertGreaterThan(firstFrame.width, 0, "First cell width should be positive")
        XCTAssertGreaterThan(firstFrame.height, 0, "First cell height should be positive")
    }

    func testCellFramesOrder() throws {
        let frames = GridLayout.cellFrames(count: 4, cols: 2, uiScale: 1.0)

        XCTAssertLessThan(frames[0].minY, frames[2].minY, "First row should be above second row")
        XCTAssertLessThan(frames[1].minY, frames[3].minY, "First row should be above second row")

        XCTAssertLessThan(frames[0].minX, frames[1].minX, "First col should be left of second")
        XCTAssertLessThan(frames[2].minX, frames[3].minX, "First col should be left of second")
    }

    func testHitTest() throws {
        let frames = GridLayout.cellFrames(count: 4, cols: 2, uiScale: 1.0)

        let pointInFirst = CGPoint(x: frames[0].midX, y: frames[0].midY)
        let hit = GridLayout.hitTest(point: pointInFirst, in: frames)
        XCTAssertEqual(hit, 0, "Should hit first cell")

        let pointOutside = CGPoint(x: -100, y: -100)
        let noHit = GridLayout.hitTest(point: pointOutside, in: frames)
        XCTAssertNil(noHit, "Should not hit any cell")
    }

    func testScale() throws {
        let scale1 = GridLayout.scale(for: 0.0)
        let scale2 = GridLayout.scale(for: 1.0)

        XCTAssertEqual(scale1, 0.5, "Scale at 0 should be 0.5")
        XCTAssertEqual(scale2, 4.0, "Scale at 1 should be 4.0")

        let cellSize1 = GridLayout.cellSize(for: 0.0)
        let cellSize2 = GridLayout.cellSize(for: 1.0)

        XCTAssertLessThan(cellSize1.width, cellSize2.width, "Cell width should increase with scale")
        XCTAssertLessThan(cellSize1.height, cellSize2.height, "Cell height should increase with scale")
    }


    func testGapScalesWithUI() {
        let gap0 = GridLayout.gap(for: 0.0)
        let gap1 = GridLayout.gap(for: 1.0)
        XCTAssertEqual(gap0, 3.0, "Gap at uiScale 0 should be 3.0")
        XCTAssertEqual(gap1, 24.0, "Gap at uiScale 1 should be 24.0")
        XCTAssertLessThan(gap0, gap1, "Gap should increase with uiScale")
    }


    func testPaddingScalesWithUI() {
        let pad0 = GridLayout.padding(for: 0.0)
        let pad1 = GridLayout.padding(for: 1.0)
        XCTAssertEqual(pad0, 6.0, "Padding at uiScale 0 should be 6.0")
        XCTAssertEqual(pad1, 48.0, "Padding at uiScale 1 should be 48.0")
        XCTAssertLessThan(pad0, pad1, "Padding should increase with uiScale")
    }

    func testCellSizeForEffectiveScaleDoesNotApplyScaleTwice() {
        let effectiveScale = GridLayout.scale(for: 0.4)
        XCTAssertEqual(
            GridLayout.cellSize(forEffectiveScale: effectiveScale),
            CGSize(width: 80 * effectiveScale, height: 50 * effectiveScale)
        )
    }


    func testSlotSizeCombinesCellAndGap() {
        let slot0 = GridLayout.slotSize(for: 0.0)
        let slot1 = GridLayout.slotSize(for: 1.0)
        let cell0 = GridLayout.cellSize(for: 0.0)
        let gap0 = GridLayout.gap(for: 0.0)
        XCTAssertEqual(slot0.width, cell0.width + gap0, "Slot width should be cell width + gap")
        XCTAssertEqual(slot0.height, cell0.height + gap0, "Slot height should be cell height + gap")
        XCTAssertLessThan(slot0.width, slot1.width, "Slot width should increase with uiScale")
    }


    func testEffectiveScaleMatchesScale() {
        XCTAssertEqual(GridLayout.effectiveScale(for: 0.0), GridLayout.scale(for: 0.0))
        XCTAssertEqual(GridLayout.effectiveScale(for: 1.0), GridLayout.scale(for: 1.0))
        XCTAssertEqual(GridLayout.effectiveScale(for: 0.5), GridLayout.scale(for: 0.5))
    }


    func testEffectiveIconScaleRange() {
        let minScale = GridLayout.effectiveIconScale(for: 0.0)
        let maxScale = GridLayout.effectiveIconScale(for: 1.0)
        XCTAssertEqual(minScale, 0.2, "Icon scale at 0 should be 0.2")
        XCTAssertEqual(maxScale, 1.0, "Icon scale at 1 should be 1.0")
        XCTAssertLessThan(minScale, maxScale, "Icon scale should increase with iconScale")
    }

    func testEffectiveIconScaleMonotonic() {
        var prev = GridLayout.effectiveIconScale(for: 0.0)
        for i in 1...10 {
            let cur = GridLayout.effectiveIconScale(for: Double(i) / 10.0)
            XCTAssertGreaterThanOrEqual(cur, prev, "Icon scale should be monotonic")
            prev = cur
        }
    }


    func testIdealSizeZeroCells() {
        let size = GridLayout.idealSize(visibleIndices: 0, cols: 8, uiScale: 1.0)
        XCTAssertGreaterThan(size.width, 0, "Width should be positive even with 0 cells (padding)")
        XCTAssertGreaterThan(size.height, 0, "Height should be positive even with 0 cells (padding)")
    }

    func testIdealSizeSingleCell() {
        let size = GridLayout.idealSize(visibleIndices: 1, cols: 8, uiScale: 1.0)
        let cellSize = GridLayout.cellSize(for: 1.0)
        XCTAssertGreaterThan(size.width, cellSize.width, "Width should include padding")
        XCTAssertGreaterThan(size.height, cellSize.height, "Height should include padding")
    }

    func testIdealSizeMultipleRows() {
        let size = GridLayout.idealSize(visibleIndices: 16, cols: 8, uiScale: 1.0)
        let size1Row = GridLayout.idealSize(visibleIndices: 8, cols: 8, uiScale: 1.0)
        XCTAssertGreaterThan(size.height, size1Row.height, "2 rows should be taller than 1 row")
    }

    func testIdealSizeRespectsCols() {
        let sizeWide = GridLayout.idealSize(visibleIndices: 8, cols: 8, uiScale: 1.0)
        let sizeNarrow = GridLayout.idealSize(visibleIndices: 8, cols: 4, uiScale: 1.0)
        XCTAssertGreaterThan(sizeNarrow.height, sizeWide.height, "More rows for fewer columns")
        XCTAssertGreaterThan(sizeWide.width, sizeNarrow.width, "More columns should make grid wider")
    }


    func testCellFrameOriginIncreasesWithRow() {
        let frame0 = GridLayout.cellFrame(offset: 0, cols: 2, uiScale: 1.0)
        let frame2 = GridLayout.cellFrame(offset: 2, cols: 2, uiScale: 1.0)
        XCTAssertGreaterThan(frame2.minY, frame0.minY, "Second row should be lower")
    }

    func testCellFrameOriginIncreasesWithCol() {
        let frame0 = GridLayout.cellFrame(offset: 0, cols: 2, uiScale: 1.0)
        let frame1 = GridLayout.cellFrame(offset: 1, cols: 2, uiScale: 1.0)
        XCTAssertGreaterThan(frame1.minX, frame0.minX, "Second column should be further right")
    }

    func testCellFrameSizeIsConsistent() {
        let frame0 = GridLayout.cellFrame(offset: 0, cols: 3, uiScale: 1.0)
        let frame1 = GridLayout.cellFrame(offset: 1, cols: 3, uiScale: 1.0)
        XCTAssertEqual(frame0.width, frame1.width, "All cells should have the same width")
        XCTAssertEqual(frame0.height, frame1.height, "All cells should have the same height")
    }


    func testCellFramesCountMatches() {
        let frames = GridLayout.cellFrames(count: 6, cols: 3, uiScale: 1.0)
        XCTAssertEqual(frames.count, 6, "Should return 6 frames")
    }

    func testCellFramesAreOrdered() {
        let frames = GridLayout.cellFrames(count: 4, cols: 2, uiScale: 1.0)
        XCTAssertLessThan(frames[0].minY, frames[2].minY, "Row 0 above row 1")
        XCTAssertLessThan(frames[1].minY, frames[3].minY, "Row 0 above row 1")
        XCTAssertLessThan(frames[0].minX, frames[1].minX, "Col 0 left of col 1")
        XCTAssertLessThan(frames[2].minX, frames[3].minX, "Col 0 left of col 1")
    }


    func testVisibleSpaceIndicesMaxSpacesClampedTo16() {
        let indices = GridLayout.visibleSpaceIndices(maxSpaces: 32, showMode: .all, activeIndices: [])
        XCTAssertEqual(indices.count, 16, "maxSpaces should be clamped to 16")
    }

    func testVisibleSpaceIndicesEmptyActiveSet() {
        let indices = GridLayout.visibleSpaceIndices(maxSpaces: 5, showMode: .active, activeIndices: [])
        XCTAssertTrue(indices.isEmpty, "No active spaces should return empty")
    }

    func testVisibleSpaceIndicesMaxSpacesOne() {
        let indices = GridLayout.visibleSpaceIndices(maxSpaces: 1, showMode: .all, activeIndices: [])
        XCTAssertEqual(indices, [1], "maxSpaces 1 should return only space 1")
    }


    func testScaledWindowFrameZeroDisplayBoundsReturnsNil() {
        let result = GridLayout.scaledWindowFrame(
            windowFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            displayBounds: CGRect(x: 0, y: 0, width: 0, height: 0),
            cellSize: CGSize(width: 80, height: 50)
        )
        XCTAssertNil(result, "Zero display bounds should return nil")
    }

    func testScaledWindowFrameZeroCellSizeReturnsNil() {
        let result = GridLayout.scaledWindowFrame(
            windowFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            cellSize: CGSize(width: 0, height: 0)
        )
        XCTAssertNil(result, "Zero cell size should return nil")
    }

    func testScaledWindowFramePreservesAspectRatio() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let cellSize = CGSize(width: 192, height: 108)
        let windowFrame = CGRect(x: 0, y: 0, width: 960, height: 540)
        let result = GridLayout.scaledWindowFrame(
            windowFrame: windowFrame,
            displayBounds: displayBounds,
            cellSize: cellSize
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, 96, "Half-width window should scale to half cell width")
        XCTAssertEqual(result?.height, 54, "Half-height window should scale to half cell height")
    }

    func testScaledWindowFrameMinimumSize() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let cellSize = CGSize(width: 192, height: 108)
        let windowFrame = CGRect(x: 0, y: 0, width: 10, height: 10)
        let result = GridLayout.scaledWindowFrame(
            windowFrame: windowFrame,
            displayBounds: displayBounds,
            cellSize: cellSize
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, 2, "Very small window should be clamped to minimum 2")
        XCTAssertEqual(result?.height, 2, "Very small window should be clamped to minimum 2")
    }


    func testHybridIconSizeZeroUIScale() {
        let size = GridLayout.hybridIconSize(uiScale: 0, windowFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(size, 0, "Zero uiScale should return 0")
    }

    func testHybridIconSizeZeroWindowFrame() {
        let size = GridLayout.hybridIconSize(uiScale: 1, windowFrame: CGRect(x: 0, y: 0, width: 0, height: 0))
        XCTAssertEqual(size, 0, "Zero window frame should return 0")
    }

    func testHybridIconSizeCapsAt26_25() {
        let size = GridLayout.hybridIconSize(uiScale: 10, windowFrame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        XCTAssertEqual(size, 262.5, "Icon size should cap at 26.25 * uiScale")
    }


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
            GridLayout.spaceNamePosition(in: CGSize(width: 100, height: 50)),
            CGPoint(x: 50, y: 25)
        )
    }


    func testThumbnailPixelSizeScalesWithUIScale() {
        let size0 = GridLayout.thumbnailPixelSize(for: 0.0, backingScale: 1.0)
        let size1 = GridLayout.thumbnailPixelSize(for: 1.0, backingScale: 1.0)
        XCTAssertLessThan(size0.width, size1.width, "Thumbnail size should increase with uiScale")
        XCTAssertLessThan(size0.height, size1.height, "Thumbnail size should increase with uiScale")
    }

    func testThumbnailPixelSizeScalesWithBackingScale() {
        let size1x = GridLayout.thumbnailPixelSize(for: 1.0, backingScale: 1.0)
        let size2x = GridLayout.thumbnailPixelSize(for: 1.0, backingScale: 2.0)
        XCTAssertEqual(size2x.width, size1x.width * 2, "Thumbnail size should double with 2x backing")
        XCTAssertEqual(size2x.height, size1x.height * 2, "Thumbnail size should double with 2x backing")
    }


    func testWindowIconLayoutsEmptyWindows() {
        let layouts = GridLayout.windowIconLayouts(
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            cellSize: CGSize(width: 192, height: 108)
        )
        XCTAssertTrue(layouts.isEmpty, "Empty windows should return empty layouts")
    }

    func testWindowIconLayoutsZeroCellSize() {
        let layouts = GridLayout.windowIconLayouts(
            windows: [YabaiWindow(id: 1, app: "Test", space: 1, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "normal")],
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            cellSize: CGSize(width: 0, height: 0)
        )
        XCTAssertTrue(layouts.isEmpty, "Zero cell size should return empty layouts")
    }

    func testWindowIconLayoutsZeroDisplayBounds() {
        let layouts = GridLayout.windowIconLayouts(
            windows: [YabaiWindow(id: 1, app: "Test", space: 1, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "normal")],
            displayBounds: CGRect(x: 0, y: 0, width: 0, height: 0),
            cellSize: CGSize(width: 192, height: 108)
        )
        XCTAssertTrue(layouts.isEmpty, "Zero display bounds should return empty layouts")
    }
}
