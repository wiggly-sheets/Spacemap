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
}
