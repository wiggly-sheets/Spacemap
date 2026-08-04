import XCTest
@testable import spacemap

final class SocketListenerTests: XCTestCase {
    func testShowCommandFromYabaiSignal() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.show.rawValue), .show)
    }

    func testASCIIShowCommandFromYabaiSignal() {
        XCTAssertEqual(SocketListener.command(for: Character("2").asciiValue!), .show)
    }

    func testBinaryShowCommandFromCLI() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.show.rawValue), .show)
    }

    func testUnknownCommandRefreshes() {
        XCTAssertEqual(SocketListener.command(for: Character("1").asciiValue!), .refresh)
    }

    func testBinaryToggleCommandFromCLI() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.toggle.rawValue), .toggle)
    }

    func testHealthProbeDoesNotTriggerRefresh() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.health.rawValue), .health)
        XCTAssertEqual(SocketListener.command(for: Character("5").asciiValue!), .health)
    }
}
