import AppKit
import Foundation
import XCTest
@testable import spacemap

// MARK: - ConfigLoader backup rotation / symlink refusal (Stream A owns source)

final class ConfigLoaderBackupAndSymlinkTests: XCTestCase {
    private func tempDir(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-audit-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testBackupRotatesToBak1() throws {
        let dir = try tempDir("rotation")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("config.toml").path

        var first = SpacemapConfig.default
        first.cols = 11
        ConfigLoader.save(first, to: path)
        var second = SpacemapConfig.default
        second.cols = 22
        ConfigLoader.save(second, to: path)
        var third = SpacemapConfig.default
        third.cols = 33
        ConfigLoader.save(third, to: path)

        XCTAssertTrue(try String(contentsOfFile: path + ".bak", encoding: .utf8).contains("cols = 22"))
        XCTAssertTrue(try String(contentsOfFile: path + ".bak.1", encoding: .utf8).contains("cols = 11"))
    }

    func testLoadRefusesSymlinkAndLeavesTargetUntouched() throws {
        let dir = try tempDir("symlink-load")
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("real.toml")
        try "cols = 5".write(to: target, atomically: true, encoding: .utf8)
        let link = dir.appendingPathComponent("config.toml").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target.path)

        let (config, needsRepair) = ConfigLoader.load(from: link, silentMode: true)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.cols, SpacemapConfig.default.cols)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "cols = 5")
    }

    func testSaveRefusesSymlinkAndLeavesTargetUntouched() throws {
        let dir = try tempDir("symlink-save")
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("real.toml")
        try "cols = 5".write(to: target, atomically: true, encoding: .utf8)
        let link = dir.appendingPathComponent("config.toml").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target.path)

        var values = SpacemapConfig.default
        values.cols = 99
        ConfigLoader.save(values, to: link)

        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "cols = 5")
        XCTAssertFalse(FileManager.default.fileExists(atPath: link + ".bak"))
    }
}
