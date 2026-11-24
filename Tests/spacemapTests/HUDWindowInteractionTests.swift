import XCTest
import CoreGraphics
@testable import spacemap

final class HUDWindowInteractionTests: HUDWindowControllerTestCase {
    func testHoverCellUpdatesOnlyHoverState() {
        let controller = makeHUDWindowController()
        controller.show()
        let display = controller.hudDisplayForTesting
        let renders = display.fullRenderCount
        let iconPreloads = display.iconPreloadCount
        let thumbnailRefreshes = display.thumbnailRefreshCount
        let panelOrigin = controller.inputPanel?.frame.origin

        controller.handleHoverCell(3)

        XCTAssertEqual(display.hoveredCell, 3)
        XCTAssertEqual(display.hoverState.cell, 3)
        XCTAssertEqual(display.fullRenderCount, renders, "hover must not re-render the HUD")
        XCTAssertEqual(display.iconPreloadCount, iconPreloads, "hover must not preload icons")
        XCTAssertEqual(display.thumbnailRefreshCount, thumbnailRefreshes,
            "hover must not refresh thumbnails")
        XCTAssertEqual(controller.inputPanel?.frame.origin, panelOrigin,
            "hover must not move or resize the panel")

        controller.handleHoverCell(nil)
        XCTAssertNil(display.hoveredCell)
    }

    func testDeleteSpaceDestroysTheFocusedSpace() {
        let yabaiService = MockYabaiService()
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: true, isVisible: nil, label: nil)
        ]
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 2, spaces: spaces)
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        ))
        controller.show()
        waitUntil("focus seeded for delete") {
            controller.seededFocusedSpaceIndex == 2
        }
        let buildsBefore = yabaiService.buildGridStateCallCount

        controller.perform(.deleteSpace)

        XCTAssertEqual(yabaiService.destroySpaceCallCount, 1)
        XCTAssertEqual(yabaiService.lastDestroySpaceIndex, 2)
        waitUntil("refresh after the destroy settles") {
            yabaiService.buildGridStateCallCount > buildsBefore
        }
    }

    func testSpaceDropSwapsOnlyWhenTheTargetDiffers() {
        let yabaiService = MockYabaiService()
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        ))
        controller.externalDropTarget = 3

        controller.handleSpaceDrop(source: 2)

        XCTAssertEqual(yabaiService.swapSpacesCallCount, 1)
        XCTAssertEqual(yabaiService.lastSwapSourceIndex, 2)
        XCTAssertEqual(yabaiService.lastSwapTargetIndex, 3)

        controller.handleSpaceDrop(source: 3)
        XCTAssertEqual(yabaiService.swapSpacesCallCount, 1,
            "a drop onto its own space must not swap")
    }

    func testWindowDropMovesWindowsToTheHighlightedTarget() {
        let yabaiService = MockYabaiService()
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        ))
        controller.externalDropTarget = 3

        controller.handleWindowDrop(ids: [7, 8], source: 1)

        XCTAssertEqual(yabaiService.moveWindowCallCount, 1)
        XCTAssertEqual(yabaiService.lastMovedWindowIDs, [7, 8])
        XCTAssertEqual(yabaiService.lastMoveWindowIndex, 3)

        controller.handleWindowDrop(ids: [], source: 1)
        XCTAssertEqual(yabaiService.moveWindowCallCount, 1, "an empty drag must not move windows")
    }

    func testExternalDragHoldsAutoHideUntilItEnds() {
        let controller = makeHUDWindowController()
        controller.show()
        XCTAssertTrue(controller.isAutoHideScheduled, "an unpinned HUD arms auto-hide")

        controller.setExternalDragActive(true)
        XCTAssertNil(controller.externalDropTarget)
        XCTAssertFalse(controller.isAutoHideScheduled, "a strip drag must hold auto-hide")

        controller.setExternalDragActive(false)
        XCTAssertTrue(controller.isAutoHideScheduled, "auto-hide re-arms once the drag ends")
    }
}
