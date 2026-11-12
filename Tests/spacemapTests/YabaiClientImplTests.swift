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


    private var isYabaiAvailable: Bool {
        // Real-desktop coverage is opt-in: an installed yabai on a dev machine
        // otherwise makes these tests depend on the current window layout.
        guard ProcessInfo.processInfo.environment["SPACEMAP_RUN_YABAI_TESTS"] == "1" else { return false }
        let executable = ["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"]
            .first(where: FileManager.default.isExecutableFile(atPath:))
        guard let executable else { return false }
        return (try? YabaiClientImpl.runProcess(
            executable: executable,
            arguments: ["-m", "query", "--spaces"],
            timeout: 1
        )) != nil
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
        let config = GridConfig.default
        let state = client.buildGridState(config: config)
        XCTAssertEqual(state.config.cols, config.cols)
        XCTAssertEqual(state.config.rows, config.rows)
    }

    func testBuildGridStateReturnsEmptyStateWhenYabaiNotRunning() throws {
        client.yabaiProcessCheck = { false }
        client.resetYabaiRunningCache()
        let config = GridConfig.default
        let state = client.buildGridState(config: config)
        XCTAssertEqual(state.spaces.count, 0)
        XCTAssertEqual(state.windows.count, 0)
        XCTAssertNil(state.focusedIndex)
    }


    func testRegisterSignalsRegistersSignals() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }
        client.registerSignals(socketPath: "/tmp/spacemap_test.socket")
    }

    func testFullPreviewsRefreshForWindowGeometryAndWorkspaceTopology() {
        XCTAssertEqual(
            client.previewRefreshEvents(refreshWindowGeometry: true),
            client.windowGeometryRefreshEvents + client.workspaceTopologyRefreshEvents
        )
    }

    func testRefreshSignalActionPreservesNonceWhenPresent() throws {
        let socketPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("smn_\(UUID().uuidString.prefix(8)).sock")
        let noncePath = SpacemapCommand.noncePath(for: socketPath)
        try Data(repeating: 0xab, count: 32).write(to: URL(fileURLWithPath: noncePath), options: .atomic)
        defer { try? FileManager.default.removeItem(atPath: noncePath) }

        let hex = String(repeating: "ab", count: 32)
        XCTAssertEqual(SpacemapCommand.currentNonceHex(for: socketPath), hex)

        let action = client.refreshSignalAction(socketPath: socketPath)

        XCTAssertTrue(action.contains(":\(hex)'"), "nonce must be preserved in the action: \(action)")
        XCTAssertFalse(action.contains("/usr/bin/false"))
    }

    func testRegisterSignalsFailsClosedWhenNonceIsMissing() {
        let socketPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("smnn_\(UUID().uuidString.prefix(8)).sock")
        let noncePath = SpacemapCommand.noncePath(for: socketPath)
        try? FileManager.default.removeItem(atPath: noncePath)
        XCTAssertNotNil(SpacemapCommand.shellQuoted(socketPath),
                        "fixture path must be valid so only the missing nonce is under test")
        XCTAssertNil(SpacemapCommand.currentNonceHex(for: socketPath))

        // Direct callers still get a fail-closed action from the builders.
        XCTAssertEqual(client.refreshSignalAction(socketPath: socketPath), "/usr/bin/false")
        XCTAssertEqual(
            client.spaceChangedSignalAction(socketPath: socketPath, showHUDOnSpaceChange: false),
            "/usr/bin/false"
        )

        client.yabaiProcessCheck = { true }
        client.yabaiExecutableOverride = true
        let commandLock = NSLock()
        var commands: [[String]] = []
        client.commandRunnerOverride = { _, arguments, _ in
            commandLock.lock()
            commands.append(arguments)
            commandLock.unlock()
            return ""
        }

        client.registerSignals(
            socketPath: socketPath,
            showHUDOnSpaceChange: false,
            refreshWorkspacePreviews: true,
            refreshWindowGeometry: true
        )

        commandLock.lock()
        let issued = commands
        commandLock.unlock()
        XCTAssertTrue(issued.isEmpty,
                      "nonce-less registration must not remove or add signals: \(issued)")
    }

    func testRegisterSignalsRegistersNonceActionsWhenPresent() throws {
        let socketPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("smn_\(UUID().uuidString.prefix(8)).sock")
        let noncePath = SpacemapCommand.noncePath(for: socketPath)
        try Data(repeating: 0xcd, count: 32).write(to: URL(fileURLWithPath: noncePath), options: .atomic)
        defer { try? FileManager.default.removeItem(atPath: noncePath) }

        let hex = String(repeating: "cd", count: 32)
        XCTAssertEqual(SpacemapCommand.currentNonceHex(for: socketPath), hex)

        client.yabaiProcessCheck = { true }
        client.yabaiExecutableOverride = true
        let actionLock = NSLock()
        var actions: [String] = []
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--add"),
               let action = arguments.first(where: { $0.hasPrefix("action=") }) {
                actionLock.lock()
                actions.append(action)
                actionLock.unlock()
            }
            return ""
        }

        client.registerSignals(
            socketPath: socketPath,
            showHUDOnSpaceChange: false,
            refreshWorkspacePreviews: true,
            refreshWindowGeometry: true
        )

        actionLock.lock()
        let registered = actions
        actionLock.unlock()
        XCTAssertFalse(registered.isEmpty)
        for action in registered {
            XCTAssertTrue(action.contains(":\(hex)'"),
                          "registered action must carry the nonce: \(action)")
            XCTAssertFalse(action.contains("/usr/bin/false"))
        }
    }

    func testDotPreviewsOnlyRefreshForWorkspaceTopology() {
        XCTAssertEqual(
            client.previewRefreshEvents(refreshWindowGeometry: false),
            client.workspaceTopologyRefreshEvents
        )
    }

    func testRunProcessDrainsLargeOutputBeforeWaitingForExit() throws {
        let output = try YabaiClientImpl.runProcess(
            executable: "/bin/sh",
            arguments: ["-c", "/usr/bin/yes x | /usr/bin/head -c 1048576"],
            timeout: 5
        )

        XCTAssertEqual(output.utf8.count, 1_048_576)
    }

    func testRunProcessTerminatesCommandsThatExceedTimeout() {
        let started = Date()

        XCTAssertThrowsError(try YabaiClientImpl.runProcess(
            executable: "/bin/sleep",
            arguments: ["5"],
            timeout: 0.05
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("timed out"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testRunProcessCapturesOutputProducedAfterDelay() throws {
        let output = try YabaiClientImpl.runProcess(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 0.3; printf 'late output'"],
            timeout: 5
        )

        XCTAssertEqual(output, "late output")
    }

    func testRunProcessCapturesStderrInFailureMessage() {
        XCTAssertThrowsError(try YabaiClientImpl.runProcess(
            executable: "/bin/sh",
            arguments: ["-c", "printf 'boom' >&2; exit 1"],
            timeout: 5
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("boom"))
        }
    }

    func testRunProcessAbandonsGrandchildHoldingPipeWithoutHangingOrCrashing() {
        let started = Date()

        XCTAssertThrowsError(try YabaiClientImpl.runProcess(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 5 & printf 'started'"],
            timeout: 5
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("output drain timed out"),
                          "unexpected error: \(error.localizedDescription)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3,
                          "a grandchild holding the pipe must not block the caller")
    }


    func testRemoveSignalsRemovesSignals() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }
        client.removeSignals()
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

    func testDecodeTolerantDropsOnlyMalformedEntries() throws {
        let json = """
        [
          {"id":1,"index":1,"display":1,"has-focus":true},
          {"id":"not-an-int","index":2,"display":1,"has-focus":false},
          {"id":3,"index":3,"display":1,"has-focus":false}
        ]
        """

        let spaces = try client.decodeTolerant(YabaiSpace.self, from: json, label: "test")

        XCTAssertEqual(spaces.map(\.index), [1, 3])
        XCTAssertEqual(spaces.map(\.id), [1, 3])
    }

    func testDecodeTolerantThrowsWhenPayloadIsNotAnArray() {
        XCTAssertThrowsError(
            try client.decodeTolerant(YabaiSpace.self, from: "{\"id\":1}", label: "test")
        )
    }


    // MARK: - Last-good snapshots

    func testQuerySpacesKeepsLastGoodSnapshotWhenTransientQueryFails() throws {
        var now: TimeInterval = 1_000
        client.uptimeOverride = { now }
        client.yabaiExecutableOverride = true
        client.yabaiProcessCheck = { true }
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") { return self.spacesJSON([1, 2], focused: 1) }
            return ""
        }

        XCTAssertEqual(try client.querySpaces().map(\.index), [1, 2])

        now += 1
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "timeout"])
            }
            return ""
        }

        XCTAssertEqual(try client.querySpaces().map(\.index), [1, 2],
                       "a failed refresh must not discard the last good spaces snapshot")
    }

    func testBuildGridStateDoesNotBlankOnTransientQueryFailure() {
        var now: TimeInterval = 2_000
        client.uptimeOverride = { now }
        client.yabaiExecutableOverride = true
        client.yabaiProcessCheck = { true }
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") { return self.spacesJSON([1, 2], focused: 1) }
            if arguments.contains("--windows") { return self.windowsJSON([10, 20]) }
            if arguments.contains("--displays") { return self.displaysJSON }
            return ""
        }

        let first = client.buildGridState(config: .default)
        XCTAssertEqual(first.spaces.count, 2)
        XCTAssertEqual(first.windows.count, 2)

        now += 1
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") || arguments.contains("--windows") {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "timeout"])
            }
            if arguments.contains("--displays") { return self.displaysJSON }
            return ""
        }

        let second = client.buildGridState(config: .default)
        XCTAssertEqual(second.spaces.map(\.index), [1, 2],
                       "transient spaces failure must keep the last good grid")
        XCTAssertEqual(second.windows.map(\.id), [10, 20],
                       "transient windows failure must keep the last good grid")
        XCTAssertEqual(second.focusedIndex, 1)
    }

    func testMissingBinaryServesLastGoodThenExpiresAfterStaleTTL() throws {
        var now: TimeInterval = 4_000
        client.uptimeOverride = { now }
        client.yabaiExecutableOverride = true
        client.yabaiProcessCheck = { true }
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") { return self.spacesJSON([1]) }
            return ""
        }

        XCTAssertEqual(try client.querySpaces().map(\.index), [1])

        now += 1
        client.yabaiExecutableOverride = false
        XCTAssertEqual(try client.querySpaces().map(\.index), [1],
                       "missing yabai must serve last-good, not a cached empty result")

        now += 6
        XCTAssertThrowsError(try client.querySpaces(),
                             "last-good snapshots must expire after the stale TTL")
    }

    func testEmptySpacesResultDoesNotEvictGoodSnapshot() throws {
        var now: TimeInterval = 5_000
        client.uptimeOverride = { now }
        client.yabaiExecutableOverride = true
        client.yabaiProcessCheck = { true }
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") { return self.spacesJSON([1]) }
            return ""
        }

        XCTAssertEqual(try client.querySpaces().map(\.index), [1])

        now += 1
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") { return "[]" }
            return ""
        }

        XCTAssertEqual(try client.querySpaces().map(\.index), [1],
                       "a transient empty spaces result must not replace a good snapshot")
    }


    // MARK: - Snapshot coalescing

    func testNearSimultaneousQueriesShareOneSnapshot() throws {
        var calls = 0
        client.yabaiExecutableOverride = true
        client.yabaiProcessCheck = { true }
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") {
                calls += 1
                return self.spacesJSON([1])
            }
            if arguments.contains("--windows") {
                calls += 1
                return self.windowsJSON([10])
            }
            return ""
        }

        _ = try client.querySpaces()
        _ = try client.querySpaces()
        XCTAssertEqual(calls, 1, "a near-simultaneous spaces query should reuse the snapshot")

        _ = try client.queryWindows()
        _ = try client.queryWindows()
        XCTAssertEqual(calls, 2, "a near-simultaneous windows query should reuse the snapshot")
    }

    func testConcurrentSpaceAndWindowQueriesCoalesce() {
        client.uptimeOverride = { 6_000 }
        client.yabaiExecutableOverride = true
        client.yabaiProcessCheck = { true }
        let counterLock = NSLock()
        var spacesCalls = 0
        var windowsCalls = 0
        let spacesEntered = DispatchSemaphore(value: 0)
        let releaseSpaces = DispatchSemaphore(value: 0)

        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") {
                counterLock.lock()
                spacesCalls += 1
                counterLock.unlock()
                spacesEntered.signal()
                releaseSpaces.wait()
                return self.spacesJSON([1])
            }
            if arguments.contains("--windows") {
                counterLock.lock()
                windowsCalls += 1
                counterLock.unlock()
                return self.windowsJSON([10])
            }
            return ""
        }

        let group = DispatchGroup()
        func querySpaces() {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                _ = try? self.client.querySpaces()
                group.leave()
            }
        }
        func queryWindows() {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                _ = try? self.client.queryWindows()
                group.leave()
            }
        }

        querySpaces()
        XCTAssertEqual(spacesEntered.wait(timeout: .now() + 2), .success)
        for _ in 0..<3 {
            querySpaces()
            queryWindows()
        }
        // Let the extra callers reach the in-flight branch before releasing.
        Thread.sleep(forTimeInterval: 0.1)
        releaseSpaces.signal()

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        counterLock.lock()
        let spaceFetchCount = spacesCalls
        let windowFetchCount = windowsCalls
        counterLock.unlock()
        XCTAssertEqual(spaceFetchCount, 1, "all concurrent spaces callers must share one fetch")
        XCTAssertEqual(windowFetchCount, 1, "all concurrent windows callers must share one fetch")
    }

    func testInvalidateSnapshotCachesForcesFreshQuery() throws {
        var index = 1
        client.uptimeOverride = { 8_000 }
        client.yabaiExecutableOverride = true
        client.yabaiProcessCheck = { true }
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") { return self.spacesJSON([index]) }
            return ""
        }

        XCTAssertEqual(try client.querySpaces().map(\.index), [1])

        index = 2
        client.invalidateSnapshotCaches()

        XCTAssertEqual(try client.querySpaces().map(\.index), [2],
                       "external mutations must invalidate coalesced snapshots")
    }

    func testGenerationMismatchRetriesOnceWithFreshSnapshot() throws {
        var calls = 0
        client.uptimeOverride = { 9_000 }
        client.yabaiExecutableOverride = true
        client.yabaiProcessCheck = { true }
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") {
                calls += 1
                if calls == 1 {
                    self.client.invalidateSnapshotCaches()
                    return self.spacesJSON([1])
                }
                return self.spacesJSON([2])
            }
            return ""
        }

        XCTAssertEqual(try client.querySpaces().map(\.index), [2],
                       "a result invalidated mid-flight should be retried, not returned")
        XCTAssertEqual(calls, 2)
    }


    // MARK: - Display cache

    func testCachedDisplaysCoalescesConcurrentFetches() {
        let client = self.client!
        client.yabaiExecutableOverride = true
        let counterLock = NSLock()
        var calls = 0
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--displays") {
                counterLock.lock()
                calls += 1
                counterLock.unlock()
                entered.signal()
                release.wait()
                return self.displaysJSON
            }
            return ""
        }

        let first = expectation(description: "first display fetch")
        DispatchQueue.global(qos: .userInitiated).async {
            _ = client.cachedDisplays()
            first.fulfill()
        }

        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        // While the first spawn is blocked, a concurrent miss serves stale
        // instead of spawning a second query.
        XCTAssertTrue(client.cachedDisplays().isEmpty)
        counterLock.lock()
        let callsDuringFlight = calls
        counterLock.unlock()
        XCTAssertEqual(callsDuringFlight, 1)

        release.signal()
        waitForExpectations(timeout: 2)
        XCTAssertEqual(client.cachedDisplays().count, 1)
    }

    func testCachedDisplaysKeepsLastGoodOnFailure() {
        var now: TimeInterval = 3_000
        client.uptimeOverride = { now }
        client.yabaiExecutableOverride = true
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--displays") { return self.displaysJSON }
            return ""
        }

        XCTAssertEqual(client.cachedDisplays().count, 1)

        now += 6
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--displays") {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "timeout"])
            }
            return ""
        }

        XCTAssertEqual(client.cachedDisplays().count, 1,
                       "a failed display query must not evict the last good snapshot")
    }


    // MARK: - Space creation loop

    func testMoveWindowCreatingSpacesBailsWhenBudgetExpires() {
        client = YabaiClientImpl(spaceCreationBudget: 0)
        client.yabaiExecutableOverride = true
        let commandLock = NSLock()
        var commands: [String] = []
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") { return "[]" }
            commandLock.lock()
            commands.append(arguments.joined(separator: " "))
            commandLock.unlock()
            return ""
        }

        let done = expectation(description: "create loop times out")
        client.moveWindowCreatingSpacesIfNeeded(42, toSpace: 2, focusDestination: false) { result in
            switch result {
            case .failure(let error):
                XCTAssertTrue(error.localizedDescription.contains("within 0"),
                              "unexpected error: \(error.localizedDescription)")
            case .success:
                XCTFail("create loop should fail when the budget is exhausted")
            }
            done.fulfill()
        }

        waitForExpectations(timeout: 2)
        commandLock.lock()
        let issued = commands
        commandLock.unlock()
        XCTAssertTrue(issued.isEmpty, "no create/move command should run after the deadline: \(issued)")
    }

    func testMoveWindowCreatingSpacesCreatesThenMovesUsingFakeRunner() {
        client = YabaiClientImpl(spaceCreationBudget: 5)
        client.yabaiExecutableOverride = true
        let commandLock = NSLock()
        var commands: [String] = []
        var spaceQueries = 0
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") {
                spaceQueries += 1
                return spaceQueries == 1
                    ? self.spacesJSON([1], focused: 1)
                    : self.spacesJSON([1, 2], focused: 1)
            }
            commandLock.lock()
            commands.append(arguments.joined(separator: " "))
            commandLock.unlock()
            return ""
        }

        let done = expectation(description: "create loop succeeds")
        client.moveWindowCreatingSpacesIfNeeded(42, toSpace: 2, focusDestination: true) { result in
            if case .failure(let error) = result {
                XCTFail("unexpected failure: \(error.localizedDescription)")
            }
            done.fulfill()
        }

        waitForExpectations(timeout: 2)
        commandLock.lock()
        let issued = commands
        commandLock.unlock()
        XCTAssertTrue(issued.contains { $0.contains("space --create") }, "issued: \(issued)")
        XCTAssertTrue(issued.contains { $0.contains("window 42 --space 2") }, "issued: \(issued)")
        XCTAssertTrue(issued.contains { $0.contains("space --focus 2") }, "issued: \(issued)")
    }

    func testMoveWindowCreatingSpacesExpiresBudgetMidLoop() {
        client = YabaiClientImpl(spaceCreationBudget: 5)
        var now: TimeInterval = 7_000
        client.uptimeOverride = { now }
        client.yabaiExecutableOverride = true
        let commandLock = NSLock()
        var commands: [String] = []
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") { return self.spacesJSON([1]) }
            commandLock.lock()
            commands.append(arguments.joined(separator: " "))
            commandLock.unlock()
            if arguments.contains("--create") {
                now += 10
            }
            return ""
        }

        let done = expectation(description: "create loop times out mid-loop")
        client.moveWindowCreatingSpacesIfNeeded(42, toSpace: 2, focusDestination: false) { result in
            switch result {
            case .failure(let error):
                XCTAssertTrue(error.localizedDescription.contains("within 5"),
                              "unexpected error: \(error.localizedDescription)")
            case .success:
                XCTFail("create loop should fail after the budget elapses")
            }
            done.fulfill()
        }

        waitForExpectations(timeout: 2)
        commandLock.lock()
        let issued = commands
        commandLock.unlock()
        XCTAssertTrue(issued.contains { $0.contains("space --create") },
                      "at least one create should have run before the deadline: \(issued)")
        XCTAssertFalse(issued.contains { $0.contains("window 42 --space 2") },
                       "move must not run after the budget expires: \(issued)")
    }


    // MARK: - Fixtures

    private func spacesJSON(_ indices: [Int], focused: Int? = nil) -> String {
        let entries = indices.map { index -> String in
            let hasFocus = index == focused ? "true" : "false"
            return "{\"id\":\(index),\"index\":\(index),\"display\":1,\"has-focus\":\(hasFocus)}"
        }
        return "[\(entries.joined(separator: ","))]"
    }

    private func windowsJSON(_ ids: [Int]) -> String {
        let entries = ids.map { id -> String in
            "{\"id\":\(id),\"app\":\"App\(id)\",\"space\":1,"
                + "\"frame\":{\"x\":0,\"y\":0,\"w\":100,\"h\":100},"
                + "\"is-hidden\":false,\"is-minimized\":false,\"sub-layer\":\"normal\"}"
        }
        return "[\(entries.joined(separator: ","))]"
    }

    private var displaysJSON: String {
        "[{\"index\":1,\"frame\":{\"x\":0,\"y\":0,\"w\":100,\"h\":100},\"has-focus\":true}]"
    }
}
