import XCTest
@testable import spacemap

final class SocketListenerCommandTests: XCTestCase {


    func testCommandForShowSocketByte() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.show.socketByte!), .show)
    }

    func testCommandForShowASCIIValue() {
        XCTAssertEqual(SocketListener.command(for: Character("2").asciiValue!), .show)
    }

    func testCommandForToggleSocketByte() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.toggle.socketByte!), .toggle)
    }

    func testCommandForToggleASCIIValue() {
        XCTAssertEqual(SocketListener.command(for: Character("4").asciiValue!), .toggle)
    }

    func testCommandForSettingsSocketByte() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.settings.socketByte!), .settings)
    }

    func testCommandForSettingsASCIIValue() {
        XCTAssertEqual(SocketListener.command(for: Character("3").asciiValue!), .settings)
    }

    func testCommandForHealthSocketByte() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.health.socketByte!), .health)
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

    func testCommandForUpdateSocketByte() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.update.socketByte!), .update)
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.updateFont.socketByte!), .updateFont)
    }

    func testCommandForReloadConfigSocketByte() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.reloadConfig.socketByte!), .reloadConfig)
        XCTAssertEqual(SocketListener.command(for: Character("6").asciiValue!), .reloadConfig)
    }

    func testCommandForRefreshSocketByte() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.refresh.socketByte!), .refresh)
    }


    func testSendCommandReturnsFalseForInvalidPath() {
        let result = SocketListener.sendCommand(to: "/nonexistent/socket/path", command: SpacemapCommand.show.socketByte!)
        XCTAssertFalse(result)
    }

    func testSendCommandReturnsFalseForZeroCommand() {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("nonexistent_socket")
        let result = SocketListener.sendCommand(to: path, command: 0)
        XCTAssertFalse(result)
    }
}
