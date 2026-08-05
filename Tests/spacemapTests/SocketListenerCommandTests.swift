import XCTest
@testable import spacemap

final class SocketListenerCommandTests: XCTestCase {

    // MARK: - command(for:)

    func testCommandForShowRawValue() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.show.rawValue), .show)
    }

    func testCommandForShowASCIIValue() {
        XCTAssertEqual(SocketListener.command(for: Character("2").asciiValue!), .show)
    }

    func testCommandForToggleRawValue() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.toggle.rawValue), .toggle)
    }

    func testCommandForToggleASCIIValue() {
        XCTAssertEqual(SocketListener.command(for: Character("4").asciiValue!), .toggle)
    }

    func testCommandForSettingsRawValue() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.settings.rawValue), .settings)
    }

    func testCommandForSettingsASCIIValue() {
        XCTAssertEqual(SocketListener.command(for: Character("3").asciiValue!), .settings)
    }

    func testCommandForHealthRawValue() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.health.rawValue), .health)
    }

    func testCommandForHealthASCIIValue() {
        XCTAssertEqual(SocketListener.command(for: Character("5").asciiValue!), .health)
    }

    func testCommandForUnknownValueReturnsRefresh() {
        XCTAssertEqual(SocketListener.command(for: Character("1").asciiValue!), .refresh)
        XCTAssertEqual(SocketListener.command(for: Character("0").asciiValue!), .refresh)
        XCTAssertEqual(SocketListener.command(for: Character("9").asciiValue!), .refresh)
        XCTAssertEqual(SocketListener.command(for: 0xFF), .refresh)
    }

    // MARK: - sendCommand

    func testSendCommandReturnsFalseForInvalidPath() {
        let result = SocketListener.sendCommand(to: "/nonexistent/socket/path", command: SpacemapCommand.show.rawValue)
        XCTAssertFalse(result)
    }

    func testSendCommandReturnsFalseForZeroCommand() {
        let result = SocketListener.sendCommand(to: "/tmp/nonexistent_socket", command: 0)
        XCTAssertFalse(result)
    }
}