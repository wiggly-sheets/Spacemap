import XCTest
import CoreGraphics
@testable import spacemap

final class WindowDragHandlerTests: XCTestCase {

    private var handler: WindowDragHandler!

    override func setUp() {
        super.setUp()
        handler = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            cgWindowListProvider: { [] }
        )
    }

    override func tearDown() {
        handler?.stop()
        handler = nil
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
            (spaceIndex: 0, frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        ]
        handler.cachedWindows = [makeWindow(id: 10, app: "Finder")]
        handler.focusedWindowIDAtOpen = 10
        // Title bar of the window at the top-left of its frame.
        handler.dragStartPoint = CGPoint(x: 50, y: 10)
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
        // Teardown clears hover and would otherwise fulfill the expectation again.
        handler.onHoverCell = nil
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

    func testFindDraggedWindowIDDoesNotFallBackToFocusedWindowWhenAppIsKnown() {
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

        XCTAssertNil(handler.findDraggedWindowID(atCG: CGPoint(x: 50, y: 50)))
        XCTAssertFalse(handler.hasWindowDragEvidence(at: CGPoint(x: 50, y: 10)))
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

    func testFindDraggedWindowIDReturnsNilWhenKnownAppHasNoCachedWindow() {
        handler.frontmostAppAtMouseDown = "Finder"
        handler.focusedWindowIDAtOpen = 99
        handler.cachedWindows = []

        XCTAssertNil(handler.findDraggedWindowID(atCG: CGPoint(x: 50, y: 50)))
    }

    func testFindDraggedWindowIDUsesFocusedFallbackWhenNoAppIsKnown() {
        handler.focusedWindowIDAtOpen = 99
        handler.cachedWindows = []

        XCTAssertEqual(handler.findDraggedWindowID(atCG: CGPoint(x: 50, y: 50)), 99)
    }

    func testDisabledEventTapTypesRequireRecovery() {
        XCTAssertTrue(WindowDragHandler.shouldRecoverEventTap(for: .tapDisabledByTimeout))
        XCTAssertTrue(WindowDragHandler.shouldRecoverEventTap(for: .tapDisabledByUserInput))
        XCTAssertFalse(WindowDragHandler.shouldRecoverEventTap(for: .leftMouseDragged))
    }

    func testStoppedHandlerIgnoresQueuedEventTapRecovery() {
        handler.stop()

        handler.recoverEventTap()

        XCTAssertFalse(handler.isEventTapRequested)
    }

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

        if case let .dragging(isDragging, draggedWindowID, lastHoveredCell, frontmostAppAtMouseDown) = handler.dragState {
            XCTAssertTrue(isDragging)
            XCTAssertEqual(draggedWindowID, 42)
            XCTAssertEqual(lastHoveredCell, 1)
            XCTAssertEqual(frontmostAppAtMouseDown, "Finder")
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

    func testWindowDragEvidenceRequiresTitleBarHit() {
        handler.frontmostAppAtMouseDown = "Finder"
        handler.focusedWindowIDAtOpen = 10
        handler.cachedWindows = [makeWindow(id: 10, app: "Finder")]

        XCTAssertTrue(handler.hasWindowDragEvidence(at: CGPoint(x: 50, y: 10)))
        XCTAssertFalse(handler.hasWindowDragEvidence(at: CGPoint(x: 50, y: 80)))
        XCTAssertFalse(handler.hasWindowDragEvidence(at: CGPoint(x: 200, y: 10)))
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

    func testBackgroundWindowDragUsesWindowServerOwnerPID() {
        handler.stop()
        handler = WindowDragHandler(
            frontmostApplicationName: { "Stale App" },
            frontmostApplicationPID: { 111 },
            permissionCacheInterval: 0,
            cgWindowListProvider: {
                [CGWindowSample(
                    windowID: 5,
                    ownerPID: 222,
                    bounds: CGRect(x: 0, y: 0, width: 300, height: 300)
                )]
            }
        )
        handler.cellFrames = [(1, CGRect(x: 0, y: 0, width: 300, height: 300))]
        handler.cachedWindows = [
            makeWindow(
                id: 1,
                app: "Stale App",
                pid: 111,
                frame: CGRect(x: 0, y: 0, width: 300, height: 300)
            ),
            makeWindow(
                id: 2,
                app: "Background",
                pid: 222,
                frame: CGRect(x: 0, y: 0, width: 300, height: 300)
            )
        ]

        handler.handleMouseDown(at: CGPoint(x: 50, y: 10))
        handler.handleDrag(at: CGPoint(x: 250, y: 250))

        XCTAssertTrue(handler.isDragging)
        XCTAssertEqual(handler.draggedWindowID, 2, "WindowServer pid wins over stale frontmost app")
    }

    func testToolbarBandDragArmsAfterWindowMoves() {
        handler.stop()
        var windows = [
            CGWindowSample(
                windowID: 7,
                ownerPID: 222,
                bounds: CGRect(x: 0, y: 0, width: 400, height: 400)
            )
        ]
        handler = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            frontmostApplicationPID: { 222 },
            cgWindowListProvider: { windows },
            cgWindowSampleInterval: 0
        )
        handler.cellFrames = [(1, CGRect(x: 0, y: 0, width: 400, height: 400))]
        handler.cachedWindows = [
            makeWindow(
                id: 10,
                app: "Finder",
                pid: 222,
                frame: CGRect(x: 0, y: 0, width: 400, height: 400)
            )
        ]
        handler.focusedWindowIDAtOpen = 10

        // Below the 30pt title bar: toolbar geometry alone is not enough.
        handler.handleMouseDown(at: CGPoint(x: 50, y: 60))
        handler.handleDrag(at: CGPoint(x: 250, y: 250))
        XCTAssertFalse(handler.isDragging)

        windows = [
            CGWindowSample(
                windowID: 7,
                ownerPID: 222,
                bounds: CGRect(x: 0, y: 20, width: 400, height: 400)
            )
        ]
        handler.handleDrag(at: CGPoint(x: 250, y: 260))

        XCTAssertTrue(handler.isDragging, "toolbar drag arms once the window actually moves")
    }

    func testEdgeResizeIsNotTreatedAsWindowMove() {
        handler.stop()
        var windows = [
            CGWindowSample(
                windowID: 7,
                ownerPID: 222,
                bounds: CGRect(x: 0, y: 0, width: 400, height: 400)
            )
        ]
        handler = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            frontmostApplicationPID: { 222 },
            cgWindowListProvider: { windows },
            cgWindowSampleInterval: 0
        )
        handler.cellFrames = [(1, CGRect(x: 0, y: 0, width: 600, height: 600))]
        handler.cachedWindows = [
            makeWindow(
                id: 10,
                app: "Finder",
                pid: 222,
                frame: CGRect(x: 0, y: 0, width: 400, height: 400)
            )
        ]
        handler.focusedWindowIDAtOpen = 10

        handler.handleMouseDown(at: CGPoint(x: 390, y: 390))
        handler.handleDrag(at: CGPoint(x: 500, y: 500))
        XCTAssertFalse(handler.isDragging)

        // Resize from the top-left: origin moves, but so does the size.
        windows = [
            CGWindowSample(
                windowID: 7,
                ownerPID: 222,
                bounds: CGRect(x: 10, y: 10, width: 420, height: 420)
            )
        ]
        handler.handleDrag(at: CGPoint(x: 520, y: 520))

        XCTAssertFalse(handler.isDragging, "edge resize is not a window drag")
    }

    func testBorderlessWindowArmsWhenWindowActuallyMoves() {
        handler.stop()
        var windows = [
            CGWindowSample(
                windowID: 9,
                ownerPID: 222,
                bounds: CGRect(x: 0, y: 0, width: 300, height: 500)
            )
        ]
        handler = WindowDragHandler(
            frontmostApplicationName: { "Borderless" },
            frontmostApplicationPID: { nil },
            cgWindowListProvider: { windows },
            cgWindowSampleInterval: 0
        )
        handler.cellFrames = [(1, CGRect(x: 0, y: 0, width: 600, height: 600))]
        handler.cachedWindows = [
            makeWindow(
                id: 20,
                app: "Borderless",
                pid: 222,
                frame: CGRect(x: 0, y: 0, width: 300, height: 500)
            )
        ]

        handler.handleMouseDown(at: CGPoint(x: 50, y: 300))
        handler.handleDrag(at: CGPoint(x: 250, y: 400))
        XCTAssertFalse(handler.isDragging, "content-area start alone is not evidence")

        windows = [
            CGWindowSample(
                windowID: 9,
                ownerPID: 222,
                bounds: CGRect(x: 20, y: 0, width: 300, height: 500)
            )
        ]
        handler.handleDrag(at: CGPoint(x: 250, y: 410))

        XCTAssertTrue(handler.isDragging, "window movement is drag evidence")
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

    func testFindDraggedWindowIDMatchesFrontmostAppByPID() {
        handler.frontmostAppAtMouseDown = "Friendly Name"
        handler.frontmostPIDAtMouseDown = 777
        handler.cachedWindows = [
            makeWindow(
                id: 1,
                app: "Friendly Name",
                pid: 111,
                frame: CGRect(x: 0, y: 0, width: 100, height: 100)
            ),
            makeWindow(
                id: 2,
                app: "Something Else",
                pid: 777,
                frame: CGRect(x: 300, y: 300, width: 100, height: 100)
            )
        ]

        XCTAssertEqual(handler.findDraggedWindowID(atCG: CGPoint(x: 50, y: 50)), 2)
    }

    func testFindDraggedWindowIDPrefersCandidateContainingPoint() {
        handler.frontmostAppAtMouseDown = "Finder"
        handler.frontmostPIDAtMouseDown = 500
        handler.focusedWindowIDAtOpen = 1
        handler.cachedWindows = [
            makeWindow(
                id: 1,
                app: "Finder",
                pid: 500,
                frame: CGRect(x: 0, y: 0, width: 100, height: 100)
            ),
            makeWindow(
                id: 2,
                app: "Finder",
                pid: 500,
                frame: CGRect(x: 100, y: 100, width: 100, height: 100)
            )
        ]

        XCTAssertEqual(handler.findDraggedWindowID(atCG: CGPoint(x: 150, y: 150)), 2)
    }

    func testEventTapCreationFailureRetries() {
        var attempts = 0
        handler.stop()
        handler = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            permissionCheck: { true },
            eventTapFactory: { _, _, _, _, _, _ in
                attempts += 1
                return nil
            }
        )

        handler.start()
        XCTAssertEqual(handler.tapCreationAttempts, 1)
        XCTAssertEqual(handler.tapCreationFailureCount, 1)
        XCTAssertFalse(handler.hasTapContext, "failed install must release its tap context")

        handler.reconcileEventTap()
        XCTAssertEqual(handler.tapCreationAttempts, 2)
        XCTAssertEqual(handler.tapCreationFailureCount, 2)
    }

    func testDragTapWaitsForInputMonitoringPermission() {
        var permitted = false
        var attempts = 0
        handler.stop()
        handler = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            permissionCheck: { permitted },
            permissionCacheInterval: 0,
            eventTapFactory: { _, _, _, _, _, _ in
                attempts += 1
                return nil
            }
        )

        handler.start()
        XCTAssertEqual(attempts, 0)

        permitted = true
        handler.reconcileEventTap()
        XCTAssertEqual(attempts, 1)
    }

    func testStaleRecoveryGenerationIsIgnored() {
        var attempts = 0
        handler.stop()
        handler = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            permissionCheck: { true },
            eventTapFactory: { _, _, _, _, _, _ in
                attempts += 1
                return nil
            }
        )

        handler.start()
        let generation = handler.eventTapGeneration
        XCTAssertTrue(handler.recoverEventTap(expectedGeneration: generation))
        XCTAssertEqual(attempts, 2)

        XCTAssertFalse(handler.recoverEventTap(expectedGeneration: generation - 1))
        XCTAssertEqual(attempts, 2, "a stale recovery must not tear down a newer tap")
    }

    func testResolveDraggedWindowIDUsesFocusedWindowContainingStartForDropOnly() {
        handler.frontmostAppAtMouseDown = "Ghost App"
        handler.focusedWindowIDAtOpen = 99
        handler.cachedWindows = [
            makeWindow(
                id: 1,
                app: "Finder",
                frame: CGRect(x: 0, y: 0, width: 100, height: 100)
            ),
            makeWindow(
                id: 99,
                app: "Other App",
                frame: CGRect(x: 100, y: 100, width: 100, height: 100)
            )
        ]

        XCTAssertNil(
            handler.findDraggedWindowID(atCG: CGPoint(x: 150, y: 150)),
            "evidence identification must not use a cross-app focused fallback"
        )
        XCTAssertEqual(
            handler.resolveDraggedWindowID(atCG: CGPoint(x: 150, y: 150)),
            99,
            "drop resolution may use the focused window containing the start"
        )
        XCTAssertNil(
            handler.resolveDraggedWindowID(atCG: CGPoint(x: 50, y: 50)),
            "focused fallback requires the start point to be inside that window"
        )
    }

    func testUnpermittedReconcileClearsHoverAndDragState() {
        handler.stop()
        handler = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            permissionCheck: { false },
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
        handler.dragStartPoint = CGPoint(x: 10, y: 10)
        handler.reconcileEventTap()

        XCTAssertTrue(didClear)
        XCTAssertFalse(handler.isDragging)
        XCTAssertNil(handler.dragStartPoint)
        XCTAssertNil(handler.lastHoveredCell)
    }

    func testStoppedDragHandlerDeallocates() {
        var local: WindowDragHandler? = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            permissionCheck: { true },
            eventTapFactory: { _, _, _, _, _, _ in nil }
        )
        weak var weakHandler = local

        local?.start()
        XCTAssertFalse(local?.hasTapContext ?? true)
        local?.stop()
        local = nil

        XCTAssertNil(weakHandler)
    }

    private func makeWindow(
        id: Int,
        app: String,
        pid: Int? = nil,
        frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    ) -> YabaiWindow {
        YabaiWindow(
            id: id,
            app: app,
            space: 1,
            frame: .init(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal",
            pid: pid
        )
    }
}
