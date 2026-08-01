import XCTest
@testable import spacemap

final class YabaiClientTests: XCTestCase {
    override func tearDown() {
        YabaiClient.resetYabaiProcessCheck()
        super.tearDown()
    }

    func testForcedProcessCheckBypassesCachedLaunchFailure() {
        var running = false
        YabaiClient.yabaiProcessCheck = { running }
        YabaiClient.resetYabaiRunningCache()

        XCTAssertFalse(YabaiClient.isYabaiRunning())
        running = true

        XCTAssertTrue(YabaiClient.isYabaiRunning(forceRefresh: true))
    }

    func testSignalRegistrationRechecksCachedLaunchFailure() {
        var processCheckCount = 0
        YabaiClient.yabaiProcessCheck = {
            processCheckCount += 1
            return false
        }
        YabaiClient.resetYabaiRunningCache()

        XCTAssertFalse(YabaiClient.isYabaiRunning())
        YabaiClient.registerSignals(socketPath: "/tmp/spacemap_test.socket")

        XCTAssertEqual(processCheckCount, 2)
    }

    func testSpaceChangedSignalUsesSystemNetcatToShowHUD() {
        let action = YabaiClient.spaceChangedSignalAction(
            socketPath: "/tmp/spacemap_test.socket",
            showHUDOnSpaceChange: true
        )

        XCTAssertEqual(action, "echo 2 | /usr/bin/nc -U /tmp/spacemap_test.socket")
    }

    func testSpaceChangedSignalRefreshesWhenAutomaticShowIsOff() {
        let action = YabaiClient.spaceChangedSignalAction(
            socketPath: "/tmp/spacemap_test.socket",
            showHUDOnSpaceChange: false
        )

        XCTAssertEqual(action, "echo 1 | /usr/bin/nc -U /tmp/spacemap_test.socket")
    }

    func testWindowSignalsRefreshTheExistingApp() {
        XCTAssertEqual(
            YabaiClient.refreshSignalAction(socketPath: "/tmp/spacemap_test.socket"),
            "echo 1 | /usr/bin/nc -U /tmp/spacemap_test.socket"
        )
        XCTAssertTrue(YabaiClient.workspacePreviewRefreshEvents.contains("window_created"))
        XCTAssertTrue(YabaiClient.workspacePreviewRefreshEvents.contains("window_destroyed"))
        XCTAssertTrue(YabaiClient.workspacePreviewRefreshEvents.contains("window_moved"))
        XCTAssertTrue(YabaiClient.workspacePreviewRefreshEvents.contains("window_resized"))
        XCTAssertTrue(YabaiClient.workspacePreviewRefreshEvents.contains("space_created"))
        XCTAssertTrue(YabaiClient.workspacePreviewRefreshEvents.contains("space_destroyed"))
    }
}
