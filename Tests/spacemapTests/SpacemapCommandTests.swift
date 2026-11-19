import Foundation
import XCTest
@testable import spacemap

final class SpacemapCommandTests: XCTestCase {
    func testSocketBytesMatchSocketProtocol() {
        XCTAssertEqual(SpacemapCommand.refresh.socketByte, 1)
        XCTAssertEqual(SpacemapCommand.show.socketByte, 2)
        XCTAssertEqual(SpacemapCommand.settings.socketByte, 3)
        XCTAssertEqual(SpacemapCommand.toggle.socketByte, 4)
        XCTAssertEqual(SpacemapCommand.health.socketByte, 5)
        XCTAssertEqual(SpacemapCommand.reloadConfig.socketByte, 6)
        XCTAssertEqual(SpacemapCommand.update.socketByte, 7)
        XCTAssertEqual(SpacemapCommand.updateFont.socketByte, 8)
    }

    func testCLIOnlyCommandsHaveNoSocketByte() {
        for command: SpacemapCommand in [.version, .help, .config, .printConfig, .status, .showMenu, .restarting] {
            XCTAssertNil(command.socketByte, "\(command) must not travel over the socket")
        }
    }

    func testSocketPathFormat() {
        let path = SpacemapCommand.socketPath
        // Per-user temp dir ($TMPDIR), never shared /tmp.
        XCTAssertTrue(path.hasPrefix(NSTemporaryDirectory()))
        XCTAssertFalse(path.hasPrefix("/tmp/"))
        XCTAssertTrue(path.contains("spacemap_"))
        XCTAssertTrue(path.hasSuffix(".socket"))
    }

    func testAllCommandsAreDistinct() {
        let commands: [SpacemapCommand] = [.refresh, .show, .settings, .toggle, .health]
        let rawValues = commands.compactMap(\.socketByte)
        XCTAssertEqual(Set(rawValues).count, rawValues.count, "All command socket bytes should be unique")
    }
}