import AppKit
import Foundation
import XCTest
@testable import spacemap

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
