import XCTest
@testable import spacemap

final class SpaceFocusTargetTests: XCTestCase {
    func testAcceptsEverySupportedIndex() {
        for index in 1...16 {
            XCTAssertEqual(SpaceFocusTarget(argument: "\(index)")?.value, "\(index)")
        }
    }

    func testRejectsIndicesOutsideSupportedRange() {
        XCTAssertNil(SpaceFocusTarget(argument: "0"))
        XCTAssertNil(SpaceFocusTarget(argument: "17"))
        XCTAssertNil(SpaceFocusTarget(argument: "-1"))
    }

    func testAcceptsNamedSelectorsCaseInsensitively() {
        for selector in ["prev", "next", "first", "last", "recent", "mouse"] {
            XCTAssertEqual(SpaceFocusTarget(argument: selector.uppercased())?.value, selector)
        }
    }

    func testAcceptsSpaceLabels() {
        XCTAssertEqual(SpaceFocusTarget(argument: "web")?.value, "web")
        XCTAssertEqual(SpaceFocusTarget(argument: "Project Alpha")?.value, "Project Alpha")
    }

    func testRejectsMissingAndOptionLikeValues() {
        XCTAssertNil(SpaceFocusTarget(argument: ""))
        XCTAssertNil(SpaceFocusTarget(argument: "   "))
        XCTAssertNil(SpaceFocusTarget(argument: "--help"))
    }
}
