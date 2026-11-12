import XCTest
import CoreGraphics
@testable import spacemap


final class HUDWindowControllerMockDisplayDelegate: HUDDisplayDelegate {
    private(set) var renderCallCount = 0
    private(set) var lastRenderedState: GridState?
    private(set) var updateCellFramesCallCount = 0
    private(set) var lastState: GridState?
    private(set) var showCallCount = 0
    private(set) var hideCallCount = 0

    func render(state: GridState) {
        renderCallCount += 1
        lastRenderedState = state
    }

    func updateCellFrames(state: GridState) {
        updateCellFramesCallCount += 1
        lastState = state
    }

    func show() {
        showCallCount += 1
    }

    func hide() {
        hideCallCount += 1
    }
}


final class HUDWindowControllerTests: XCTestCase {


    private func cannedState(
        focusedIndex: Int? = nil,
        spaces: [YabaiSpace] = [],
        windows: [YabaiWindow] = [],
        displays: [YabaiDisplay] = []
    ) -> GridState {
        GridState(
            config: .default,
            spaces: spaces,
            windows: windows,
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: focusedIndex,
            displays: displays
        )
    }

    private func makeHUDWindowController() -> HUDWindowController {
        HUDWindowController(services: SpacemapServices(
            yabaiService: MockYabaiService(),
            alertsService: Alerts()
        ))
    }


    func testShowSetsIsVisible() throws {
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        controller.show()

        XCTAssertTrue(controller.isVisible, "show() should set isVisible to true")
    }

    func testShowCallsStateSyncFetchAndRenderRefreshed() throws {
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        controller.show()

        XCTAssertTrue(controller.isVisible, "show() should set isVisible to true after fetch")
    }


    func testHideSetsIsVisible() throws {
        let controller = makeHUDWindowController()
        controller.show()
        XCTAssertTrue(controller.isVisible, "HUD should be visible after show()")

        controller.hide()

        XCTAssertFalse(controller.isVisible, "hide() should set isVisible to false")
    }

    func testHideCallsInputStopAndClearsPendingFocus() throws {
        let controller = makeHUDWindowController()
        controller.show()
        XCTAssertTrue(controller.isVisible, "HUD should be visible before hide")

        controller.hide()

        XCTAssertFalse(controller.isVisible, "hide() should set isVisible to false")
    }


    func testToggleSwitchesBetweenShowAndHide() throws {
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        controller.toggle()

        XCTAssertTrue(controller.isVisible, "toggle() when hidden should show the HUD")

        controller.isToggling = false

        controller.toggle()

        XCTAssertFalse(controller.isVisible, "toggle() when visible should hide the HUD")
    }

    func testToggleWhenVisibleCallsHideAndSetsIsVisibleFalse() throws {
        let controller = makeHUDWindowController()
        controller.show()
        XCTAssertTrue(controller.isVisible, "HUD should be visible before toggle")

        controller.toggle()

        XCTAssertFalse(controller.isVisible, "toggle() when visible should hide the HUD")
    }

    func testToggleWhenHiddenCallsShowAndSetsIsVisibleTrue() throws {
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        controller.toggle()

        XCTAssertTrue(controller.isVisible, "toggle() when hidden should show the HUD")
    }


    func testToggleIsNoOpWhenToggling() throws {
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        controller.toggle()
        XCTAssertTrue(controller.isToggling, "isToggling should be true after toggle()")

        controller.toggle()

        XCTAssertTrue(controller.isVisible, "second toggle() should be a no-op, HUD should remain visible")
    }


    func testTogglePinnedPinsTheHUD() throws {
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isPinned, "HUD should start unpinned")

        controller.togglePinned()

