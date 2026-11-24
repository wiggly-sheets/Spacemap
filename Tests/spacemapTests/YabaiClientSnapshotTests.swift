import XCTest
@testable import spacemap

final class YabaiClientSnapshotTests: YabaiClientImplTestCase {
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

    /// A spawn-time error (EACCES, quarantine, binary gone) is not a
    /// `ProcessRunner.Failure`, so it must still surface as a yabai command
    /// failure instead of raw Cocoa/POSIX text.
    func testSpawnErrorSurfacesAsYabaiCommandFailure() {
        client.yabaiExecutableOverride = true
        client.yabaiProcessCheck = { true }
        client.commandRunnerOverride = { _, _, _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        }

        XCTAssertThrowsError(try client.querySpaces()) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("yabai -m query --spaces failed with status -1"),
                          "spawn errors must surface as a yabai command failure: \(message)")
            XCTAssertTrue(message.contains("Permission denied"), message)
        }
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

}
