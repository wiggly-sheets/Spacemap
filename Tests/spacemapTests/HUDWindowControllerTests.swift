import XCTest
import CoreGraphics
@testable import spacemap


final class MockHUDStateSync: HUDStateSync {
    var currentState: GridState?
    var focusedIndex: Int?
    var pendingFocusedSpaceIndex: Int?
    var isPendingFocusValid = false

    private(set) var fetchCallCount = 0
    private(set) var refreshCallCount = 0
    private(set) var reloadConfigCallCount = 0
    private(set) var clearPendingFocusCallCount = 0
    private(set) var cancelPendingFetchCallCount = 0
    private(set) var updateFocusedIndexCallCount = 0
    var updateFocusedIndexResult: GridState?

    func updateFocusedIndex(_ index: Int) -> GridState? {
        updateFocusedIndexCallCount += 1
        return updateFocusedIndexResult
    }

    func fetch(completion: @escaping () -> Void) {
        fetchCallCount += 1
        completion()
    }

    func fetch(completion: @escaping () -> Void, replacingFocusedIndex: Int?) {
        fetchCallCount += 1
        completion()
    }

    func refresh(completion: @escaping () -> Void) {
        refreshCallCount += 1
        completion()
    }

    func clearPendingFocus() {
        clearPendingFocusCallCount += 1
    }

    func cancelPendingFetch() {
        cancelPendingFetchCallCount += 1
    }

    func reloadConfig() {
        reloadConfigCallCount += 1
    }
}


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
        let stateSync = MockHUDStateSync()
        let state = cannedState()
        stateSync.currentState = state
        let services = SpacemapServices(
            yabaiService: yabaiService,
            alertsService: Alerts()
        )
        let controller = HUDWindowController(services: services, hudStateSync: stateSync)
        let queried = expectation(description: "focused window queried")

        controller.show()
        DispatchQueue.main.async {
            XCTAssertEqual(controller.focusedWindowIDAtOpen, 77)
            controller.updateCellFrames(state: state)
            XCTAssertEqual(controller.focusedWindowIDAtOpen, 77)
            queried.fulfill()
        }
        waitForExpectations(timeout: 1)

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
}