        XCTAssertTrue(controller.isPinned, "togglePinned() should pin the HUD")
    }

    func testTogglePinnedTogglesIsPinnedAndManagesAutoHideTimer() throws {
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isPinned, "HUD should start unpinned")

        controller.togglePinned()

        XCTAssertTrue(controller.isPinned, "togglePinned() should set isPinned to true")
    }


    func testPinPinsTheHUD() throws {
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isPinned, "HUD should start unpinned")

        controller.pin()

        XCTAssertTrue(controller.isPinned, "pin() should pin the HUD")
    }

    func testPinSetsIsPinnedTrueAndKeepsHUDVisible() throws {
        let controller = makeHUDWindowController()
        controller.show()
        XCTAssertTrue(controller.isVisible, "HUD should be visible before pin")
        XCTAssertFalse(controller.isPinned, "HUD should start unpinned")

        controller.pin()

        XCTAssertTrue(controller.isPinned, "pin() should set isPinned to true")
        XCTAssertTrue(controller.isVisible, "pin() should keep the HUD visible")
    }

    func testPinningVisibleHUDUsesTheInputPinnedStateAsSourceOfTruth() {
        let controller = makeHUDWindowController()
        controller.show()

        controller.pin()

        XCTAssertTrue(controller.isPinned)
    }

    func testFocusedWindowAtOpenPersistsAcrossFrameUpdatesAndClearsOnHide() {
        let yabaiService = MockYabaiService()
        yabaiService.queryFocusedWindowResult = 77
        let state = cannedState()
        yabaiService.buildGridStateResult = state
        let services = SpacemapServices(
            yabaiService: yabaiService,
            alertsService: Alerts()
        )
        let coordinator = GridStateCoordinator(config: .default, yabaiService: yabaiService)
        let controller = HUDWindowController(services: services, coordinator: coordinator)
        let queried = expectation(description: "focused window queried")

        controller.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(controller.focusedWindowIDAtOpen, 77)
            controller.updateCellFrames(state: state)
            XCTAssertEqual(controller.focusedWindowIDAtOpen, 77)
            queried.fulfill()
        }
        waitForExpectations(timeout: 2)

        controller.hide()
        XCTAssertNil(controller.focusedWindowIDAtOpen)
    }


    func testReloadConfigReloadsTheConfig() throws {
        let controller = makeHUDWindowController()

        controller.reloadConfig()

        XCTAssertFalse(controller.isVisible, "controller should still be hidden after reloadConfig")
    }


    func testRefreshRefreshesStateWhenVisible() throws {
        let controller = makeHUDWindowController()
        controller.show()
        XCTAssertTrue(controller.isVisible, "HUD should be visible")

        controller.refresh()

        XCTAssertTrue(controller.isVisible, "HUD should still be visible after refresh")
    }


    func testRefreshRefreshesCachedFocusWhenNotVisible() throws {
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        controller.refresh()

        XCTAssertFalse(controller.isVisible, "HUD should remain hidden after refresh when not visible")
    }

    func testRefreshWhenNotVisibleAndNoCachedStateCallsPrewarmState() throws {
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        controller.refresh()

        XCTAssertFalse(controller.isVisible, "HUD should remain hidden after refresh when not visible")
    }


    func testNavigateDelegatesToHUDInput() throws {
        let controller = makeHUDWindowController()
        controller.show()
        XCTAssertTrue(controller.isVisible, "HUD should be visible for navigation")

        controller.navigate(direction: .right)

        XCTAssertTrue(controller.isVisible, "HUD should still be visible after navigate")
    }

    func testRecentSpaceFocusUsesLiteralYabaiTarget() {
        let yabaiService = MockYabaiService()
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 3, display: 1, hasFocus: true, isVisible: nil, label: nil)
        ]
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 3, spaces: spaces)
        let coordinator = GridStateCoordinator(config: .default, yabaiService: yabaiService)
        let controller = HUDWindowController(
            services: SpacemapServices(yabaiService: yabaiService, alertsService: Alerts()),
            coordinator: coordinator
        )

        controller.show()
        XCTAssertEqual(yabaiService.focusSpaceTargetCallCount, 0)

        controller.focusRecent()
        XCTAssertEqual(yabaiService.focusSpaceTargetCallCount, 1)
        XCTAssertEqual(yabaiService.lastFocusSpaceTarget, SpaceFocusTarget(argument: "recent"))

        controller.focusRecent()
        XCTAssertEqual(yabaiService.focusSpaceTargetCallCount, 2)
    }

    func testRecentSpaceFocusRunsOffTheMainThreadQueue() {
        let yabaiService = MockYabaiService()
        yabaiService.runsYabaiQueueImmediately = false
        let controller = HUDWindowController(
            services: SpacemapServices(yabaiService: yabaiService, alertsService: Alerts())
        )

        controller.focusRecent()

        XCTAssertEqual(yabaiService.focusSpaceTargetCallCount, 0,
            "focusRecent must not run yabai synchronously on the main thread")
        yabaiService.performPendingYabaiQueueBlocks()
        XCTAssertEqual(yabaiService.focusSpaceTargetCallCount, 1)
        XCTAssertEqual(yabaiService.lastFocusSpaceTarget, SpaceFocusTarget(argument: "recent"))
    }

    func testRecentSpaceFocusRefreshesStateAfterFocusCompletes() {
        let yabaiService = MockYabaiService()
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 3, display: 1, hasFocus: true, isVisible: nil, label: nil)
        ]
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 3, spaces: spaces)
        let controller = HUDWindowController(
            services: SpacemapServices(yabaiService: yabaiService, alertsService: Alerts())
        )
        controller.show()
        let settled = expectation(description: "initial show settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        let buildsBefore = yabaiService.buildGridStateCallCount

        controller.focusRecent()

        let refreshed = expectation(description: "refresh after recent focus")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { refreshed.fulfill() }
        wait(for: [refreshed], timeout: 2)
        XCTAssertGreaterThan(yabaiService.buildGridStateCallCount, buildsBefore,
            "focusRecent must refresh state so the highlight catches up")
    }

    func testShowWiresPanelAndQuartzConverterForCustomDrag() throws {
        let controller = makeHUDWindowController()

        controller.show()

        XCTAssertNotNil(controller.inputPanel,
            "custom-position drag needs the live unified panel")
        let converter = try XCTUnwrap(controller.inputQuartzPointConverter,
            "custom-position drag needs the Quartz point converter")
        let point = CGPoint(x: 25, y: 125)
        XCTAssertEqual(
            converter(point),
            HUDGeometry.quartzPoint(
                fromAppKit: point,
                quartzMaxY: HUDGeometry.mainScreenFrame().maxY
            )
        )
    }

    func testShowSeedsLastFocusedSpaceIndex() {
        let yabaiService = MockYabaiService()
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 3, display: 1, hasFocus: true, isVisible: nil, label: nil)
        ]
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 3, spaces: spaces)
        let coordinator = GridStateCoordinator(config: .default, yabaiService: yabaiService)
        let controller = HUDWindowController(
            services: SpacemapServices(yabaiService: yabaiService, alertsService: Alerts()),
            coordinator: coordinator
        )
        let fetched = expectation(description: "state fetched")
        coordinator.fetch { fetched.fulfill() }
        wait(for: [fetched], timeout: 2)

        controller.show()

        XCTAssertEqual(controller.seededFocusedSpaceIndex, 3,
            "first arrow key must move from the installed focus, not no-op")
    }

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
}
