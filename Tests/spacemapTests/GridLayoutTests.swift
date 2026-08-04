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
        
        // Verify first cell position
        let firstFrame = frames[0]
        XCTAssertGreaterThan(firstFrame.origin.x, 0, "First cell x should be positive")
        XCTAssertGreaterThan(firstFrame.origin.y, 0, "First cell y should be positive")
        XCTAssertGreaterThan(firstFrame.width, 0, "First cell width should be positive")
        XCTAssertGreaterThan(firstFrame.height, 0, "First cell height should be positive")
    }
    
    func testCellFramesOrder() throws {
        let frames = GridLayout.cellFrames(count: 4, cols: 2, uiScale: 1.0)
        
        // First two cells should be on first row
        XCTAssertLessThan(frames[0].minY, frames[2].minY, "First row should be above second row")
        XCTAssertLessThan(frames[1].minY, frames[3].minY, "First row should be above second row")
        
        // First cell in row should be left of second
        XCTAssertLessThan(frames[0].minX, frames[1].minX, "First col should be left of second")
        XCTAssertLessThan(frames[2].minX, frames[3].minX, "First col should be left of second")
    }
    
    func testHitTest() throws {
        let frames = GridLayout.cellFrames(count: 4, cols: 2, uiScale: 1.0)
        
        // Point in first cell
        let pointInFirst = CGPoint(x: frames[0].midX, y: frames[0].midY)
        let hit = GridLayout.hitTest(point: pointInFirst, in: frames)
        XCTAssertEqual(hit, 0, "Should hit first cell")
        
        // Point outside all cells
        let pointOutside = CGPoint(x: -100, y: -100)
        let noHit = GridLayout.hitTest(point: pointOutside, in: frames)
        XCTAssertNil(noHit, "Should not hit any cell")
    }
    
    func testScale() throws {
        let scale1 = GridLayout.scale(for: 0.0)
        let scale2 = GridLayout.scale(for: 1.0)
        
        XCTAssertEqual(scale1, 0.5, "Scale at 0 should be 0.5")
        XCTAssertEqual(scale2, 4.0, "Scale at 1 should be 4.0")
        
        // Cell size should increase with scale
        let cellSize1 = GridLayout.cellSize(for: 0.0)
        let cellSize2 = GridLayout.cellSize(for: 1.0)
        
        XCTAssertLessThan(cellSize1.width, cellSize2.width, "Cell width should increase with scale")
        XCTAssertLessThan(cellSize1.height, cellSize2.height, "Cell height should increase with scale")
    }
}