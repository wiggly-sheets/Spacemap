import XCTest

final class GenerateAppcastFailureTests: XCTestCase {
    func testGenerateAppcastFailsWhenFetchFailsAndMissingNotAllowed() throws {
        var env = ProcessInfo.processInfo.environment
        env["VERSION"] = "0.0.0-test"
        env["DMG_FILE"] = "Spacemap.dmg"
        env["DMG_SIZE"] = "12345"
        env["APPCAST_URL"] = "https://example.invalid/appcast.xml"
        // Do not set ALLOW_MISSING_APPCAST (defaults to 0)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [".github/scripts/generate-appcast.sh"]
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertNotEqual(process.terminationStatus, 0, "Script should fail when fetch fails and missing appcast not allowed")
    }
}
