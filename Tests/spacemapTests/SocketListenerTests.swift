import XCTest
@testable import spacemap

final class SocketListenerTests: XCTestCase {
    func testASCIIShowCommandFromYabaiSignal() {
        XCTAssertEqual(SocketListener.command(for: Character("2").asciiValue!), .show)
    }

    func testBinaryShowCommandFromCLI() {
        XCTAssertEqual(SocketListener.command(for: 2), .show)
    }

    func testUnknownCommandRefreshes() {
        XCTAssertEqual(SocketListener.command(for: Character("1").asciiValue!), .refresh)
    }

    func testBinaryToggleCommandFromCLI() {
        XCTAssertEqual(SocketListener.command(for: 4), .toggle)
    }

    func testHealthProbeDoesNotTriggerRefresh() {
        XCTAssertEqual(SocketListener.command(for: 5), .health)
        XCTAssertEqual(SocketListener.command(for: Character("5").asciiValue!), .health)
    }
}
