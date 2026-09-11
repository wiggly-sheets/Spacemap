import XCTest

final class AppcastScriptTests: XCTestCase {
    func testGenerateAppcastAllowsMissingWhenFlagSet() throws {
        // Set environment to force missing appcast
        var env = ProcessInfo.processInfo.environment
        env["VERSION"] = "0.0.0-test"
        env["DMG_FILE"] = "Spacemap.dmg"
        env["DMG_SIZE"] = "12345"
        env["APPCAST_URL"] = "https://example.invalid/appcast.xml"
        env["ALLOW_MISSING_APPCAST"] = "1"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [".github/scripts/generate-appcast.sh"]
        process.environment = env
        // Capture output to avoid clutter
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "Script should succeed when missing appcast is allowed")
    }
}
