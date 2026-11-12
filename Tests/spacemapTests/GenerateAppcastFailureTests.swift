import Foundation
import XCTest

final class GenerateAppcastFailureTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testGenerateAppcastFailsWhenFetchFailsAndMissingNotAllowed() throws {
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-appcast-failure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: workDirectory) }

        let script = repositoryRoot.appendingPathComponent(".github/scripts/generate-appcast.sh").path
        var env = ProcessInfo.processInfo.environment
        env["VERSION"] = "0.0.0-test"
        env["DMG_FILE"] = "Spacemap.dmg"
        env["DMG_SIZE"] = "12345"
        env["ED_SIGNATURE"] = "test-signature"
        env["APPCAST_URL"] = "https://example.invalid/appcast.xml"
        // Pass the signature guard so the fetch policy is what fails.
        env.removeValue(forKey: "ALLOW_MISSING_APPCAST")
        env.removeValue(forKey: "MINIMUM_SYSTEM_VERSION")
        env.removeValue(forKey: "INFO_PLIST")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script]
        process.currentDirectoryURL = workDirectory
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        XCTAssertNotEqual(process.terminationStatus, 0, "Script should fail when fetch fails and missing appcast not allowed")
        XCTAssertTrue(
            output.contains("refusing to truncate release history"),
            "Script should fail at the history guard, not earlier:\n\(output)"
        )
    }
}
