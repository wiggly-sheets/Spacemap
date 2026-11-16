import XCTest
@testable import spacemap

private final class LRUWorkspaceStub: WorkspaceProtocol {
    let notificationCenter = NotificationCenter()
    var frontmostApplication: NSRunningApplication? { nil }
    var runningApplications: [NSRunningApplication] { [] }
    func open(_ url: URL) -> Bool { false }
    func icon(forFile path: String) -> NSImage { NSImage(size: NSSize(width: 64, height: 64)) }
}

/// Thread-safe counters for the background Spotlight lookups.
private final class LookupProbe {
    private let lock = NSLock()
    private var storedCalls = 0
    private var storedActive = 0
    private var storedMaxActive = 0

    var calls: Int { lock.lock(); defer { lock.unlock() }; return storedCalls }
    var maxActive: Int { lock.lock(); defer { lock.unlock() }; return storedMaxActive }

    func begin() {
        lock.lock()
        storedCalls += 1
        storedActive += 1
        storedMaxActive = max(storedMaxActive, storedActive)
        lock.unlock()
    }

    func end() {
        lock.lock()
        storedActive -= 1
        lock.unlock()
    }
}

/// Thread-safe monotonic clock for the negative-cache TTL test.
private final class ClockBox {
    private let lock = NSLock()
    private var value: TimeInterval

    init(_ value: TimeInterval) {
        self.value = value
    }

    var now: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(_ delta: TimeInterval) {
        lock.lock()
        value += delta
        lock.unlock()
    }
}

final class IconCacheTests: XCTestCase {


    func testOverfillEvictsOldestAndHitRefreshesMRU() {
        let cache = IconCache(workspace: LRUWorkspaceStub())
        for i in 0 ... IconCache.maxEntries {
            cache.store(NSImage(size: NSSize(width: 64, height: 64)), for: "App\(i)")
        }
        XCTAssertNil(cache.cachedIcon(for: "App0"))
        XCTAssertNotNil(cache.cachedIcon(for: "App\(IconCache.maxEntries)"))
        // Hit refreshes MRU: App1 survives the next insert, App2 falls out.
        _ = cache.cachedIcon(for: "App1")
        cache.store(NSImage(size: NSSize(width: 64, height: 64)), for: "AppOverflow")
        XCTAssertNotNil(cache.cachedIcon(for: "App1"))
        XCTAssertNil(cache.cachedIcon(for: "App2"))
    }

    func testConcurrentResolvesForOneNameShareASingleLookup() {
        let cache = IconCache(workspace: LRUWorkspaceStub())
        let probe = LookupProbe()
        cache.spotlightLookup = { _ in
            probe.begin()
            Thread.sleep(forTimeInterval: 0.1)
            probe.end()
            return nil
        }
        let both = expectation(description: "both callers complete")
        both.expectedFulfillmentCount = 2

        cache.resolveInBackground(appName: "CoalescedApp") { _ in both.fulfill() }
        cache.resolveInBackground(appName: "CoalescedApp") { _ in both.fulfill() }

        wait(for: [both], timeout: 2)
        XCTAssertEqual(probe.calls, 1, "one mdfind must serve every concurrent caller")
    }

    func testNegativeLookupIsCachedUntilTTLExpires() {
        let cache = IconCache(workspace: LRUWorkspaceStub())
        let probe = LookupProbe()
        let clock = ClockBox(100)
        cache.uptime = { clock.now }
        cache.negativeTTL = 60
        cache.spotlightLookup = { _ in
            probe.begin()
            probe.end()
            return nil
        }

        let first = expectation(description: "first miss")
        cache.resolveInBackground(appName: "MissingApp") { image in
            XCTAssertNil(image)
            first.fulfill()
        }
        wait(for: [first], timeout: 2)
        XCTAssertEqual(probe.calls, 1)

        let second = expectation(description: "negative cache hit")
        cache.resolveInBackground(appName: "MissingApp") { image in
            XCTAssertNil(image)
            second.fulfill()
        }
        wait(for: [second], timeout: 2)
        XCTAssertEqual(probe.calls, 1, "a recent miss must not run mdfind again")

        clock.advance(61)
        let third = expectation(description: "TTL expiry retries")
        cache.resolveInBackground(appName: "MissingApp") { _ in third.fulfill() }
        wait(for: [third], timeout: 2)
        XCTAssertEqual(probe.calls, 2, "an expired negative entry must be retried")
    }

    func testClearDuringLookupDropsStaleStoreAndCompletesPendingWithNil() {
        let cache = IconCache(workspace: LRUWorkspaceStub())
        let lookupStarted = expectation(description: "spotlight lookup started")
        let release = DispatchSemaphore(value: 0)
        cache.spotlightLookup = { _ in
            lookupStarted.fulfill()
            _ = release.wait(timeout: .now() + 2)
            return "/Applications/Stale.app"
        }
        let completed = expectation(description: "pending completion runs once")
        completed.assertForOverFulfill = true
        var results: [NSImage?] = []
        cache.resolveInBackground(appName: "StaleApp") { image in
            results.append(image)
            completed.fulfill()
        }
        wait(for: [lookupStarted], timeout: 1)

        cache.clear()
        release.signal()
        wait(for: [completed], timeout: 2)
        // Let the stale background block finish before checking that it stored nothing.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0], "clear() must complete the pending waiter with nil")
        XCTAssertNil(cache.cachedIcon(for: "StaleApp"),
                     "a lookup from the cleared generation must not store")
    }

    func testSpotlightLookupsAreBoundedButConcurrent() {
        let cache = IconCache(workspace: LRUWorkspaceStub())
        let probe = LookupProbe()
        cache.spotlightLookup = { _ in
            probe.begin()
            Thread.sleep(forTimeInterval: 0.15)
            probe.end()
            return nil
        }
        let all = expectation(description: "all lookups complete")
        all.expectedFulfillmentCount = 6

        for index in 0..<6 {
            cache.resolveInBackground(appName: "BoundedApp\(index)") { _ in all.fulfill() }
        }

        wait(for: [all], timeout: 5)
        XCTAssertEqual(probe.calls, 6)
        XCTAssertLessThanOrEqual(probe.maxActive, IconCache.maxConcurrentSpotlightLookups,
            "bounded concurrency keeps one wedged lookup from blocking everyone")
        XCTAssertGreaterThan(probe.maxActive, 1,
            "lookups must run concurrently, not on one serial queue")
    }
}
