import XCTest
@testable import spacemap

final class SpacemapCommandTests: XCTestCase {
    func testCommandRawValuesMatchSocketProtocol() {
        XCTAssertEqual(SpacemapCommand.refresh.rawValue, 1)
        XCTAssertEqual(SpacemapCommand.show.rawValue, 2)
        XCTAssertEqual(SpacemapCommand.settings.rawValue, 3)
        XCTAssertEqual(SpacemapCommand.toggle.rawValue, 4)
        XCTAssertEqual(SpacemapCommand.health.rawValue, 5)
    }

    func testSocketPathFormat() {
        let path = SpacemapCommand.socketPath
        XCTAssertTrue(path.hasPrefix("/tmp/spacemap_"))
        XCTAssertTrue(path.hasSuffix(".socket"))
    }

    func testAllCommandsAreDistinct() {
        let commands: [SpacemapCommand] = [.refresh, .show, .settings, .toggle, .health]
        let rawValues = commands.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count, "All command raw values should be unique")
    }
}