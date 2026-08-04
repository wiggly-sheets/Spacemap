import XCTest
import CoreGraphics
@testable import spacemap

final class GridStateCoordinatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeCoordinator(
        config: GridConfig = .default,
        stateBuilder: @escaping (GridConfig) -> GridState
    ) -> GridStateCoordinator {
        GridStateCoordinator(config: config, stateBuilder: stateBuilder)
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

    // MARK: - Build state produces correct fields

    func testBuildStatePopulatesFields() throws {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        let windows = [
            YabaiWindow(id: 10, app: "Safari", space: 1, frame: .init(x: 0, y: 0, w: 800, h: 600), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 20, app: "Notes", space: 2, frame: .init(x: 0, y: 0, w: 400, h: 300), isHidden: false, isMinimized: false, subLayer: "normal"),
        ]
        let displays = [
            YabaiDisplay(index: 1, frame: .init(x: 0, y: 0, w: 2560, h: 1440), hasFocus: true),
        ]
        let expected = GridState(
            config: .default,
            spaces: spaces,
            windows: windows,
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: 1,
            displays: displays
        )

        let coordinator = makeCoordinator(stateBuilder: { _ in expected })
        let exp = expectation(description: "fetch completes")

        coordinator.fetch {
            let state = coordinator.latestState
            XCTAssertEqual(state?.focusedIndex, 1)
            XCTAssertEqual(state?.spaces.count, 2)
            XCTAssertEqual(state?.windows.count, 2)
            XCTAssertEqual(state?.displays.count, 1)
            XCTAssertEqual(state?.spaces.first?.index, 1)
            XCTAssertEqual(state?.windows.first?.id, 10)
            XCTAssertEqual(state?.displays.first?.index, 1)
            exp.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - replacingFocusedIndex preserves all fields except focusedIndex

    func testReplacingFocusedIndexPreservesOtherFields() throws {
        let base = cannedState(focusedIndex: 1, spaces: [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
        ])
        let coordinator = makeCoordinator(stateBuilder: { _ in base })

        // Prime the coordinator with the base state
        let primeExp = expectation(description: "prime fetch")
        coordinator.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        // Now do a focused-index-only update
        let updateExp = expectation(description: "focused index update")
        coordinator.fetch(completion: { updateExp.fulfill() }, replacingFocusedIndex: 2)
        waitForExpectations(timeout: 1.0)

        let updated = coordinator.latestState
        XCTAssertEqual(updated?.focusedIndex, 2, "focusedIndex should be updated")
        XCTAssertEqual(updated?.spaces.count, 2, "spaces count should be preserved")
        XCTAssertEqual(updated?.windows.count, 0, "windows count should be preserved")
        XCTAssertEqual(updated?.displays.count, 0, "displays count should be preserved")
        XCTAssertEqual(updated?.spaces.first?.index, 1, "first space index should be preserved")
        XCTAssertEqual(updated?.spaces.last?.index, 2, "last space index should be preserved")
    }

    // MARK: - Debounce: second refresh while one in flight drops stale

    func testDebounceDoesNotDoubleApply() throws {
        var callCount = 0
        let asyncCoordinator = makeCoordinator(stateBuilder: { _ in
            // Simulate async work: sleep briefly then return
            Thread.sleep(forTimeInterval: 0.5)
            callCount += 1
            return self.cannedState(focusedIndex: callCount)
        })

        // Track whether the first completion's side-effect runs
        var firstCompletionCalled = false

        // Fire first fetch — its completion will be dropped by generation guard
        asyncCoordinator.fetch {
            firstCompletionCalled = true
        }

        // Give the first fetch time to start processing on the yabai queue,
        // so that cancel() in the second fetch cannot prevent it from running.
        // This ensures the generation guard (not cancel()) is what drops it.
        Thread.sleep(forTimeInterval: 0.1)

        // Immediately fire second fetch (should supersede first)
        let fetch2Exp = expectation(description: "fetch 2 (authoritative)")
        asyncCoordinator.fetch { fetch2Exp.fulfill() }

        waitForExpectations(timeout: 3.0)
        // The final latestState should reflect the second (authoritative) fetch,
        // NOT the first. Since the builder increments callCount, the second
        // completion returns focusedIndex 2. If the first completion were NOT
        // dropped, focusedIndex would be 1.
        XCTAssertEqual(asyncCoordinator.latestState?.focusedIndex, 2,
            "latestState should reflect the second (non-stale) fetch")
        XCTAssertFalse(firstCompletionCalled,
            "first completion should have been dropped by generation guard")
    }

    // MARK: - fetch/refresh cancellation

    func testFetchRefreshCancellation() throws {
        var callCount = 0
        let asyncCoordinator = makeCoordinator(stateBuilder: { _ in
            Thread.sleep(forTimeInterval: 0.5)
            callCount += 1
            return self.cannedState(focusedIndex: callCount)
        })

        var firstCompletionCalled = false

        asyncCoordinator.fetch {
            firstCompletionCalled = true
        }

        Thread.sleep(forTimeInterval: 0.1)

        let fetch2Exp = expectation(description: "fetch 2 (authoritative)")
        asyncCoordinator.fetch { fetch2Exp.fulfill() }

        waitForExpectations(timeout: 3.0)
        XCTAssertEqual(asyncCoordinator.latestState?.focusedIndex, 2,
            "latestState should reflect the second (non-stale) fetch")
        XCTAssertFalse(firstCompletionCalled,
            "first completion should have been dropped by generation guard")
    }

    // MARK: - Pending focus preservation

    func testPendingFocusPreservedUntilRealFetchConfirms() throws {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        let baseState = cannedState(focusedIndex: 1, spaces: spaces)
        let coordinator = makeCoordinator(stateBuilder: { _ in baseState })

        // Prime
        let primeExp = expectation(description: "prime")
        coordinator.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        // Navigate optimistically to space 2
        let optimistic = coordinator.updateFocusedIndex(2)
        XCTAssertEqual(optimistic?.focusedIndex, 2, "optimistic state should have focusedIndex 2")
        XCTAssertEqual(coordinator.latestState?.focusedIndex, 2, "latestState should reflect optimistic focus")
        XCTAssertTrue(coordinator.isPendingFocusValid, "pending focus should be valid")

        // A refresh that fetches real state (still focusedIndex 1 from yabai)
        // should preserve the optimistic focus since pending is still valid.
        let refreshExp = expectation(description: "refresh")
        coordinator.refresh { refreshExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        // The real fetch returned focusedIndex 1, but pending focus (2) is still valid.
        // statePreservingPendingFocus should keep the optimistic focus.
        XCTAssertEqual(coordinator.latestState?.focusedIndex, 2,
            "pending focus should be preserved through refresh until confirmed")

        // Now simulate yabai confirming focus changed to 2
        let confirmedState = cannedState(focusedIndex: 2, spaces: spaces)
        let confirmedCoordinator = makeCoordinator(stateBuilder: { _ in confirmedState })
        let confirmedPrimeExp = expectation(description: "confirmed prime")
        confirmedCoordinator.fetch { confirmedPrimeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        // Navigate optimistically to 2 (same as yabai)
        _ = confirmedCoordinator.updateFocusedIndex(2)

        // Refresh — yabai now confirms focusedIndex 2
        let confirmedRefreshExp = expectation(description: "confirmed refresh")
        confirmedCoordinator.refresh { confirmedRefreshExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        // Since state.focusedIndex == pending, pending focus should be cleared
        XCTAssertEqual(confirmedCoordinator.pendingFocusedSpaceIndex, nil,
            "pending focus should be cleared when yabai confirms")
        XCTAssertEqual(confirmedCoordinator.latestState?.focusedIndex, 2)
    }

    // MARK: - Transitions: idle → fetching → ready

    func testPhaseTransitions() throws {
        let coordinator = makeCoordinator(stateBuilder: { _ in self.cannedState() })

        XCTAssertEqual(coordinator.phase, .idle, "initial phase should be idle")

        let exp = expectation(description: "fetch")
        coordinator.fetch { exp.fulfill() }

        // Phase should be fetching immediately
        XCTAssertEqual(coordinator.phase, .fetching, "phase should be fetching after fetch()")

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(coordinator.phase, .ready, "phase should be ready after completion")
        XCTAssertNotNil(coordinator.latestState, "latestState should be non-nil after fetch")
    }

    // MARK: - state(withFocusedIndex:) derivation

    func testStateWithFocusedIndexDerivesCorrectly() throws {
        let base = cannedState(focusedIndex: 1, spaces: [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
        ])
        let coordinator = makeCoordinator(stateBuilder: { _ in base })

        // Prime
        let primeExp = expectation(description: "prime")
        coordinator.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        // Derive with different focusedIndex without mutating latestState
        let derived = coordinator.state(withFocusedIndex: 2)
        XCTAssertEqual(derived?.focusedIndex, 2, "derived state should have focusedIndex 2")
        XCTAssertEqual(derived?.spaces.count, 1, "derived state should preserve spaces")

        // latestState itself should be unchanged
        XCTAssertEqual(coordinator.latestState?.focusedIndex, 1, "latestState should not be mutated")
    }

    // MARK: - cancelPendingFetch keeps last state

    func testCancelPendingFetchKeepsLastState() throws {
        let coordinator = makeCoordinator(stateBuilder: { _ in self.cannedState(focusedIndex: 1) })

        let primeExp = expectation(description: "prime")
        coordinator.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        coordinator.cancelPendingFetch()
        XCTAssertEqual(coordinator.phase, .ready, "phase should stay ready when cancelling with existing state")
        XCTAssertEqual(coordinator.latestState?.focusedIndex, 1, "latestState should be retained")
    }
}