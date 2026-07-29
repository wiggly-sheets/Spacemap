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
}
