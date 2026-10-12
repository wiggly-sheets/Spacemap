import AppKit
import Foundation
import XCTest
@testable import spacemap

// Stream D regression tests for DesignDocs/HANDOFF-audit-2026-10-12.md.
// Tests-only: no source edits.

// MARK: - createAndFocusNewestSpace timeout path (Stream B owns source)

final class CreateAndFocusTimeoutTests: XCTestCase {
    private func makeController(yabai: MockYabaiService) -> HUDWindowController {
        HUDWindowController(services: SpacemapServices(
            yabaiService: yabai,
            alertsService: Alerts()
        ))
    }

    func testTimeoutPathCreatesButNeverFocuses() {
        let yabai = MockYabaiService()
        yabai.querySpacesResult = [] // newest never appears: poll exhausts attempts
        var controller: HUDWindowController? = makeController(yabai: yabai)
        controller?.createAndFocusNewestSpace()

        let settled = expectation(description: "poll attempts exhaust")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { settled.fulfill() }
        wait(for: [settled], timeout: 5)
        defer { controller = nil }

        XCTAssertEqual(yabai.createSpaceCallCount, 1)
        XCTAssertEqual(yabai.focusSpaceIndexCallCount, 0)
        XCTAssertEqual(yabai.focusSpaceTargetCallCount, 0)
        XCTAssertGreaterThanOrEqual(yabai.querySpacesCallCount, 3)
    }

    func testStaleGenerationAbortsPoll() {
        let yabai = MockYabaiService()
        yabai.querySpacesResult = []
        var controller: HUDWindowController? = makeController(yabai: yabai)
        controller?.show()
        controller?.createAndFocusNewestSpace()
        controller?.hide() // bumps generation: pending polls must abort

        let settled = expectation(description: "aborted poll settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settled.fulfill() }
        wait(for: [settled], timeout: 5)
        defer { controller = nil }

        XCTAssertEqual(yabai.focusSpaceIndexCallCount, 0)
        XCTAssertEqual(yabai.focusSpaceTargetCallCount, 0)
    }
}

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

// MARK: - SocketListener.parseFrame nonce + newline (Stream A owns source)

final class ParseFrameNonceTests: XCTestCase {
    func testNonceMismatchDropsFrame() {
        let frame = Data([SpacemapCommand.toggle.rawValue]) + Data(":deadbeef".utf8)
        XCTAssertNil(SocketListener.parseFrame(frame, nonce: String(repeating: "0", count: 64)))
    }

    func testMatchingNonceAccepted() {
        let nonce = String(repeating: "a", count: 64)
        let frame = Data([SpacemapCommand.toggle.rawValue]) + Data((":" + nonce).utf8)
        XCTAssertEqual(SocketListener.parseFrame(frame, nonce: nonce), .toggle)
    }

    func testTrailingNewlineAccepted() {
        XCTAssertEqual(
            SocketListener.parseFrame(Data([SpacemapCommand.show.rawValue, 0x0A]), nonce: nil),
            .show
        )
    }

    func testMissingColonSeparatorDropsFrame() {
        let frame = Data([SpacemapCommand.show.rawValue]) + Data("xy".utf8)
        XCTAssertNil(SocketListener.parseFrame(frame, nonce: nil))
    }

    func testEmptyFrameReturnsNil() {
        XCTAssertNil(SocketListener.parseFrame(Data(), nonce: nil))
    }
}

// MARK: - ConfigLoader backup rotation / symlink refusal (Stream A owns source)

final class ConfigLoaderBackupAndSymlinkTests: XCTestCase {
    private func tempDir(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-audit-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testBackupRotatesToBak1() throws {
        let dir = try tempDir("rotation")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("config.toml").path

        var first = ConfigValues(); first.cols = 11
        ConfigLoader.save(first, to: path)
        var second = ConfigValues(); second.cols = 22
        ConfigLoader.save(second, to: path)
        var third = ConfigValues(); third.cols = 33
        ConfigLoader.save(third, to: path)

        XCTAssertTrue(try String(contentsOfFile: path + ".bak", encoding: .utf8).contains("cols = 22"))
        XCTAssertTrue(try String(contentsOfFile: path + ".bak.1", encoding: .utf8).contains("cols = 11"))
    }

    func testLoadRefusesSymlinkAndLeavesTargetUntouched() throws {
        let dir = try tempDir("symlink-load")
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("real.toml")
        try "cols = 5".write(to: target, atomically: true, encoding: .utf8)
        let link = dir.appendingPathComponent("config.toml").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target.path)

        let (values, needsRepair) = ConfigLoader.load(from: link, silentMode: true)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(values.cols, ConfigValues().cols)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "cols = 5")
    }

    func testSaveRefusesSymlinkAndLeavesTargetUntouched() throws {
        let dir = try tempDir("symlink-save")
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("real.toml")
        try "cols = 5".write(to: target, atomically: true, encoding: .utf8)
        let link = dir.appendingPathComponent("config.toml").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target.path)

        var values = ConfigValues(); values.cols = 99
        ConfigLoader.save(values, to: link)

        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "cols = 5")
        XCTAssertFalse(FileManager.default.fileExists(atPath: link + ".bak"))
    }
}

// MARK: - IconCache eviction after terminate (Stream C owns source)

private final class EvictionWorkspaceStub: WorkspaceProtocol {
    var apps: [NSRunningApplication] = []
    let notificationCenter = NotificationCenter()
    var frontmostApplication: NSRunningApplication? { nil }
    var runningApplications: [NSRunningApplication] { apps }
    func open(_ url: URL) -> Bool { false }
    func icon(forFile path: String) -> NSImage { NSImage(size: NSSize(width: 64, height: 64)) }
}

final class IconCacheEvictionTests: XCTestCase {
    func testUnknownAppReturnsNil() throws {
        let cache = IconCache(workspace: EvictionWorkspaceStub()) // no running apps
        XCTAssertNil(cache.icon(for: "GhostAppEvictionProbe"))
    }

    func testTerminateNotificationEvictsUnlistedApp() throws {
        let stub = EvictionWorkspaceStub()
        let cache = IconCache(workspace: stub)
        stub.notificationCenter.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        XCTAssertNil(cache.icon(for: "GhostAppEvictionProbe"))
    }

    func testRunningAppSurvivesRebuild() throws {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName != nil && $0.bundleURL != nil
        }), let name = app.localizedName else {
            throw XCTSkip("no named running app available")
        }

        let stub = EvictionWorkspaceStub()
        stub.apps = [app]
        let cache = IconCache(workspace: stub)
        stub.notificationCenter.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        XCTAssertNotNil(cache.icon(for: name))
    }
}
