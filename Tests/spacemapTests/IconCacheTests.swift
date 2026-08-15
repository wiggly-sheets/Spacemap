import XCTest
@testable import spacemap

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
}
