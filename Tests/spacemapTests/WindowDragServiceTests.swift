import XCTest
import CoreGraphics
@testable import spacemap

final class WindowDragServiceTests: XCTestCase {

    private var handler: WindowDragHandler!
    private var mockYabai: MockYabaiService!

    override func setUp() {
        super.setUp()
        mockYabai = MockYabaiService()
        handler = WindowDragHandler(yabaiService: mockYabai)
    }

    override func tearDown() {
        handler.stop()
        handler = nil
        mockYabai = nil
        super.tearDown()
    }

    // MARK: - updateInput Tests

    func testUpdateInputStoresCellFramesCachedWindowsAndFocusedWindowIDAtOpen() {
        // Given
        let cellFrames = [
            (spaceIndex: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            (spaceIndex: 1, frame: CGRect(x: 100, y: 0, width: 100, height: 100))
        ]
        let cachedWindows = [
            YabaiWindow(
                id: 1,
                app: "Finder",
                space: 1,
                frame: .init(x: 0, y: 0, w: 100, h: 100),
                isHidden: false,
                isMinimized: false,
                subLayer: "",
                pid: nil,
                role: nil,
                subrole: nil,
                isRootWindow: nil,
                hasAXReference: nil,
                isVisible: nil,
                isFloating: nil
            )
        ]
        let focusedWindowIDAtOpen = 1
        let input = WindowDragInput(
            cellFrames: cellFrames,
            cachedWindows: cachedWindows,
            focusedWindowIDAtOpen: focusedWindowIDAtOpen
        )

        // When
        handler.updateInput(input)

        // Then
        XCTAssertEqual(handler.cellFrames.count, cellFrames.count)
        for (lhs, rhs) in zip(handler.cellFrames, cellFrames) {
            XCTAssertEqual(lhs.spaceIndex, rhs.spaceIndex)
            XCTAssertEqual(lhs.frame, rhs.frame)
        }
        XCTAssertEqual(handler.cachedWindows, cachedWindows)
        XCTAssertEqual(handler.focusedWindowIDAtOpen, focusedWindowIDAtOpen)
    }

    // MARK: - Lifecycle Tests

    func testStartAndStopLifecycleWorksWithoutCrashing() {
        // When/Then - should not crash
        handler.start()
        handler.stop()
    }

    // MARK: - Reset Tests

    func testResetClearsAllDragState() {
        // Given - set up drag state
        handler.dragStartPoint = CGPoint(x: 100, y: 200)
        handler.isDragging = true
        handler.draggedWindowID = 42
        handler.lastHoveredCell = 1
        handler.frontmostAppAtMouseDown = "Finder"

        // When
        handler.reset()

        // Then
        XCTAssertNil(handler.dragStartPoint)
        XCTAssertFalse(handler.isDragging)
        XCTAssertNil(handler.draggedWindowID)
        XCTAssertNil(handler.lastHoveredCell)
        XCTAssertNil(handler.frontmostAppAtMouseDown)
    }

    // MARK: - Drag State Tests

    func testDragStateReturnsIdleWhenNoDragInProgress() {
        // Then
        XCTAssertEqual(handler.dragState, .idle)
    }

    // MARK: - Cell Space Index Tests

    func testCellSpaceIndexReturnsCorrectSpaceIndexForPointInsideFrame() {
        // Given
        handler.cellFrames = [
            (spaceIndex: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            (spaceIndex: 1, frame: CGRect(x: 100, y: 0, width: 100, height: 100))
        ]

        // When
        let result = handler.cellSpaceIndex(forCG: CGPoint(x: 50, y: 50))

        // Then
        XCTAssertEqual(result, 0)
    }

    func testCellSpaceIndexReturnsNilForPointOutsideAllFrames() {
        // Given
        handler.cellFrames = [
            (spaceIndex: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        ]

        // When
        let result = handler.cellSpaceIndex(forCG: CGPoint(x: 200, y: 200))

        // Then
        XCTAssertNil(result)
    }

    // MARK: - Find Dragged Window ID Tests

    func testFindDraggedWindowIDReturnsFocusedWindowIDAtOpenWhenNoFrontmostAppMatch() {
        // Given - no frontmost app recorded
        handler.frontmostAppAtMouseDown = nil
        handler.focusedWindowIDAtOpen = 99

        // When
        let result = handler.findDraggedWindowID(atCG: CGPoint(x: 50, y: 50))

        // Then
        XCTAssertEqual(result, 99)
    }

    // MARK: - Mouse Down Tests

    func testHandleMouseDownSetsDragStartPointAndRecordsFrontmostApp() {
        // When
        handler.handleMouseDown(at: CGPoint(x: 123, y: 456))

        // Then
        XCTAssertEqual(handler.dragStartPoint, CGPoint(x: 123, y: 456))
        XCTAssertNotNil(handler.frontmostAppAtMouseDown)
    }

    // MARK: - Mouse Up Tests

    func testHandleMouseUpTriggersOnDropInCellCallbackWithCorrectWindowIDAndSpaceIndex() {
        // Given
        let cellFrames = [
            (spaceIndex: 2, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        ]
        handler.cellFrames = cellFrames
        handler.isDragging = true
        handler.draggedWindowID = 42
        handler.dragStartPoint = CGPoint(x: 10, y: 10)

        let expectation = self.expectation(description: "onDropInCell callback")

        handler.onDropInCell = { windowID, spaceIndex, modifiers in
            XCTAssertEqual(windowID, 42)
            XCTAssertEqual(spaceIndex, 2)
            XCTAssertEqual(modifiers, .maskShift)
            expectation.fulfill()
        }

        // When
        handler.handleMouseUp(at: CGPoint(x: 50, y: 50), modifiers: .maskShift)

        // Then
        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Drag Tests

    func testHandleDragTriggersOnHoverCellCallbackWhenCellChanges() {
        // Given
        let cellFrames = [
            (spaceIndex: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        ]
        handler.cellFrames = cellFrames
        handler.dragStartPoint = CGPoint(x: 10, y: 10)
        handler.isDragging = false

        let expectation = self.expectation(description: "onHoverCell callback")

        handler.onHoverCell = { cell in
            XCTAssertEqual(cell, 0)
            expectation.fulfill()
        }

        // When - drag far enough from start to trigger drag initiation
        handler.handleDrag(at: CGPoint(x: 50, y: 50))

        // Then
        waitForExpectations(timeout: 1.0)
    }
}
