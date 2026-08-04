import XCTest
import CoreGraphics
@testable import spacemap

final class HUDStateSyncTests: XCTestCase {

    // MARK: - Helpers

    private func makeHUDStateSync(
        coordinatorConfig: GridConfig? = .default,
        buildGridState: @escaping (GridConfig, Int?) -> GridState
    ) -> DefaultHUDStateSync {
        let mock = MockYabaiService()
        mock.buildGridStateClosure = buildGridState
        let coordinator = GridStateCoordinator(config: coordinatorConfig, yabaiService: mock)
        return DefaultHUDStateSync(coordinator: coordinator)
    }

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

    // MARK: - currentState mirrors coordinator's latestState

    func testCurrentStateMirrorsCoordinatorLatestState() throws {
        let state = cannedState(focusedIndex: 2)
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in state })

        let primeExp = expectation(description: "prime fetch")
        hudSync.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(hudSync.currentState, state,
            "currentState should mirror coordinator.latestState")
    }

    // MARK: - focusedIndex derives from currentState

    func testFocusedIndexDerivesFromCurrentState() throws {
        let state = cannedState(focusedIndex: 3)
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in state })

        let primeExp = expectation(description: "prime fetch")
        hudSync.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(hudSync.focusedIndex, 3,
            "focusedIndex should derive from currentState.focusedIndex")
    }

    func testFocusedIndexIsNilWhenNoState() throws {
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in self.cannedState() })

        // Don't prime — latestState is nil
        XCTAssertNil(hudSync.focusedIndex,
            "focusedIndex should be nil when currentState is nil")
    }

    // MARK: - updateFocusedIndex delegates to coordinator

    func testUpdateFocusedIndexDelegatesToCoordinator() throws {
        let state = cannedState(focusedIndex: 1)
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in state })

        let primeExp = expectation(description: "prime fetch")
        hudSync.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        let updated = hudSync.updateFocusedIndex(2)
        XCTAssertEqual(updated?.focusedIndex, 2,
            "updateFocusedIndex should return state with new focusedIndex")
        XCTAssertEqual(hudSync.focusedIndex, 2,
            "focusedIndex should reflect the update")
    }

    // MARK: - fetch delegates to coordinator

    func testFetchDelegatesToCoordinator() throws {
        var fetchCalled = false
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in
            fetchCalled = true
            return self.cannedState(focusedIndex: 1)
        })

        let exp = expectation(description: "fetch completes")
        hudSync.fetch {
            XCTAssertTrue(fetchCalled,
                "fetch should have called the coordinator's stateBuilder")
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    // MARK: - refresh delegates to coordinator

    func testRefreshDelegatesToCoordinator() throws {
        var refreshCalled = false
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in
            refreshCalled = true
            return self.cannedState(focusedIndex: 1)
        })

        // Prime the coordinator first
        let primeExp = expectation(description: "prime fetch")
        hudSync.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        let refreshExp = expectation(description: "refresh completes")
        hudSync.refresh {
            XCTAssertTrue(refreshCalled,
                "refresh should have called the coordinator's stateBuilder")
            refreshExp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    // MARK: - clearPendingFocus delegates to coordinator

    func testClearPendingFocusDelegatesToCoordinator() throws {
        let state = cannedState(focusedIndex: 1)
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in state })

        let primeExp = expectation(description: "prime fetch")
        hudSync.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        // Set a pending focus
        _ = hudSync.updateFocusedIndex(2)
        XCTAssertNotNil(hudSync.pendingFocusedSpaceIndex,
            "pendingFocusedSpaceIndex should be set after updateFocusedIndex")

        // Clear it
        hudSync.clearPendingFocus()
        XCTAssertNil(hudSync.pendingFocusedSpaceIndex,
            "pendingFocusedSpaceIndex should be nil after clearPendingFocus")
    }

    // MARK: - cancelPendingFetch delegates to coordinator

    func testCancelPendingFetchDelegatesToCoordinator() throws {
        let state = cannedState(focusedIndex: 1)
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in state })

        let primeExp = expectation(description: "prime fetch")
        hudSync.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        hudSync.cancelPendingFetch()
        XCTAssertEqual(hudSync.currentState?.focusedIndex, 1,
            "currentState should be retained after cancelPendingFetch")
    }

    // MARK: - reloadConfig updates coordinator's config

    func testReloadConfigUpdatesCoordinatorConfig() throws {
        let hudSync = makeHUDStateSync(coordinatorConfig: nil, buildGridState: { _, _ in self.cannedState() })

        XCTAssertNil(hudSync.coordinator.config,
            "config should be nil before reloadConfig")

        hudSync.reloadConfig()

        XCTAssertNotNil(hudSync.coordinator.config,
            "config should be non-nil after reloadConfig")
        XCTAssertEqual(hudSync.coordinator.config?.cols, Config.load().cols,
            "reloadConfig should update coordinator.config to Config.load()")
    }

    // MARK: - currentState is nil before fetch

    func testCurrentStateIsNilBeforeFetch() throws {
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in self.cannedState() })

        XCTAssertNil(hudSync.currentState,
            "currentState should be nil before fetch is called")
    }

    // MARK: - focusedIndex is nil when state has nil focusedIndex

    func testFocusedIndexIsNilWhenStateHasNilFocusedIndex() throws {
        let state = cannedState(focusedIndex: nil)
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in state })

        let primeExp = expectation(description: "prime fetch")
        hudSync.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        XCTAssertNil(hudSync.focusedIndex,
            "focusedIndex should be nil when currentState has focusedIndex nil")
    }

    // MARK: - updateFocusedIndex with nil index

    func testUpdateFocusedIndexReturnsNilStateWhenIndexIsNil() throws {
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in self.cannedState() })

        // Without a primed state, updateFocusedIndex(nil) returns nil
        let updated = hudSync.updateFocusedIndex(nil)
        XCTAssertNil(updated,
            "updateFocusedIndex(nil) should return nil when no base state exists")
    }

    // MARK: - updateFocusedIndex does not mutate original state

    func testUpdateFocusedIndexDoesNotMutateOriginalState() throws {
        let state = cannedState(focusedIndex: 1)
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in state })

        let primeExp = expectation(description: "prime fetch")
        hudSync.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        // Capture the original state before update
        let originalState = hudSync.currentState
        XCTAssertEqual(originalState?.focusedIndex, 1,
            "original state should have focusedIndex 1 before update")

        // Perform the update
        let updated = hudSync.updateFocusedIndex(2)
        XCTAssertEqual(updated?.focusedIndex, 2,
            "updated state should have focusedIndex 2")

        // The original captured state should be unchanged (value type)
        XCTAssertEqual(originalState?.focusedIndex, 1,
            "original state should not be mutated by updateFocusedIndex")
    }

    // MARK: - fetch with replacingFocusedIndex

    func testFetchWithReplacingFocusedIndex() throws {
        let state = cannedState(focusedIndex: 1)
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in state })

        let primeExp = expectation(description: "prime fetch")
        hudSync.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(hudSync.focusedIndex, 1,
            "focusedIndex should be 1 before replacing fetch")

        let replaceExp = expectation(description: "replace focused index")
        hudSync.fetch(completion: { replaceExp.fulfill() }, replacingFocusedIndex: 3)
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(hudSync.focusedIndex, 3,
            "focusedIndex should be replaced with 3 after replacingFocusedIndex fetch")
    }

    // MARK: - concurrent fetch and refresh

    func testConcurrentFetchAndRefresh() throws {
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in self.cannedState(focusedIndex: 1) })

        // Call fetch and refresh in quick succession
        hudSync.fetch { }
        hudSync.refresh { }

        // Give async operations time to complete
        let exp = expectation(description: "concurrent operations complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 2.0)

        // Verify no crash and final state is valid
        XCTAssertNotNil(hudSync.currentState,
            "currentState should be accessible after concurrent fetch and refresh")
    }

    // MARK: - clearPendingFocus when no pending focus

    func testClearPendingFocusWhenNoPendingFocus() throws {
        let state = cannedState(focusedIndex: 1)
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in state })

        let primeExp = expectation(description: "prime fetch")
        hudSync.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        // No pending focus has been set
        XCTAssertNil(hudSync.pendingFocusedSpaceIndex,
            "pendingFocusedSpaceIndex should be nil before clearPendingFocus")

        // Should not crash
        hudSync.clearPendingFocus()

        XCTAssertNil(hudSync.pendingFocusedSpaceIndex,
            "pendingFocusedSpaceIndex should remain nil after clearPendingFocus with no pending focus")
    }

    // MARK: - cancelPendingFetch preserves currentState

    func testCancelPendingFetchPreservesCurrentState() throws {
        let state = cannedState(focusedIndex: 2)
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in state })

        let primeExp = expectation(description: "prime fetch")
        hudSync.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        XCTAssertNotNil(hudSync.currentState,
            "currentState should be non-nil after priming")

        hudSync.cancelPendingFetch()

        XCTAssertNotNil(hudSync.currentState,
            "currentState should still be accessible after cancelPendingFetch")
        XCTAssertEqual(hudSync.currentState?.focusedIndex, 2,
            "currentState should retain its focusedIndex after cancelPendingFetch")
    }

    // MARK: - reloadConfig when config is already loaded

    func testReloadConfigWhenConfigIsAlreadyLoaded() throws {
        let hudSync = makeHUDStateSync(coordinatorConfig: .default, buildGridState: { _, _ in self.cannedState() })

        XCTAssertNotNil(hudSync.coordinator.config,
            "config should be non-nil before reloadConfig")
        let configBefore = hudSync.coordinator.config

        hudSync.reloadConfig()
        let configAfterFirst = hudSync.coordinator.config
        XCTAssertNotNil(configAfterFirst,
            "config should be non-nil after first reloadConfig")

        hudSync.reloadConfig()
        let configAfterSecond = hudSync.coordinator.config
        XCTAssertNotNil(configAfterSecond,
            "config should be non-nil after second reloadConfig")

        // Both reloads should have updated config to Config.load()
        XCTAssertEqual(configAfterFirst?.cols, Config.load().cols,
            "first reloadConfig should update config to Config.load()")
        XCTAssertEqual(configAfterSecond?.cols, Config.load().cols,
            "second reloadConfig should also update config to Config.load()")
    }

    // MARK: - HUDStateSync protocol conformance

    func testStateSyncProtocolConformance() throws {
        let hudSync = makeHUDStateSync(buildGridState: { _, _ in self.cannedState() })

        // Verify DefaultHUDStateSync can be used as HUDStateSync
        let sync: HUDStateSync = hudSync

        // Verify all protocol requirements are accessible and functional
        XCTAssertNotNil(sync,
            "DefaultHUDStateSync should conform to HUDStateSync")

        // currentState and focusedIndex are readable
        XCTAssertNil(sync.currentState,
            "currentState should be nil before fetch via protocol interface")
        XCTAssertNil(sync.focusedIndex,
            "focusedIndex should be nil before fetch via protocol interface")

        // updateFocusedIndex is callable
        let primeExp = expectation(description: "prime fetch")
        sync.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        let updated = sync.updateFocusedIndex(1)
        XCTAssertEqual(updated?.focusedIndex, 1,
            "updateFocusedIndex should work through protocol interface")

        // clearPendingFocus is callable
        sync.clearPendingFocus()
        XCTAssertNil(sync.pendingFocusedSpaceIndex,
            "clearPendingFocus should work through protocol interface")

        // cancelPendingFetch is callable
        sync.cancelPendingFetch()
        XCTAssertNotNil(sync.currentState,
            "cancelPendingFetch should work through protocol interface")

        // reloadConfig is callable
        sync.reloadConfig()
        XCTAssertNotNil(hudSync.coordinator.config,
            "reloadConfig should work through protocol interface")
    }
}
