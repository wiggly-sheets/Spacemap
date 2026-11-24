import AppKit
import Foundation
import XCTest
@testable import spacemap

// MARK: - SocketListener.parseFrame nonce + newline (Stream A owns source)

final class ParseFrameNonceTests: XCTestCase {
    func testNonceMismatchDropsFrame() {
        let frame = Data([SpacemapCommand.toggle.socketByte!]) + Data(":deadbeef".utf8)
        XCTAssertNil(SocketListener.parseFrame(frame, nonce: String(repeating: "0", count: 64)))
    }

    func testMatchingNonceAccepted() {
        let nonce = String(repeating: "a", count: 64)
        let frame = Data([SpacemapCommand.toggle.socketByte!]) + Data((":" + nonce).utf8)
        XCTAssertEqual(SocketListener.parseFrame(frame, nonce: nonce), .toggle)
    }

    func testTrailingNewlineAccepted() {
        XCTAssertEqual(
            SocketListener.parseFrame(Data([SpacemapCommand.show.socketByte!, 0x0A]), nonce: nil),
            .show
        )
    }

    func testMissingColonSeparatorDropsFrame() {
        let frame = Data([SpacemapCommand.show.socketByte!]) + Data("xy".utf8)
        XCTAssertNil(SocketListener.parseFrame(frame, nonce: nil))
    }

    func testEmptyFrameReturnsNil() {
        XCTAssertNil(SocketListener.parseFrame(Data(), nonce: nil))
    }
}
