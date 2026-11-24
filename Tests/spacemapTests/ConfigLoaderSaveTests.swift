import XCTest
@testable import spacemap

final class ConfigLoaderSaveTests: ConfigLoaderTestCase {
    func testSaveCreatesBackupBeforeOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-backup-save-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = "cols = 5"
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        var config = SpacemapConfig.default
        config.cols = 10

        ConfigLoader.save(config, to: path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path + ".bak"))
        XCTAssertEqual(try String(contentsOfFile: path + ".bak", encoding: .utf8), original)
    }

    /// Single save/load contract for the config codec: every shape the app
    /// exposes (grid, keyCode and media-key hotkeys, multi-display, custom HUD
    /// position) survives a disk trip, and a self-written file needs no repair.
    func testSaveRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-roundtrip-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var written = SpacemapConfig.default
        written.cols = 7
        written.rows = 4
        written.cellStyle = .hybrid
        written.theme = "default"
        written.showMode = .active
        written.hotkey = HotkeyConfig(key: .keyCode(49), modifiers: .maskCommand)
        written.pinnedHotkey = HotkeyConfig(key: .mediaKey(.playPause), modifiers: .maskControl)
        written.glyphStripHotkey = HotkeyConfig(key: .keyCode(100), modifiers: .maskShift)
        written.hudShadow = false
        written.jumpToSpaceEnabled = true
        written.multiMonitorHUDMode = .separate
        written.unifiedHUDVisibility = .all
        written.separateHUDVisibility = .active
        written.displayNavigationWrap = .between
        written.menuBarDisplayMode = .all
        written.menuBarNearbyCount = 7
        written.hudPosition = .custom(x: 0.23, y: 0.81, screen: "display-A")

        ConfigLoader.save(written, to: path)

        let (config, needsRepair) = ConfigLoader.load(from: path, silentMode: true)

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config.cols, 7)
        XCTAssertEqual(config.rows, 4)
        XCTAssertEqual(config.cellStyle, .hybrid)
        XCTAssertEqual(config.theme, "default")
        XCTAssertEqual(config.showMode, .active)
        XCTAssertEqual(config.hotkey.keyCode, 49)
        XCTAssertTrue(config.hotkey.modifiers.contains(.maskCommand))
        XCTAssertEqual(config.pinnedHotkey.mediaKey, .playPause)
        XCTAssertTrue(config.pinnedHotkey.modifiers.contains(.maskControl))
        XCTAssertEqual(config.glyphStripHotkey, written.glyphStripHotkey)
        XCTAssertFalse(config.hudShadow)
        XCTAssertTrue(config.jumpToSpaceEnabled)
        XCTAssertEqual(config.multiMonitorHUDMode, .separate)
        XCTAssertEqual(config.unifiedHUDVisibility, .all)
        XCTAssertEqual(config.separateHUDVisibility, .active)
        XCTAssertEqual(config.displayNavigationWrap, .between)
        XCTAssertEqual(config.menuBarDisplayMode, .all)
        XCTAssertEqual(config.menuBarNearbyCount, 7)
        XCTAssertEqual(config.hudPosition, .custom(x: 0.23, y: 0.81, screen: "display-A"))
    }

    func testGeneratedConfigHasBackgroundStylesInAppearanceSection() {
        let toml = ConfigLoader.tomlConfigString(
            from: SpacemapConfig.default,
            includeHeaderComments: true
        )
        let appearance = toml.components(separatedBy: "[appearance]").last ?? ""

        XCTAssertTrue(appearance.contains("backgroundStyle = \"glass\""))
        XCTAssertTrue(appearance.contains("glassStyle = \"regular\""))
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

    func testUpdatePreservesUnrelatedFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-update-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var written = SpacemapConfig.default
        written.cols = 12
        written.rows = 4
        ConfigLoader.save(written, to: path)

        XCTAssertTrue(ConfigLoader.update(at: path, silentMode: true) { config in
            config.rows = 7
        })

        let (config, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config.cols, 12)
        XCTAssertEqual(config.rows, 7)
    }

    func testUpdateWritesOnceWhenRepairIsNeeded() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-update-repair-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = ConfigLoader.tomlConfigString(
            from: SpacemapConfig.default,
            includeHeaderComments: true
        )
        let invalid = valid.replacingOccurrences(of: "cols = 8", with: "cols = 100")
        try invalid.write(toFile: path, atomically: true, encoding: .utf8)

        XCTAssertTrue(ConfigLoader.update(at: path, silentMode: true) { config in
            config.rows = 7
        })

        // A repair write before the mutation would have rotated the backup.
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + ".bak.1"))
        let (config, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config.cols, 32)
        XCTAssertEqual(config.rows, 7)
    }

    func testSaveRotatesOversizedFileToBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-oversized-backup-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bomb = String(repeating: "#", count: ConfigLoader.maxConfigBytes + 1)
        try bomb.write(toFile: path, atomically: true, encoding: .utf8)

        var written = SpacemapConfig.default
        written.cols = 9
        XCTAssertTrue(ConfigLoader.saveReportingResult(written, to: path))

        XCTAssertEqual(try String(contentsOfFile: path + ".bak", encoding: .utf8), bomb)
        let (config, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config.cols, 9)
    }

    func testSaveReportingResultReportsSuccessAndSymlinkFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-save-status-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var config = SpacemapConfig.default
        config.cols = 9
        XCTAssertTrue(ConfigLoader.saveReportingResult(config, to: path))

        let target = directory.appendingPathComponent("real.toml")
        try "cols = 5".write(toFile: target.path, atomically: true, encoding: .utf8)
        let link = directory.appendingPathComponent("link.toml").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target.path)

        XCTAssertFalse(ConfigLoader.saveReportingResult(config, to: link))
        XCTAssertEqual(try String(contentsOfFile: target.path, encoding: .utf8), "cols = 5")
        XCTAssertEqual(
            ConfigLoader.loadReportingResult(from: link, silentMode: true).status,
            .unreadable
        )
    }

    func testRepairSaveWritesSilentlyClampedValuesImmediately() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-heal-on-save-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // A silent clamp does not flag repair on its own, so a second missing
        // key supplies the rewrite that carries the clamped value to the file.
        let valid = ConfigLoader.tomlConfigString(
            from: SpacemapConfig.default,
            includeHeaderComments: true
        )
        let invalid = valid
            .replacingOccurrences(of: "spacesCornerRadius = 4.0", with: "spacesCornerRadius = 999.0")
            .replacingOccurrences(of: "showSpaceLayout = false\n", with: "")
        try invalid.write(toFile: path, atomically: true, encoding: .utf8)

        let (config, needsRepair) = ConfigLoader.load(from: path, silentMode: true)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.spacesCornerRadius, 60)
        XCTAssertTrue(try String(contentsOfFile: path, encoding: .utf8)
            .contains("spacesCornerRadius = 60.0"),
                      "the repair save writes the repaired value, not the raw one")
    }

    func testConcurrentSavesRemainParseable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-concurrent-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        DispatchQueue.concurrentPerform(iterations: 16) { index in
            var config = SpacemapConfig.default
            config.cols = (index % 8) + 1
            ConfigLoader.save(config, to: path)
        }

        let (config, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        XCTAssertFalse(needsRepair)
        XCTAssertTrue((1...8).contains(config.cols))
    }
}
