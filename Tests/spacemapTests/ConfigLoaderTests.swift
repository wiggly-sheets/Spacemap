import XCTest
@testable import spacemap

final class ConfigLoaderTests: XCTestCase {

    // MARK: - Load

    func testLoadCreatesDefaultWhenFileMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-default-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        defer { try? FileManager.default.removeItem(at: directory) }

        let (values, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        let config = values.gridConfig

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.cols, GridConfig.default.cols)
        XCTAssertEqual(config.theme, GridConfig.default.theme)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testLoadParsesValidConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-valid-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let toml = """
        [grid]
        cols = 6
        rows = 3
        cellStyle = "icons"
        """
        try toml.write(toFile: path, atomically: true, encoding: .utf8)

        let (values, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        let config = values.gridConfig

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.cols, 6)
        XCTAssertEqual(config.rows, 3)
        XCTAssertEqual(config.cellStyle, .icons)
    }

    func testLoadRepairsInvalidValues() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-repair-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let toml = """
        [grid]
        cols = 5
        rows = "broken"

        [appearance]
        theme = "nord"
        """
        try toml.write(toFile: path, atomically: true, encoding: .utf8)

        let (values, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        let config = values.gridConfig

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.cols, 5)
        XCTAssertEqual(config.rows, GridConfig.default.rows)
        XCTAssertEqual(config.theme, "nord")
    }

    func testLoadBacksUpInvalidFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-backup-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let invalid = "[grid\ncols = 5"
        try invalid.write(toFile: path, atomically: true, encoding: .utf8)

        let (_, needsRepair) = ConfigLoader.load(from: path, silentMode: true)

        XCTAssertTrue(needsRepair)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path + ".bak"))
        XCTAssertEqual(try String(contentsOfFile: path + ".bak", encoding: .utf8), invalid)
    }

    // MARK: - Save

    func testSaveWritesConfigToFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-save-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var values = ConfigValues()
        values.cols = 10
        values.rows = 5
        values.theme = "nord"
        values.hudShadow = false
        values.jumpToSpaceEnabled = true

        ConfigLoader.save(values, to: path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        let content = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(content.contains("cols = 10"))
        XCTAssertTrue(content.contains("rows = 5"))
        XCTAssertTrue(content.contains("nord"))
        XCTAssertTrue(content.contains("hudShadow = false"))
        XCTAssertTrue(content.contains("jumpToSpaceEnabled = true"))
    }

    func testSaveCreatesBackupBeforeOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-backup-save-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = "cols = 5"
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        var values = ConfigValues()
        values.cols = 10

        ConfigLoader.save(values, to: path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path + ".bak"))
        XCTAssertEqual(try String(contentsOfFile: path + ".bak", encoding: .utf8), original)
    }

    func testSaveRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-roundtrip-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var values = ConfigValues()
        values.cols = 7
        values.rows = 4
        values.cellStyle = .hybrid
        values.theme = "dracula"
        values.showMode = .active
        values.hotkey = HotkeyConfig(key: .keyCode(49), modifiers: .maskCommand)
        values.hudShadow = false
        values.jumpToSpaceEnabled = true

        ConfigLoader.save(values, to: path)

        let (loadedValues, _) = ConfigLoader.load(from: path, silentMode: true)
        let (config, _) = loadedValues.toGridConfig()

        XCTAssertEqual(config.cols, 7)
        XCTAssertEqual(config.rows, 4)
        XCTAssertEqual(config.cellStyle, .hybrid)
        XCTAssertEqual(config.theme, "dracula")
        XCTAssertEqual(config.showMode, .active)
        XCTAssertEqual(config.hotkey.keyCode, 49)
        XCTAssertTrue(config.hotkey.modifiers.contains(.maskCommand))
        XCTAssertFalse(config.hudShadow)
        XCTAssertTrue(config.jumpToSpaceEnabled)
    }

    // MARK: - Create Default Config File

    func testCreateDefaultConfigFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-defaultfile-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        defer { try? FileManager.default.removeItem(at: directory) }

        ConfigLoader.createDefaultConfigFile(at: path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        let content = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(content.contains("[grid]"))
        XCTAssertTrue(content.contains("[spaceNames.names]"))
        XCTAssertTrue(content.contains("[appearance]"))
        XCTAssertTrue(content.contains("[behavior.hotkey]"))
        XCTAssertTrue(content.contains("[advanced]"))
    }

    func testCreateDefaultConfigFileBacksUpExisting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-default-backup-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let existing = "cols = 99"
        try existing.write(toFile: path, atomically: true, encoding: .utf8)

        ConfigLoader.createDefaultConfigFile(at: path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path + ".bak"))
        XCTAssertEqual(try String(contentsOfFile: path + ".bak", encoding: .utf8), existing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }
}
