import XCTest
@testable import spacemap

final class YabaiClientImplTests: XCTestCase {
    private var client: YabaiClientImpl!

    override func setUp() {
        super.setUp()
        client = YabaiClientImpl()
    }

    override func tearDown() {
        client.resetYabaiProcessCheck()
        client = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private var isYabaiAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/yabai") ||
            FileManager.default.isExecutableFile(atPath: "/usr/local/bin/yabai")
    }

    // MARK: - isYabaiRunning

    func testIsYabaiRunningReturnsTrueWhenRunning() {
        client.yabaiProcessCheck = { true }
        XCTAssertTrue(client.isYabaiRunning())
    }

    func testIsYabaiRunningReturnsFalseWhenNotRunning() {
        client.yabaiProcessCheck = { false }
        XCTAssertFalse(client.isYabaiRunning())
    }

    // MARK: - isYabaiRunning caching

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

    // MARK: - isYabaiRunning forceRefresh

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

    // MARK: - resetYabaiRunningCache

    func testResetYabaiRunningCacheClearsCache() {
        client.yabaiProcessCheck = { true }
        client.resetYabaiRunningCache()

        XCTAssertTrue(client.isYabaiRunning())

        client.yabaiProcessCheck = { false }
        // Still cached as true
        XCTAssertTrue(client.isYabaiRunning())

        client.resetYabaiRunningCache()
        // Cache cleared, returns new result
        XCTAssertFalse(client.isYabaiRunning())
    }

    // MARK: - querySpaces

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

    // MARK: - queryWindows

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

    // MARK: - queryFocusedSpaceIndex

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

    // MARK: - focusSpace

    func testFocusSpaceCallsYabaiCommand() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }
        client.focusSpace(1)
    }

    // MARK: - focusSpaceAsync

    func testFocusSpaceAsyncDispatchesToYabaiQueue() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }

        let expectation = self.expectation(description: "focusSpaceAsync dispatches asynchronously")
        expectation.isInverted = true

        client.focusSpaceAsync(1)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - buildGridState

    func testBuildGridStateReturnsGridStateWhenYabaiRunning() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }
        let config = GridConfig.default
        let state = client.buildGridState(config: config)
        XCTAssertEqual(state.config.cols, config.cols)
        XCTAssertEqual(state.config.rows, config.rows)
    }

    func testBuildGridStateReturnsEmptyStateWhenYabaiNotRunning() throws {
        guard !isYabaiAvailable else {
            throw XCTSkip("yabai is available; cannot test not-running state")
        }
        let config = GridConfig.default
        let state = client.buildGridState(config: config)
        XCTAssertEqual(state.spaces.count, 0)
        XCTAssertEqual(state.windows.count, 0)
        XCTAssertNil(state.focusedIndex)
    }

    // MARK: - registerSignals

    func testRegisterSignalsRegistersSignals() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }
        client.registerSignals(socketPath: "/tmp/spacemap_test.socket")
    }

    // MARK: - removeSignals

    func testRemoveSignalsRemovesSignals() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }
        client.removeSignals()
    }

    // MARK: - moveWindowCreatingSpacesIfNeeded

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
}
