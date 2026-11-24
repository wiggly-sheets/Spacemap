import AppKit
import Foundation
import XCTest
@testable import spacemap

// MARK: - buildGridState uses cache, not raw pgrep (Stream B owns source)

final class BuildGridStateCacheTests: XCTestCase {
    func testBuildGridStateConsultsProcessCache() {
        let client = YabaiClientImpl()
        defer { client.resetYabaiProcessCheck() }
        var checks = 0
        client.yabaiProcessCheck = { checks += 1; return false }
        client.resetYabaiRunningCache()

        let state = client.buildGridState(config: .default)

        XCTAssertGreaterThanOrEqual(checks, 1)
        XCTAssertEqual(state.spaces.count, 0)
        XCTAssertNil(state.focusedIndex)
    }

    func testBuildGridStateCachesNegativeResult() {
        let client = YabaiClientImpl()
        defer { client.resetYabaiProcessCheck() }
        var checks = 0
        client.yabaiProcessCheck = { checks += 1; return false }
        client.resetYabaiRunningCache()

        _ = client.buildGridState(config: .default)
        _ = client.buildGridState(config: .default)

        XCTAssertEqual(checks, 1)
    }
}
