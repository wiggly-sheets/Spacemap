import XCTest
@testable import spacemap

final class YabaiClientQueryTests: YabaiClientImplTestCase {
    func testSpaceSwapPlanMovesBothSidesBeforeAnythingRuns() {
        func window(_ id: Int, space: Int) -> YabaiWindow {
            YabaiWindow(
                id: id,
                app: "App",
                space: space,
                frame: .init(x: 0, y: 0, w: 100, h: 100),
                isHidden: false,
                isMinimized: false,
                subLayer: "normal"
            )
        }
        let plan = YabaiClientImpl.spaceSwapPlan(
            windows: [window(1, space: 1), window(2, space: 1), window(3, space: 3), window(4, space: 4)],
            first: 1,
            second: 3
        )
        XCTAssertEqual(plan, [
            .init(windowID: 1, target: 3),
            .init(windowID: 2, target: 3),
            .init(windowID: 3, target: 1),
        ])
    }

    func testIsYabaiRunningReturnsTrueWhenRunning() {
        client.yabaiProcessCheck = { true }
        XCTAssertTrue(client.isYabaiRunning())
    }

    func testIsYabaiRunningReturnsFalseWhenNotRunning() {
        client.yabaiProcessCheck = { false }
        XCTAssertFalse(client.isYabaiRunning())
    }


    func testIsYabaiRunningCachesResultWithinTTL() {
        var checkCount = 0
        client.yabaiProcessCheck = {
            checkCount += 1
            return true
        }
        client.resetYabaiRunningCache()

        XCTAssertTrue(client.isYabaiRunning())
        XCTAssertTrue(client.isYabaiRunning())
        XCTAssertEqual(checkCount, 1)
    }


    func testIsYabaiRunningForceRefreshBypassesCache() {
        var checkCount = 0
        client.yabaiProcessCheck = {
            checkCount += 1
            return checkCount == 1
        }
        client.resetYabaiRunningCache()

        XCTAssertTrue(client.isYabaiRunning())
        XCTAssertFalse(client.isYabaiRunning(forceRefresh: true))
        XCTAssertEqual(checkCount, 2)
    }


    func testResetYabaiRunningCacheClearsCache() {
        client.yabaiProcessCheck = { true }
        client.resetYabaiRunningCache()

        XCTAssertTrue(client.isYabaiRunning())

        client.yabaiProcessCheck = { false }
        XCTAssertTrue(client.isYabaiRunning())

        client.resetYabaiRunningCache()
        XCTAssertFalse(client.isYabaiRunning())
    }


    func testQuerySpacesReturnsSpacesWhenYabaiRunning() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }
        let spaces = try client.querySpaces()
        XCTAssertNotNil(spaces)
    }

    func testQuerySpacesReturnsEmptyArrayWhenYabaiNotRunning() {
        client.yabaiProcessCheck = { false }
        let spaces = try? client.querySpaces()
        XCTAssertEqual(spaces?.count, 0)
    }


    func testQueryWindowsReturnsWindowsWhenYabaiRunning() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }
        let windows = try client.queryWindows()
        XCTAssertNotNil(windows)
    }

    func testQueryWindowsReturnsEmptyArrayWhenYabaiNotRunning() {
        client.yabaiProcessCheck = { false }
        let windows = try? client.queryWindows()
        XCTAssertEqual(windows?.count, 0)
    }


    func testQueryFocusedSpaceIndexReturnsFocusedIndex() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }
        let index = client.queryFocusedSpaceIndex()
        XCTAssertNotNil(index)
    }

    func testQueryFocusedSpaceIndexReturnsNilWhenYabaiNotRunning() {
        client.yabaiProcessCheck = { false }
        let index = client.queryFocusedSpaceIndex()
        XCTAssertNil(index)
    }


    func testFocusSpaceCallsYabaiCommand() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }
        client.focusSpace(1)
    }


    func testFocusSpaceAsyncDispatchesToYabaiQueue() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }

        let expectation = self.expectation(description: "focusSpaceAsync dispatches asynchronously")

        client.focusSpaceAsync(1)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }


    func testBuildGridStateReturnsGridStateWhenYabaiRunning() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }
        let config = SpacemapConfig.default
        let state = client.buildGridState(config: config)
        XCTAssertEqual(state.config.cols, config.cols)
        XCTAssertEqual(state.config.rows, config.rows)
    }

    func testBuildGridStateReturnsEmptyStateWhenYabaiNotRunning() throws {
        client.yabaiProcessCheck = { false }
        client.resetYabaiRunningCache()
        let config = SpacemapConfig.default
        let state = client.buildGridState(config: config)
        XCTAssertEqual(state.spaces.count, 0)
        XCTAssertEqual(state.windows.count, 0)
        XCTAssertNil(state.focusedIndex)
    }


    func testFullPreviewsRefreshForWindowGeometryAndWorkspaceTopology() {
        XCTAssertEqual(
            client.previewRefreshEvents(refreshWindowGeometry: true),
            client.windowGeometryRefreshEvents + client.workspaceTopologyRefreshEvents
        )
    }

    func testDotPreviewsOnlyRefreshForWorkspaceTopology() {
        XCTAssertEqual(
            client.previewRefreshEvents(refreshWindowGeometry: false),
            client.workspaceTopologyRefreshEvents
        )
    }


    func testMoveWindowCreatingSpacesIfNeededCallsCompletion() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }

        let expectation = self.expectation(description: "moveWindowCreatingSpacesIfNeeded completes")
        client.moveWindowCreatingSpacesIfNeeded(0, toSpace: 1, focusDestination: false) { result in
            XCTAssertNotNil(result)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)
    }


    // MARK: - Tolerant decoding

}
