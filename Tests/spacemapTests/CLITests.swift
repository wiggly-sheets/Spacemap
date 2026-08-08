import XCTest
@testable import spacemap

final class CLITests: XCTestCase {
    func testParsesEverySupportedSpaceIndex() {
        for index in 1...16 {
            XCTAssertEqual(
                CLI.parse(arguments: ["spacemap", "--space", "\(index)"]),
                .command(.focusSpace(SpaceFocusTarget(argument: "\(index)")!))
            )
        }
    }

    func testParsesNamedAndLabelSpaceSelectors() {
        XCTAssertEqual(
            CLI.parse(arguments: ["spacemap", "--space", "recent"]),
            .command(.focusSpace(SpaceFocusTarget(argument: "recent")!))
        )
        XCTAssertEqual(
            CLI.parse(arguments: ["spacemap", "--space", "web"]),
            .command(.focusSpace(SpaceFocusTarget(argument: "web")!))
        )
    }

    func testRejectsMissingAndOutOfRangeSpaceSelectors() {
        guard case .error = CLI.parse(arguments: ["spacemap", "--space"]) else {
            return XCTFail("Expected missing selector error")
        }
        guard case .error = CLI.parse(arguments: ["spacemap", "--space", "17"]) else {
            return XCTFail("Expected out-of-range selector error")
        }
    }

    func testParsesOtherExitOnlyCommands() {
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--help"]), .command(.help))
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--version"]), .command(.version))
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--config"]), .command(.config))
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--trigger"]), .command(.trigger))
        XCTAssertEqual(CLI.parse(arguments: ["spacemap"]), .none)
    }
}
