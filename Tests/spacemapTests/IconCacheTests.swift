import XCTest
@testable import spacemap

final class IconCacheTests: XCTestCase {

    // MARK: - shared instance

    func testSharedInstanceIsSingleton() {
        let instance1 = IconCache.shared
        let instance2 = IconCache.shared
        // Verify it's the same instance (identity check)
        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - icon(for:)

    func testIconForUnknownAppReturnsNil() {
        let icon = IconCache.shared.icon(for: "NonExistentApp12345")
        XCTAssertNil(icon)
    }

    // MARK: - preload

    func testPreloadDoesNotCrash() {
        // Preload with empty list should not crash
        IconCache.shared.preload(appNames: [])
    }

    func testPreloadWithAppNamesDoesNotCrash() {
        // Preload with known app names should not crash
        IconCache.shared.preload(appNames: ["Finder", "Safari"])
    }

    // MARK: - clear

    func testClearDoesNotCrash() {
        IconCache.shared.clear()
    }

    // MARK: - rebuildLookup

    func testRebuildLookupDoesNotCrash() {
        // rebuildLookup is private, but we can verify the cache works
        // by preloading and then checking icon lookup
        IconCache.shared.preload(appNames: ["Finder"])
        // The icon for Finder should now be cached
        let icon = IconCache.shared.icon(for: "Finder")
        // Finder should be available on macOS
        XCTAssertNotNil(icon)
    }
}