import Foundation
import XCTest

final class AppcastScriptTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-script-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func run(
        _ executable: String,
        _ arguments: [String],
        workingDirectory: URL? = nil
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func infoPlist() throws -> [String: Any] {
        let url = repositoryRoot.appendingPathComponent("Sources/spacemap/Info.plist")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private func values(of key: String, in project: String) -> [String] {
        let prefix = "\(key) = "
        return project.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix) else { return nil }
            return String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\";"))
        }
    }

    func testGenerateAppcastAllowsMissingWhenFlagSet() throws {
        let workDirectory = try makeTemporaryDirectory()
        let script = repositoryRoot.appendingPathComponent(".github/scripts/generate-appcast.sh").path
        var env = ProcessInfo.processInfo.environment
        env["VERSION"] = "0.0.0-test"
        env["DMG_FILE"] = "Spacemap.dmg"
        env["DMG_SIZE"] = "12345"
        env["ED_SIGNATURE"] = "test-signature-for-missing-appcast-path"
        env["APPCAST_URL"] = "https://example.invalid/appcast.xml"
        env["ALLOW_MISSING_APPCAST"] = "1"
        env.removeValue(forKey: "MINIMUM_SYSTEM_VERSION")
        env.removeValue(forKey: "INFO_PLIST")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script]
        process.currentDirectoryURL = workDirectory
        process.environment = env
        // Capture output to avoid clutter
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "Script should succeed when missing appcast is allowed:\n\(output)")

        let minimum = try XCTUnwrap(try infoPlist()["LSMinimumSystemVersion"] as? String)
        let appcast = try String(
            contentsOf: workDirectory.appendingPathComponent("appcast.xml"),
            encoding: .utf8
        )
        XCTAssertTrue(
            appcast.contains("<sparkle:minimumSystemVersion>\(minimum)</sparkle:minimumSystemVersion>"),
            "Generated appcast should advertise the bundle's minimum macOS version"
        )
    }

    func testGeneratedXcodeProjectIsUpToDate() throws {
        let script = repositoryRoot.appendingPathComponent("scripts/generate-xcodeproj.py").path
        let result = try run("/usr/bin/env", ["python3", script, "--check"])
        XCTAssertEqual(result.status, 0, "generate-xcodeproj.py --check failed:\n\(result.output)")
    }

    func testGenerateXcodeprojRejectsInvalidVersion() throws {
        let root = try makeTemporaryDirectory()
        let scripts = root.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        let script = scripts.appendingPathComponent("generate-xcodeproj.py")
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("scripts/generate-xcodeproj.py"),
            to: script
        )
        let versionURL = root.appendingPathComponent("VERSION")

        try "1.2.3 beta\n".write(to: versionURL, atomically: true, encoding: .utf8)
        let bogus = try run("/usr/bin/env", ["python3", script.path, "--check"])
        XCTAssertNotEqual(bogus.status, 0)
        XCTAssertTrue(bogus.output.contains("must contain a version"), bogus.output)

        try FileManager.default.removeItem(at: versionURL)
        let missing = try run("/usr/bin/env", ["python3", script.path, "--check"])
        XCTAssertNotEqual(missing.status, 0)
        XCTAssertTrue(missing.output.contains("not found"), missing.output)
    }

    func testGeneratedVersionsComeFromVersionFile() throws {
        let versionURL = repositoryRoot.appendingPathComponent("VERSION")
        let version = try String(contentsOf: versionURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(version.isEmpty, "VERSION must not be empty")

        let plist = try infoPlist()
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, version)
        XCTAssertEqual(plist["CFBundleVersion"] as? String, version)

        // Four targets times Debug and Release.
        let projectURL = repositoryRoot.appendingPathComponent("spacemap.xcodeproj/project.pbxproj")
        let project = try String(contentsOf: projectURL, encoding: .utf8)
        let marketingVersions = values(of: "MARKETING_VERSION", in: project)
        let projectVersions = values(of: "CURRENT_PROJECT_VERSION", in: project)
        XCTAssertEqual(marketingVersions.count, 8)
        XCTAssertEqual(projectVersions.count, 8)
        XCTAssertEqual(Set(marketingVersions), Set([version]))
        XCTAssertEqual(Set(projectVersions), Set([version]))
    }

    func testInfoPlistMinimumSystemVersionMatchesDeploymentTarget() throws {
        let minimum = try XCTUnwrap(try infoPlist()["LSMinimumSystemVersion"] as? String)
        XCTAssertFalse(minimum.isEmpty)

        let makefileURL = repositoryRoot.appendingPathComponent("Makefile")
        let makefile = try String(contentsOf: makefileURL, encoding: .utf8)
        let pattern = "(?m)^MACOS_DEPLOYMENT_TARGET\\s*[:?]?=\\s*(\\S+)"
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(makefile.startIndex..<makefile.endIndex, in: makefile)
        let match = try XCTUnwrap(
            regex.firstMatch(in: makefile, range: range),
            "Makefile must define MACOS_DEPLOYMENT_TARGET"
        )
        let capture = try XCTUnwrap(Range(match.range(at: 1), in: makefile))
        XCTAssertEqual(minimum, String(makefile[capture]))
        XCTAssertTrue(
            makefile.contains(":LSMinimumSystemVersion"),
            "The bundle assembly step should set LSMinimumSystemVersion"
        )

        let projectURL = repositoryRoot.appendingPathComponent("spacemap.xcodeproj/project.pbxproj")
        let project = try String(contentsOf: projectURL, encoding: .utf8)
        let projectTargets = values(of: "MACOSX_DEPLOYMENT_TARGET", in: project)
        XCTAssertFalse(projectTargets.isEmpty, "The Xcode project must set MACOSX_DEPLOYMENT_TARGET")
        XCTAssertEqual(Set(projectTargets), Set([minimum]))
    }

    func testInfoPlistProhibitsMultipleInstances() throws {
        let prohibited = try XCTUnwrap(try infoPlist()["LSMultipleInstancesProhibited"] as? Bool)
        XCTAssertTrue(prohibited, "The bundle must declare that multiple instances are prohibited")

        // The assembly step copies the plist verbatim, so the key ships with every bundle.
        let makefile = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Makefile"),
            encoding: .utf8
        )
        XCTAssertTrue(
            makefile.contains("cp Sources/spacemap/Info.plist"),
            "The bundle assembly step should copy the generated Info.plist"
        )
    }
}
