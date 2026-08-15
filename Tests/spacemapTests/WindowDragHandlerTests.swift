import XCTest
import CoreGraphics
@testable import spacemap

final class WindowDragHandlerTests: XCTestCase {

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


    func testHandleMouseDownSetsDragStartPoint() {
        handler.handleMouseDown(at: CGPoint(x: 100, y: 200))
        XCTAssertEqual(handler.dragStartPoint, CGPoint(x: 100, y: 200))
        XCTAssertFalse(handler.isDragging)
    }

    func testHandleMouseDownRecordsFrontmostApp() {
        handler.handleMouseDown(at: CGPoint(x: 50, y: 50))
        XCTAssertNotNil(handler.frontmostAppAtMouseDown)
    }


    func testHandleDragDoesNotStartDragForSmallMovement() {
        handler.dragStartPoint = CGPoint(x: 100, y: 100)
        handler.handleDrag(at: CGPoint(x: 102, y: 102))
        XCTAssertFalse(handler.isDragging)
        XCTAssertNil(handler.draggedWindowID)
    }

    func testHandleDragStartsDragForLargeMovement() {
        handler.cellFrames = [
            (spaceIndex: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        ]
        handler.dragStartPoint = CGPoint(x: 100, y: 100)
        handler.handleDrag(at: CGPoint(x: 200, y: 200))
        XCTAssertTrue(handler.isDragging)
    }

    func testHandleDragCallsOnHoverCell() {
        let expectation = self.expectation(description: "onHoverCell callback")
        handler.cellFrames = [
            (spaceIndex: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        ]
        handler.dragStartPoint = CGPoint(x: 100, y: 100)
        handler.isDragging = true

        handler.onHoverCell = { cell in
            XCTAssertEqual(cell, 1)
            expectation.fulfill()
        }

        handler.handleDrag(at: CGPoint(x: 50, y: 50))
        waitForExpectations(timeout: 1.0)
    }

    func testHandleDragDoesNotCallOnHoverCellWhenCellUnchanged() {
        let expectation = self.expectation(description: "onHoverCell should not be called")
        expectation.isInverted = true

        handler.cellFrames = [
            (spaceIndex: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        ]
        handler.dragStartPoint = CGPoint(x: 100, y: 100)
        handler.isDragging = true
        handler.lastHoveredCell = 0

        handler.onHoverCell = { _ in
            expectation.fulfill()
        }

        handler.handleDrag(at: CGPoint(x: 50, y: 50))
        waitForExpectations(timeout: 0.5)
    }


    func testHandleMouseUpTriggersOnDropInCell() {
        let expectation = self.expectation(description: "onDropInCell callback")
        handler.cellFrames = [
            (spaceIndex: 2, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        ]
        handler.isDragging = true
        handler.draggedWindowID = 42
        handler.dragStartPoint = CGPoint(x: 10, y: 10)

        handler.onDropInCell = { windowID, spaceIndex, modifiers in
            XCTAssertEqual(windowID, 42)
            XCTAssertEqual(spaceIndex, 2)
            XCTAssertEqual(modifiers, .maskShift)
            expectation.fulfill()
        }

        handler.handleMouseUp(at: CGPoint(x: 50, y: 50), modifiers: .maskShift)
        waitForExpectations(timeout: 1.0)
    }

    func testHandleMouseUpWithNoDragDoesNotTriggerDrop() {
        handler.cellFrames = [
            (spaceIndex: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        ]
        handler.isDragging = false
        handler.draggedWindowID = nil

        handler.onDropInCell = { _, _, _ in
            XCTFail("onDropInCell should not be called when not dragging")
        }

        handler.handleMouseUp(at: CGPoint(x: 50, y: 50), modifiers: [])
    }

    func testHandleMouseUpWithNoHoveredCellClearsHover() {
        handler.cellFrames = [
            (spaceIndex: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        ]
        handler.isDragging = true
        handler.draggedWindowID = 42
        handler.dragStartPoint = CGPoint(x: 10, y: 10)
        handler.lastHoveredCell = 0

        let expectation = self.expectation(description: "onHoverCell nil callback")
        handler.onHoverCell = { cell in
            XCTAssertNil(cell)
            expectation.fulfill()
        }

        handler.handleMouseUp(at: CGPoint(x: 200, y: 200), modifiers: [])
        waitForExpectations(timeout: 1.0)
    }


    func testCellSpaceIndexForPointInsideFrame() {
        handler.cellFrames = [
            (spaceIndex: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            (spaceIndex: 1, frame: CGRect(x: 100, y: 0, width: 100, height: 100))
        ]
        XCTAssertEqual(handler.cellSpaceIndex(forCG: CGPoint(x: 50, y: 50)), 0)
        XCTAssertEqual(handler.cellSpaceIndex(forCG: CGPoint(x: 150, y: 50)), 1)
    }

    func testCellSpaceIndexForPointOutsideAllFrames() {
        handler.cellFrames = [
            (spaceIndex: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        ]
        XCTAssertNil(handler.cellSpaceIndex(forCG: CGPoint(x: 200, y: 200)))
    }

    func testCellSpaceIndexWithEmptyFrames() {
        handler.cellFrames = []
        XCTAssertNil(handler.cellSpaceIndex(forCG: CGPoint(x: 50, y: 50)))
    }


    func testFindDraggedWindowIDReturnsFocusedWindowIDAtOpenWhenNoFrontmostApp() {
        handler.frontmostAppAtMouseDown = nil
        handler.focusedWindowIDAtOpen = 99
        handler.cachedWindows = []

        let result = handler.findDraggedWindowID(atCG: CGPoint(x: 50, y: 50))
        XCTAssertEqual(result, 99)
    }

    func testFindDraggedWindowIDReturnsFocusedWindowIDWhenNoAppMatch() {
        handler.frontmostAppAtMouseDown = "NonExistentApp"
        handler.focusedWindowIDAtOpen = 99
        handler.cachedWindows = [
            YabaiWindow(
                id: 1,
                app: "Finder",
                space: 1,
                frame: .init(x: 0, y: 0, w: 100, h: 100),
                isHidden: false,
                isMinimized: false,
                subLayer: ""
            )
        ]

        let result = handler.findDraggedWindowID(atCG: CGPoint(x: 50, y: 50))
        XCTAssertEqual(result, 99)
    }

    func testFindDraggedWindowIDReturnsSingleWindow() {
        handler.frontmostAppAtMouseDown = "Finder"
        handler.focusedWindowIDAtOpen = nil
        handler.cachedWindows = [
            YabaiWindow(
                id: 42,
                app: "Finder",
                space: 1,
                frame: .init(x: 0, y: 0, w: 100, h: 100),
                isHidden: false,
                isMinimized: false,
                subLayer: ""
            )
        ]

        let result = handler.findDraggedWindowID(atCG: CGPoint(x: 50, y: 50))
        XCTAssertEqual(result, 42)
    }

    func testFindDraggedWindowIDPrefersFocusedWindow() {
        handler.frontmostAppAtMouseDown = "Finder"
        handler.focusedWindowIDAtOpen = 10
        handler.cachedWindows = [
            YabaiWindow(
                id: 10,
                app: "Finder",
                space: 1,
                frame: .init(x: 0, y: 0, w: 100, h: 100),
                isHidden: false,
                isMinimized: false,
                subLayer: ""
            ),
            YabaiWindow(
                id: 20,
                app: "Finder",
                space: 1,
                frame: .init(x: 100, y: 0, w: 100, h: 100),
                isHidden: false,
                isMinimized: false,
                subLayer: ""
            )
        ]

        let result = handler.findDraggedWindowID(atCG: CGPoint(x: 50, y: 50))
        XCTAssertEqual(result, 10)
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


    func testDragStateReturnsIdleWhenNoDragInProgress() {
        XCTAssertEqual(handler.dragState, .idle)
    }

    func testDragStateReturnsDraggingWhenDragInProgress() {
        handler.dragStartPoint = CGPoint(x: 100, y: 100)
        handler.isDragging = true
        handler.draggedWindowID = 42
        handler.lastHoveredCell = 1
        handler.frontmostAppAtMouseDown = "Finder"

        if case .dragging(let state) = handler.dragState {
            XCTAssertTrue(state.isDragging)
            XCTAssertEqual(state.draggedWindowID, 42)
            XCTAssertEqual(state.lastHoveredCell, 1)
            XCTAssertEqual(state.frontmostAppAtMouseDown, "Finder")
        } else {
            XCTFail("Expected dragging state")
        }
    }


    func testUpdateInputStoresCellFramesCachedWindowsAndFocusedWindowIDAtOpen() {
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
                subLayer: ""
            )
        ]
        let focusedWindowIDAtOpen = 1
        let input = WindowDragInput(
            cellFrames: cellFrames,
            cachedWindows: cachedWindows,
            focusedWindowIDAtOpen: focusedWindowIDAtOpen
        )

        handler.updateInput(input)

        XCTAssertEqual(handler.cellFrames.count, cellFrames.count)
        for (lhs, rhs) in zip(handler.cellFrames, cellFrames) {
            XCTAssertEqual(lhs.spaceIndex, rhs.spaceIndex)
            XCTAssertEqual(lhs.frame, rhs.frame)
        }
        XCTAssertEqual(handler.cachedWindows, cachedWindows)
        XCTAssertEqual(handler.focusedWindowIDAtOpen, focusedWindowIDAtOpen)
    }
}
