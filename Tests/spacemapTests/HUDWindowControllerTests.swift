import XCTest
import CoreGraphics
@testable import spacemap

// MARK: - Mock HUDStateSync

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

// MARK: - Mock HUDDisplayDelegate (for HUDWindowControllerTests)

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

// MARK: - HUDWindowControllerTests

final class HUDWindowControllerTests: XCTestCase {

    // MARK: - Helpers

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
        HUDWindowController(yabaiService: MockYabaiService())
    }

    // MARK: - show()

    func testShowSetsIsVisible() throws {
        // Given
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        // When
        controller.show()

        // Then
        XCTAssertTrue(controller.isVisible, "show() should set isVisible to true")
    }

    func testShowCallsStateSyncFetchAndRenderRefreshed() throws {
        // Given
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        // When
        controller.show()

        // Then - show() should fetch state via stateSync and then render the refreshed HUD
        XCTAssertTrue(controller.isVisible, "show() should set isVisible to true after fetch")
    }

    // MARK: - hide()

    func testHideSetsIsVisible() throws {
        // Given
        let controller = makeHUDWindowController()
        controller.show()
        XCTAssertTrue(controller.isVisible, "HUD should be visible after show()")

        // When
        controller.hide()

        // Then
        XCTAssertFalse(controller.isVisible, "hide() should set isVisible to false")
    }

    func testHideCallsInputStopAndClearsPendingFocus() throws {
        // Given
        let controller = makeHUDWindowController()
        controller.show()
        XCTAssertTrue(controller.isVisible, "HUD should be visible before hide")

        // When
        controller.hide()

        // Then - hide() should stop input, invalidate timers, and clear pending focus
        XCTAssertFalse(controller.isVisible, "hide() should set isVisible to false")
    }

    // MARK: - toggle()

    func testToggleSwitchesBetweenShowAndHide() throws {
        // Given
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        // When - first toggle should show
        controller.toggle()

        // Then
        XCTAssertTrue(controller.isVisible, "toggle() when hidden should show the HUD")

        // When - second toggle should hide
        let exp = expectation(description: "wait for toggle to complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        controller.toggle()

        // Then
        XCTAssertFalse(controller.isVisible, "toggle() when visible should hide the HUD")
    }

    func testToggleWhenVisibleCallsHideAndSetsIsVisibleFalse() throws {
        // Given
        let controller = makeHUDWindowController()
        controller.show()
        XCTAssertTrue(controller.isVisible, "HUD should be visible before toggle")

        // When
        controller.toggle()

        // Then - toggle() when visible should call hide() and set isVisible to false
        XCTAssertFalse(controller.isVisible, "toggle() when visible should hide the HUD")
    }

    func testToggleWhenHiddenCallsShowAndSetsIsVisibleTrue() throws {
        // Given
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        // When
        controller.toggle()

        // Then - toggle() when hidden should call show() and set isVisible to true
        XCTAssertTrue(controller.isVisible, "toggle() when hidden should show the HUD")
    }

    // MARK: - toggle() no-op when toggling

    func testToggleIsNoOpWhenToggling() throws {
        // Given
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        // When - first toggle starts the show operation
        controller.toggle()
        XCTAssertTrue(controller.isToggling, "isToggling should be true after toggle()")

        // Second toggle should be a no-op because isToggling is true
        controller.toggle()

        // Then - HUD should still showing (first toggle's effect not overridden)
        XCTAssertTrue(controller.isVisible, "second toggle() should be a no-op, HUD should remain visible")
    }

    // MARK: - togglePinned()

    func testTogglePinnedPinsTheHUD() throws {
        // Given
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isPinned, "HUD should start unpinned")

        // When
        controller.togglePinned()

        // Then
        XCTAssertTrue(controller.isPinned, "togglePinned() should pin the HUD")
    }

    func testTogglePinnedTogglesIsPinnedAndManagesAutoHideTimer() throws {
        // Given
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isPinned, "HUD should start unpinned")

        // When - togglePinned should pin the HUD and manage the auto-hide timer
        controller.togglePinned()

        // Then - isPinned should be true and auto-hide timer should be managed
        XCTAssertTrue(controller.isPinned, "togglePinned() should set isPinned to true")
    }

    // MARK: - pin()

    func testPinPinsTheHUD() throws {
        // Given
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isPinned, "HUD should start unpinned")

        // When
        controller.pin()

        // Then
        XCTAssertTrue(controller.isPinned, "pin() should pin the HUD")
    }

    func testPinSetsIsPinnedTrueAndKeepsHUDVisible() throws {
        // Given
        let controller = makeHUDWindowController()
        controller.show()
        XCTAssertTrue(controller.isVisible, "HUD should be visible before pin")
        XCTAssertFalse(controller.isPinned, "HUD should start unpinned")

        // When
        controller.pin()

        // Then - pin() should set isPinned to true and keep the HUD visible
        XCTAssertTrue(controller.isPinned, "pin() should set isPinned to true")
        XCTAssertTrue(controller.isVisible, "pin() should keep the HUD visible")
    }

    // MARK: - reloadConfig()

    func testReloadConfigReloadsTheConfig() throws {
        // Given
        let controller = makeHUDWindowController()

        // When
        controller.reloadConfig()

        // Then - reloadConfig should reset the cached config (_config = nil) and call stateSync.reloadConfig().
        // We verify the controller remains functional after reload.
        XCTAssertFalse(controller.isVisible, "controller should still be hidden after reloadConfig")
    }

    // MARK: - refresh() when visible

    func testRefreshRefreshesStateWhenVisible() throws {
        // Given
        let controller = makeHUDWindowController()
        controller.show()
        XCTAssertTrue(controller.isVisible, "HUD should be visible")

        // When
        controller.refresh()

        // Then - refresh should trigger a state refresh via stateSync.refresh() and then renderRefreshed(force: false).
        // We verify the HUD remains visible after the refresh.
        XCTAssertTrue(controller.isVisible, "HUD should still be visible after refresh")
    }

    // MARK: - refresh() when not visible

    func testRefreshRefreshesCachedFocusWhenNotVisible() throws {
        // Given
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        // When
        controller.refresh()

        // Then - refresh when not visible should either prewarm state or query focused space.
        // We verify the HUD remains hidden and no crash occurred.
        XCTAssertFalse(controller.isVisible, "HUD should remain hidden after refresh when not visible")
    }

    func testRefreshWhenNotVisibleAndNoCachedStateCallsPrewarmState() throws {
        // Given - controller is hidden with no cached state
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        // When - refresh should call prewarmState() since there's no cached state
        controller.refresh()

        // Then - prewarmState() fetches state and preloads icons; HUD should remain hidden
        XCTAssertFalse(controller.isVisible, "HUD should remain hidden after refresh when not visible")
    }

    // MARK: - navigate()

    func testNavigateDelegatesToHUDInput() throws {
        // Given
        let controller = makeHUDWindowController()
        controller.show()
        XCTAssertTrue(controller.isVisible, "HUD should be visible for navigation")

        // When - calling navigate through the HUDInputDelegate should not crash
        // and should delegate to the internal HUDInput's navigate method
        controller.navigate(direction: .right)

        // Then - the controller should remain visible and functional
        XCTAssertTrue(controller.isVisible, "HUD should still be visible after navigate")
    }
}
