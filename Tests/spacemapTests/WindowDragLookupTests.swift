import XCTest
import CoreGraphics
@testable import spacemap

final class WindowDragLookupTests: WindowDragHandlerTestCase {
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


    func testWindowDragEvidenceRequiresTitleBarHit() {
        handler.frontmostAppAtMouseDown = "Finder"
        handler.focusedWindowIDAtOpen = 10
        handler.cachedWindows = [makeWindow(id: 10, app: "Finder")]

        XCTAssertTrue(handler.hasWindowDragEvidence(at: CGPoint(x: 50, y: 10)))
        XCTAssertFalse(handler.hasWindowDragEvidence(at: CGPoint(x: 50, y: 80)))
        XCTAssertFalse(handler.hasWindowDragEvidence(at: CGPoint(x: 200, y: 10)))
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

}
