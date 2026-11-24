import XCTest
import CoreGraphics
@testable import spacemap

final class WindowDragSnapshotTests: WindowDragHandlerTestCase {
    func testDragWaitsForFreshMouseDownSnapshot() throws {
        var requestedGeneration: Int?
        handler.cellFrames = [(1, CGRect(x: 0, y: 0, width: 100, height: 100))]
        handler.focusedWindowIDAtOpen = 10
        handler.cachedWindows = [makeWindow(id: 10, app: "Finder")]
        handler.onRequestDragSnapshot = { requestedGeneration = $0 }

        handler.handleMouseDown(at: CGPoint(x: 10, y: 10))
        handler.handleDrag(at: CGPoint(x: 30, y: 30))
        XCTAssertNil(handler.draggedWindowID)

        handler.applyDragSnapshot(
            focusedWindowID: 20,
            windows: [makeWindow(id: 20, app: "Finder")],
            generation: try XCTUnwrap(requestedGeneration)
        )

        XCTAssertEqual(handler.draggedWindowID, 20)
    }

    func testLateSnapshotMouseUpUsesCachedWindowFallback() {
        handler.cellFrames = [(1, CGRect(x: 0, y: 0, width: 300, height: 300))]
        handler.cachedWindows = [makeWindow(id: 10, app: "Finder")]
        handler.focusedWindowIDAtOpen = 10
        handler.onRequestDragSnapshot = { _ in } // snapshot never arrives

        let dropped = expectation(description: "drop uses cached fallback")
        handler.onDropInCell = { windowID, cell, _ in
            XCTAssertEqual(windowID, 10)
            XCTAssertEqual(cell, 1)
            dropped.fulfill()
        }

        handler.handleMouseDown(at: CGPoint(x: 50, y: 10))
        handler.handleDrag(at: CGPoint(x: 200, y: 200))
        XCTAssertFalse(handler.dragSnapshotReady)
        handler.handleMouseUp(at: CGPoint(x: 200, y: 200), modifiers: [])

        waitForExpectations(timeout: 1.0)
    }

    func testSnapshotForPreviousMouseDownDoesNotMarkNewDragReady() {
        var requested: [Int] = []
        handler.onRequestDragSnapshot = { requested.append($0) }

        handler.handleMouseDown(at: CGPoint(x: 10, y: 10))
        handler.handleMouseDown(at: CGPoint(x: 10, y: 10))
        XCTAssertEqual(requested.count, 2)

        handler.applyDragSnapshot(
            focusedWindowID: 1,
            windows: [makeWindow(id: 1, app: "Finder")],
            generation: requested[0]
        )
        XCTAssertFalse(handler.dragSnapshotReady)

        handler.applyDragSnapshot(
            focusedWindowID: 1,
            windows: [makeWindow(id: 1, app: "Finder")],
            generation: requested[1]
        )
        XCTAssertTrue(handler.dragSnapshotReady)
    }

    func testApplyDragSnapshotAfterDragEndedKeepsReadyState() {
        var generation = 0
        handler.onRequestDragSnapshot = { generation = $0 }
        handler.handleMouseDown(at: CGPoint(x: 10, y: 10))
        XCTAssertFalse(handler.dragSnapshotReady)

        // Drag ended (start cleared) but the snapshot still carries the
        // matching generation, e.g. a teardown-time late apply.
        handler.dragStartPoint = nil
        handler.applyDragSnapshot(
            focusedWindowID: 1,
            windows: [makeWindow(id: 1, app: "Finder")],
            generation: generation
        )

        XCTAssertTrue(handler.dragSnapshotReady)
        XCTAssertNil(handler.draggedWindowID)
        XCTAssertNil(handler.focusedWindowIDAtOpen)
    }

    func testLateSnapshotAfterMouseUpDoesNotRestoreDragState() {
        var generation = 0
        handler.onRequestDragSnapshot = { generation = $0 }
        handler.handleMouseDown(at: CGPoint(x: 10, y: 10))
        handler.handleMouseUp(at: CGPoint(x: 10, y: 10), modifiers: [])
        XCTAssertTrue(handler.dragSnapshotReady)

        handler.applyDragSnapshot(
            focusedWindowID: 1,
            windows: [makeWindow(id: 1, app: "Finder")],
            generation: generation
        )

        XCTAssertTrue(handler.dragSnapshotReady)
        XCTAssertNil(handler.draggedWindowID)
        XCTAssertNil(handler.focusedWindowIDAtOpen)
    }

}
