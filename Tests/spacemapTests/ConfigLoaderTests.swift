import XCTest
@testable import spacemap

final class ConfigLoaderTests: XCTestCase {


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

    func testLoadRewritesDecoderRejectedNumericEnumAndHotkeyValues() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-rejected-values-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = ConfigLoader.tomlConfigString(
            from: ConfigValues(from: .default),
            includeHeaderComments: true
        )
        let invalid = valid
            .replacingOccurrences(of: "rows = 2", with: "rows = -1")
            .replacingOccurrences(of: "cellStyle = \"rects\"", with: "cellStyle = \"broken\"")
            .replacingOccurrences(of: "keyKind = \"keyCode\"", with: "keyKind = \"broken\"")
        try invalid.write(toFile: path, atomically: true, encoding: .utf8)

        let (values, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        let repaired = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(values.gridConfig.rows, GridConfig.default.rows)
        XCTAssertEqual(values.gridConfig.cellStyle, GridConfig.default.cellStyle)
        XCTAssertEqual(values.gridConfig.hotkey.key, GridConfig.default.hotkey.key)
        XCTAssertTrue(repaired.contains("rows = \(GridConfig.default.rows)"))
        XCTAssertTrue(repaired.contains("cellStyle = \"rects\""))
        XCTAssertTrue(repaired.contains("keyKind = \"keyCode\""))
        XCTAssertFalse(repaired.contains("broken"))
        XCTAssertEqual(try String(contentsOfFile: path + ".bak", encoding: .utf8), invalid)
    }

    func testLoadRepairsAllInvalidSpaceNameEntries() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-invalid-space-names-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = ConfigLoader.tomlConfigString(
            from: ConfigValues(from: .default),
            includeHeaderComments: true
        )
        let invalid = valid.replacingOccurrences(
            of: "[spaceNames.names]\n",
            with: "[spaceNames.names]\n\"not-a-space\" = \"Name\"\n\"1\" = 42\n"
        )
        try invalid.write(toFile: path, atomically: true, encoding: .utf8)

        let (values, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        let repaired = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(values.gridConfig.spaceNames, [:])
        XCTAssertFalse(repaired.contains("not-a-space"))
        XCTAssertFalse(repaired.contains("\"1\" = 42"))
    }

    func testLoadPreservesValidSpaceNamesWhileRemovingInvalidEntries() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-mixed-space-names-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = ConfigLoader.tomlConfigString(
            from: ConfigValues(from: .default),
            includeHeaderComments: true
        )
        let mixed = valid.replacingOccurrences(
            of: "[spaceNames.names]\n",
            with: "[spaceNames.names]\n\"1\" = \"Work\"\n\"bad\" = \"Broken\"\n"
        )
        try mixed.write(toFile: path, atomically: true, encoding: .utf8)

        let (values, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        let repaired = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(values.gridConfig.spaceNames, [1: "Work"])
        XCTAssertTrue(repaired.contains("\"1\" = \"Work\""))
        XCTAssertFalse(repaired.contains("\"bad\""))
    }

    func testParseFailureLeavesFileUntouched() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-parse-failure-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let invalid = "[grid\ncols = 5"
        try invalid.write(toFile: path, atomically: true, encoding: .utf8)

        let result = ConfigLoader.loadReportingResult(from: path, silentMode: true)

