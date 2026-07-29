import XCTest
@testable import spacemap

final class YabaiClientTests: XCTestCase {
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
