import XCTest
@testable import spacemap

final class CLISymlinkInstallerTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var targetPath: String!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let targetURL = temporaryDirectory.appendingPathComponent("spacemap")
        try "#!/bin/sh\n".write(to: targetURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetURL.path)
        targetPath = targetURL.path
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testCreatesParentDirectoryAndSymlink() throws {
        let symlinkPath = temporaryDirectory
            .appendingPathComponent("bin/spacemap-cli")
            .path

        XCTAssertEqual(CLISymlinkInstaller.install(symlinkPath: symlinkPath, targetPath: targetPath), .installed)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath), targetPath)
    }

    func testAcceptsExistingCorrectSymlink() throws {
        let symlinkPath = temporaryDirectory.appendingPathComponent("spacemap-cli").path
        try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: targetPath)

        XCTAssertEqual(CLISymlinkInstaller.install(symlinkPath: symlinkPath, targetPath: targetPath), .installed)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath), targetPath)
    }

    func testPreservesConflictingSymlink() throws {
        let symlinkPath = temporaryDirectory.appendingPathComponent("spacemap-cli").path
        let otherTarget = "/usr/bin/true"
        try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: otherTarget)

        XCTAssertEqual(CLISymlinkInstaller.install(symlinkPath: symlinkPath, targetPath: targetPath), .conflictingItem)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath), otherTarget)
    }

    func testPreservesConflictingRegularFile() throws {
        let symlinkPath = temporaryDirectory.appendingPathComponent("spacemap-cli").path
        try "unrelated".write(toFile: symlinkPath, atomically: true, encoding: .utf8)

        XCTAssertEqual(CLISymlinkInstaller.install(symlinkPath: symlinkPath, targetPath: targetPath), .conflictingItem)
        XCTAssertEqual(try String(contentsOfFile: symlinkPath), "unrelated")
    }

    func testDoesNotCreateLinkWhenTargetIsUnavailable() {
        let symlinkPath = temporaryDirectory.appendingPathComponent("spacemap-cli").path

        XCTAssertEqual(
            CLISymlinkInstaller.install(symlinkPath: symlinkPath, targetPath: temporaryDirectory.appendingPathComponent("missing").path),
            .targetUnavailable
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: symlinkPath))
    }
}
