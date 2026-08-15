import XCTest
import CoreGraphics
@testable import spacemap

final class GridStateCoordinatorTests: XCTestCase {


    private func makeCoordinator(
        config: GridConfig = .default,
        buildGridState: @escaping (GridConfig, Int?) -> GridState
    ) -> GridStateCoordinator {
        let mock = MockYabaiService()
        mock.buildGridStateClosure = buildGridState
        return GridStateCoordinator(config: config, yabaiService: mock)
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

        let mock = MockYabaiService()
        mock.buildGridStateClosure = { _, _ in expected }
        let coordinator = makeCoordinator(buildGridState: mock.buildGridStateClosure!)
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


    func testReplacingFocusedIndexPreservesOtherFields() throws {
        let base = cannedState(focusedIndex: 1, spaces: [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
        ])
        let mock = MockYabaiService()
        mock.buildGridStateClosure = { _, _ in base }
        let coordinator = makeCoordinator(buildGridState: mock.buildGridStateClosure!)

        let primeExp = expectation(description: "prime fetch")
        coordinator.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

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


    func testDebounceDoesNotDoubleApply() throws {
        var callCount = 0
        let mock = MockYabaiService()
        mock.buildGridStateClosure = { _, _ in
            Thread.sleep(forTimeInterval: 0.5)
            callCount += 1
            return self.cannedState(focusedIndex: callCount)
        }
        let asyncCoordinator = makeCoordinator(buildGridState: mock.buildGridStateClosure!)

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


    func testFetchRefreshCancellation() throws {
        var callCount = 0
        let mock = MockYabaiService()
        mock.buildGridStateClosure = { _, _ in
            Thread.sleep(forTimeInterval: 0.5)
            callCount += 1
            return self.cannedState(focusedIndex: callCount)
        }
        let asyncCoordinator = makeCoordinator(buildGridState: mock.buildGridStateClosure!)

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


    func testPendingFocusPreservedUntilRealFetchConfirms() throws {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        let baseState = cannedState(focusedIndex: 1, spaces: spaces)
        let mock = MockYabaiService()
        mock.buildGridStateClosure = { _, _ in baseState }
        let coordinator = makeCoordinator(buildGridState: mock.buildGridStateClosure!)

        let primeExp = expectation(description: "prime")
        coordinator.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        let optimistic = coordinator.updateFocusedIndex(2)
        XCTAssertEqual(optimistic?.focusedIndex, 2, "optimistic state should have focusedIndex 2")
        XCTAssertEqual(coordinator.latestState?.focusedIndex, 2, "latestState should reflect optimistic focus")
        XCTAssertTrue(coordinator.isPendingFocusValid, "pending focus should be valid")

        let refreshExp = expectation(description: "refresh")
        coordinator.refresh { refreshExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(coordinator.latestState?.focusedIndex, 2,
            "pending focus should be preserved through refresh until confirmed")

        let confirmedState = cannedState(focusedIndex: 2, spaces: spaces)
        let confirmedMock = MockYabaiService()
        confirmedMock.buildGridStateClosure = { _, _ in confirmedState }
        let confirmedCoordinator = makeCoordinator(buildGridState: confirmedMock.buildGridStateClosure!)
        let confirmedPrimeExp = expectation(description: "confirmed prime")
        confirmedCoordinator.fetch { confirmedPrimeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        _ = confirmedCoordinator.updateFocusedIndex(2)

        let confirmedRefreshExp = expectation(description: "confirmed refresh")
        confirmedCoordinator.refresh { confirmedRefreshExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(confirmedCoordinator.pendingFocusedSpaceIndex, nil,
            "pending focus should be cleared when yabai confirms")
        XCTAssertEqual(confirmedCoordinator.latestState?.focusedIndex, 2)
    }


    func testPhaseTransitions() throws {
        let coordinator = makeCoordinator(buildGridState: { _, _ in self.cannedState() })

        XCTAssertEqual(coordinator.phase, .idle, "initial phase should be idle")

        let exp = expectation(description: "fetch")
        coordinator.fetch { exp.fulfill() }

        XCTAssertEqual(coordinator.phase, .fetching, "phase should be fetching after fetch()")

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(coordinator.phase, .ready, "phase should be ready after completion")
        XCTAssertNotNil(coordinator.latestState, "latestState should be non-nil after fetch")
    }


    func testStateWithFocusedIndexDerivesCorrectly() throws {
        let base = cannedState(focusedIndex: 1, spaces: [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
        ])
        let coordinator = makeCoordinator(buildGridState: { _, _ in base })

        let primeExp = expectation(description: "prime")
        coordinator.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        let derived = coordinator.state(withFocusedIndex: 2)
        XCTAssertEqual(derived?.focusedIndex, 2, "derived state should have focusedIndex 2")
        XCTAssertEqual(derived?.spaces.count, 1, "derived state should preserve spaces")

        XCTAssertEqual(coordinator.latestState?.focusedIndex, 1, "latestState should not be mutated")
    }


    func testCancelPendingFetchKeepsLastState() throws {
        let coordinator = makeCoordinator(buildGridState: { _, _ in self.cannedState(focusedIndex: 1) })

        let primeExp = expectation(description: "prime")
        coordinator.fetch { primeExp.fulfill() }
        waitForExpectations(timeout: 1.0)

        coordinator.cancelPendingFetch()
        XCTAssertEqual(coordinator.phase, .ready, "phase should stay ready when cancelling with existing state")
        XCTAssertEqual(coordinator.latestState?.focusedIndex, 1, "latestState should be retained")
    }
}
