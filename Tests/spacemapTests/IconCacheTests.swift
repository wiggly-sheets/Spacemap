import XCTest
@testable import spacemap

private final class LRUWorkspaceStub: WorkspaceProtocol {
    let notificationCenter = NotificationCenter()
    var frontmostApplication: NSRunningApplication? { nil }
    var runningApplications: [NSRunningApplication] { [] }
    func open(_ url: URL) -> Bool { false }
    func icon(forFile path: String) -> NSImage { NSImage(size: NSSize(width: 64, height: 64)) }
}

final class IconCacheTests: XCTestCase {


    func testSharedInstanceIsSingleton() {
        let instance1 = IconCache.shared
        let instance2 = IconCache.shared
        XCTAssertTrue(instance1 === instance2)
    }


    func testIconForUnknownAppReturnsNil() {
        let icon = IconCache.shared.icon(for: "NonExistentApp12345")
        XCTAssertNil(icon)
    }


    func testPreloadDoesNotCrash() {
        IconCache.shared.preload(appNames: [])
    }

    func testPreloadWithAppNamesDoesNotCrash() {
        IconCache.shared.preload(appNames: ["Finder", "Safari"])
    }


    func testClearDoesNotCrash() {
        IconCache.shared.clear()
    }


    func testRebuildLookupDoesNotCrash() {
        IconCache.shared.preload(appNames: ["Finder"])
        let icon = IconCache.shared.icon(for: "Finder")
        XCTAssertNotNil(icon)
    }

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
}
