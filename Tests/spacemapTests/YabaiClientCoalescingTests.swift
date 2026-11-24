import XCTest
@testable import spacemap

final class YabaiClientCoalescingTests: YabaiClientImplTestCase {
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

}
