import XCTest
import CoreGraphics
@testable import spacemap

final class WindowDragDeliveryTests: WindowDragHandlerTestCase {
    func testStopCancelsQueuedDropDelivery() {
        let dropped = expectation(description: "queued drop is cancelled")
        dropped.isInverted = true
        handler.cellFrames = [(1, CGRect(x: 0, y: 0, width: 300, height: 300))]
        handler.cachedWindows = [makeWindow(id: 10, app: "Finder")]
        handler.focusedWindowIDAtOpen = 10
        handler.onDropInCell = { _, _, _ in dropped.fulfill() }

        handler.handleMouseDown(at: CGPoint(x: 50, y: 10))
        handler.handleDrag(at: CGPoint(x: 250, y: 250))
        // Queue the drop, then stop before the main queue can deliver it.
        handler.handleMouseUp(at: CGPoint(x: 250, y: 250), modifiers: [])
        handler.stop()

        wait(for: [dropped], timeout: 0.1)
    }

    func testStopClearsVisibleHoverSynchronously() {
        handler.cellFrames = [(1, CGRect(x: 0, y: 0, width: 300, height: 300))]
        handler.cachedWindows = [makeWindow(id: 10, app: "Finder")]
        handler.focusedWindowIDAtOpen = 10
        handler.lastHoveredCell = 1
        handler.isDragging = true
        var didClear = false
        var clearedCell: Int?
        handler.onHoverCell = { cell in
            didClear = true
            clearedCell = cell
        }

        handler.stop()

        XCTAssertTrue(didClear)
        XCTAssertNil(clearedCell)
        XCTAssertNil(handler.lastHoveredCell)
    }

    func testResetClearsAllDragState() {
        handler.dragStartPoint = CGPoint(x: 100, y: 200)
        handler.isDragging = true
        handler.draggedWindowID = 42
        handler.lastHoveredCell = 1
        handler.frontmostAppAtMouseDown = "Finder"

        handler.reset()

        XCTAssertNil(handler.dragStartPoint)
        XCTAssertFalse(handler.isDragging)
        XCTAssertNil(handler.draggedWindowID)
        XCTAssertNil(handler.lastHoveredCell)
        XCTAssertNil(handler.frontmostAppAtMouseDown)
    }


    func testHoverDeliveryCoalescesToLatestCell() {
        handler.cellFrames = [
            (0, CGRect(x: 0, y: 0, width: 100, height: 100)),
            (1, CGRect(x: 100, y: 0, width: 100, height: 100)),
            (2, CGRect(x: 200, y: 0, width: 100, height: 100))
        ]
        handler.isDragging = true
        var delivered: [Int?] = []
        let hovered = expectation(description: "coalesced hover")
        handler.onHoverCell = { cell in
            delivered.append(cell)
            hovered.fulfill()
        }

        handler.handleDrag(at: CGPoint(x: 50, y: 50))
        handler.handleDrag(at: CGPoint(x: 150, y: 50))
        handler.handleDrag(at: CGPoint(x: 250, y: 50))

        waitForExpectations(timeout: 1.0)
        handler.onHoverCell = nil
        XCTAssertEqual(delivered, [2])
    }

    func testDropOutsideAllCellsIsCancelled() {
        handler.cellFrames = [(0, CGRect(x: 0, y: 0, width: 100, height: 100))]
        handler.isDragging = true
        handler.draggedWindowID = 42
        handler.dragStartPoint = CGPoint(x: 10, y: 10)

        let dropped = expectation(description: "drop outside cells is cancelled")
        dropped.isInverted = true
        handler.onDropInCell = { _, _, _ in dropped.fulfill() }

        handler.handleMouseUp(at: CGPoint(x: 200, y: 200), modifiers: [])

        wait(for: [dropped], timeout: 0.2)
    }

    func testContentAreaDragDoesNotArmHoverOrDrop() {
        handler.cellFrames = [(1, CGRect(x: 0, y: 0, width: 300, height: 300))]
        handler.cachedWindows = [makeWindow(id: 10, app: "Finder")]
        handler.focusedWindowIDAtOpen = 10

        let hovered = expectation(description: "content drag must not hover")
        hovered.isInverted = true
        let dropped = expectation(description: "content drag must not drop")
        dropped.isInverted = true
        handler.onHoverCell = { _ in hovered.fulfill() }
        handler.onDropInCell = { _, _, _ in dropped.fulfill() }

        // Text selection: mouse-down in the window body, not its title bar.
        handler.handleMouseDown(at: CGPoint(x: 50, y: 80))
        handler.handleDrag(at: CGPoint(x: 250, y: 250))
        XCTAssertFalse(handler.isDragging)
        handler.handleMouseUp(at: CGPoint(x: 250, y: 250), modifiers: [])

        wait(for: [hovered, dropped], timeout: 0.2)
    }

    func testRecoveryClearsHoverBeforeResetting() {
        handler.stop()
        handler = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            permissionCheck: { true },
            permissionCacheInterval: 0,
            eventTapFactory: { _, _, _, _, _, _ in nil },
            cgWindowListProvider: { [] }
        )
        var didClear = false
        handler.onHoverCell = { cell in
            if cell == nil { didClear = true }
        }

        handler.start()
        handler.isDragging = true
        handler.lastHoveredCell = 1
        handler.recoverEventTap(expectedGeneration: handler.eventTapGeneration)

        XCTAssertTrue(didClear)
        XCTAssertNil(handler.lastHoveredCell)
    }

}