        XCTAssertEqual(result.status, .parseFailed)
        XCTAssertTrue(result.needsRepair)
        XCTAssertEqual(result.values.gridConfig.cols, GridConfig.default.cols)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), invalid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + ".bak"))
    }

    func testUpdateBailsOnParseFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-update-parse-failure-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let invalid = "[grid\ncols = 5"
        try invalid.write(toFile: path, atomically: true, encoding: .utf8)

        XCTAssertFalse(ConfigLoader.update(at: path, silentMode: true) { $0.cols = 9 })
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), invalid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + ".bak"))
    }


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

        let (loadedValues, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        let (config, _) = loadedValues.toGridConfig()

        XCTAssertFalse(needsRepair)
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

    func testBackgroundStyleRepairsInvalidToDefault() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-bgstyle-repair-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = ConfigLoader.tomlConfigString(
            from: ConfigValues(from: .default),
            includeHeaderComments: true
        )
        let invalid = valid
            .replacingOccurrences(of: "backgroundStyle = \"glass\"", with: "backgroundStyle = \"broken\"")
            .replacingOccurrences(of: "glassStyle = \"opaque\"", with: "glassStyle = \"broken\"")
        try invalid.write(toFile: path, atomically: true, encoding: .utf8)

        let (values, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        let repaired = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(values.gridConfig.backgroundStyle, GridConfig.default.backgroundStyle)
        XCTAssertEqual(values.gridConfig.glassStyle, GridConfig.default.glassStyle)
        XCTAssertTrue(repaired.contains("backgroundStyle = \"glass\""))
        XCTAssertTrue(repaired.contains("glassStyle = \"opaque\""))
        XCTAssertFalse(repaired.contains("broken"))
    }

    func testGeneratedConfigHasBackgroundStylesInAppearanceSection() {
        let toml = ConfigLoader.tomlConfigString(
            from: ConfigValues(from: .default),
            includeHeaderComments: true
        )
        let appearance = toml.components(separatedBy: "[appearance]").last ?? ""

        XCTAssertTrue(appearance.contains("backgroundStyle = \"glass\""))
        XCTAssertTrue(appearance.contains("glassStyle = \"opaque\""))
    }


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

    func testRepairConvergesOnSecondLoad() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-converge-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = ConfigLoader.tomlConfigString(
            from: ConfigValues(from: .default),
            includeHeaderComments: true
        )
        let invalid = valid
            .replacingOccurrences(of: "cols = 8", with: "cols = 9223372036854775807")
            .replacingOccurrences(of: "maxIconsPerSpace = 8", with: "maxIconsPerSpace = 100")
        try invalid.write(toFile: path, atomically: true, encoding: .utf8)

        let (first, firstRepair) = ConfigLoader.load(from: path, silentMode: true)
        let (second, secondRepair) = ConfigLoader.load(from: path, silentMode: true)

        XCTAssertTrue(firstRepair)
        XCTAssertFalse(secondRepair, "the repaired file must not re-trigger repair")
        XCTAssertEqual(first.gridConfig.cols, 32)
        XCTAssertEqual(first.gridConfig.glyphStrip.maxIconsPerSpace, 16)
        XCTAssertEqual(second.gridConfig.cols, 32)
        XCTAssertEqual(second.gridConfig.glyphStrip.maxIconsPerSpace, 16)
        XCTAssertTrue(try String(contentsOfFile: path, encoding: .utf8).contains("cols = 32"))
        // A second save would have rotated the first backup; its absence
        // proves the converged load did not rewrite anything.
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + ".bak.1"))
    }

    func testUpdatePreservesUnrelatedFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-update-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var values = ConfigValues()
        values.cols = 12
        values.rows = 4
        ConfigLoader.save(values, to: path)

        XCTAssertTrue(ConfigLoader.update(at: path, silentMode: true) { config in
            config.rows = 7
        })

        let (reloaded, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        XCTAssertFalse(needsRepair)
        XCTAssertEqual(reloaded.gridConfig.cols, 12)
        XCTAssertEqual(reloaded.gridConfig.rows, 7)
    }

    func testLoadAcceptsBenignTOMLVariantsWithoutRepair() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-benign-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = ConfigLoader.tomlConfigString(
            from: ConfigValues(from: .default),
            includeHeaderComments: true
        )
        let variant = valid
            .replacingOccurrences(of: "cols = 8", with: "cols = 0x8")
            .replacingOccurrences(of: "rows = 2", with: "rows = 1_0")
            .replacingOccurrences(of: "maxIconsPerSpace = 8", with: "maxIconsPerSpace = 0x8")
            .replacingOccurrences(
                of: "modifiers = [\"ctrl\"]",
                with: "modifiers = [\n    \"ctrl\",\n  ]"
            )
        try variant.write(toFile: path, atomically: true, encoding: .utf8)

        let (values, needsRepair) = ConfigLoader.load(from: path, silentMode: true)

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(values.gridConfig.cols, 8)
        XCTAssertEqual(values.gridConfig.rows, 10)
        XCTAssertEqual(values.gridConfig.glyphStrip.maxIconsPerSpace, 8)
    }

    func testAdvertisedThemeSpellingLoadsWithoutRepair() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-theme-spelling-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = ConfigLoader.tomlConfigString(
            from: ConfigValues(from: .default),
            includeHeaderComments: true
        )
        for name in ["monokai-dark", "tokyonight"] {
            let variant = valid.replacingOccurrences(
                of: "theme = \"default\"",
                with: "theme = \"\(name)\""
            )
            try variant.write(toFile: path, atomically: true, encoding: .utf8)

            let (values, needsRepair) = ConfigLoader.load(from: path, silentMode: true)

            XCTAssertFalse(needsRepair, "\(name) should resolve")
            XCTAssertEqual(values.gridConfig.theme, name, "spelling must be preserved")
        }
    }

    func testUpdateWritesOnceWhenRepairIsNeeded() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-update-repair-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = ConfigLoader.tomlConfigString(
            from: ConfigValues(from: .default),
            includeHeaderComments: true
        )
        let invalid = valid.replacingOccurrences(of: "cols = 8", with: "cols = 100")
        try invalid.write(toFile: path, atomically: true, encoding: .utf8)

        XCTAssertTrue(ConfigLoader.update(at: path, silentMode: true) { config in
            config.rows = 7
        })

        // A repair write before the mutation would have rotated the backup.
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + ".bak.1"))
        let (reloaded, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        XCTAssertFalse(needsRepair)
        XCTAssertEqual(reloaded.gridConfig.cols, 32)
        XCTAssertEqual(reloaded.gridConfig.rows, 7)
    }

    func testSaveRotatesOversizedFileToBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-oversized-backup-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bomb = String(repeating: "#", count: ConfigLoader.maxConfigBytes + 1)
        try bomb.write(toFile: path, atomically: true, encoding: .utf8)

        var values = ConfigValues()
        values.cols = 9
        XCTAssertTrue(ConfigLoader.saveReportingResult(values, to: path))

        XCTAssertEqual(try String(contentsOfFile: path + ".bak", encoding: .utf8), bomb)
        let (reloaded, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        XCTAssertFalse(needsRepair)
        XCTAssertEqual(reloaded.gridConfig.cols, 9)
    }

    func testU2028SpaceNameIsSanitizedAndRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-2028-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rawName = "Work\u{2028}Space"
        let valid = ConfigLoader.tomlConfigString(
            from: ConfigValues(from: .default),
            includeHeaderComments: true
        )
        let raw = valid.replacingOccurrences(
            of: "[spaceNames.names]\n",
            with: "[spaceNames.names]\n\"1\" = \"\(rawName)\"\n"
        )
        try raw.write(toFile: path, atomically: true, encoding: .utf8)

        let (first, firstRepair) = ConfigLoader.load(from: path, silentMode: true)
        let rewritten = try String(contentsOfFile: path, encoding: .utf8)
        let (second, secondRepair) = ConfigLoader.load(from: path, silentMode: true)

        XCTAssertTrue(firstRepair)
        XCTAssertEqual(first.gridConfig.spaceNames[1], "Work Space")
        XCTAssertFalse(rewritten.unicodeScalars.contains { $0.value == 0x2028 })
        XCTAssertFalse(secondRepair)
        XCTAssertEqual(second.gridConfig.spaceNames[1], "Work Space")

        // The writer escapes separators so a label containing one survives a
        // direct write/read cycle too.
        let escaped = ConfigLoader.tomlString(rawName)
        XCTAssertFalse(escaped.unicodeScalars.contains { $0.value == 0x2028 })
        let parsed = try TOMLParser.parse("[spaceNames.names]\n\"1\" = \(escaped)")
        XCTAssertEqual(parsed.spaceNames?[1], rawName)
    }

    func testOversizedConfigIsLeftUntouched() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-oversized-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bomb = String(repeating: "#", count: ConfigLoader.maxConfigBytes + 1)
        try bomb.write(toFile: path, atomically: true, encoding: .utf8)

        let result = ConfigLoader.loadReportingResult(from: path, silentMode: true)

        XCTAssertEqual(result.status, .oversized)
        XCTAssertTrue(result.needsRepair)
        XCTAssertEqual(result.values.gridConfig.cols, GridConfig.default.cols)
        XCTAssertEqual(result.values.gridConfig.theme, GridConfig.default.theme)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), bomb)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + ".bak"))
    }

    func testSaveReportingResultReportsSuccessAndSymlinkFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-save-status-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var values = ConfigValues()
        values.cols = 9
        XCTAssertTrue(ConfigLoader.saveReportingResult(values, to: path))

        let target = directory.appendingPathComponent("real.toml")
        try "cols = 5".write(toFile: target.path, atomically: true, encoding: .utf8)
        let link = directory.appendingPathComponent("link.toml").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target.path)

        XCTAssertFalse(ConfigLoader.saveReportingResult(values, to: link))
        XCTAssertEqual(try String(contentsOfFile: target.path, encoding: .utf8), "cols = 5")
        XCTAssertEqual(
            ConfigLoader.loadReportingResult(from: link, silentMode: true).status,
            .unreadable
        )
    }

    func testConcurrentSavesRemainParseable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-concurrent-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        DispatchQueue.concurrentPerform(iterations: 16) { index in
            var values = ConfigValues()
            values.cols = (index % 8) + 1
            ConfigLoader.save(values, to: path)
        }

        let (values, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        XCTAssertFalse(needsRepair)
        XCTAssertTrue((1...8).contains(values.gridConfig.cols))
    }
}
