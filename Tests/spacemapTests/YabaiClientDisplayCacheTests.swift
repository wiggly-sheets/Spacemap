import XCTest
@testable import spacemap

final class YabaiClientDisplayCacheTests: YabaiClientImplTestCase {
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

}
