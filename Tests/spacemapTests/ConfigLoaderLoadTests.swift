import XCTest
@testable import spacemap

final class ConfigLoaderLoadTests: ConfigLoaderTestCase {
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

        let (config, needsRepair) = ConfigLoader.load(from: path, silentMode: true)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.cols, 6)
        XCTAssertEqual(config.rows, 3)
        XCTAssertEqual(config.cellStyle, .icons)
    }

    func testLoadRewritesDecoderRejectedNumericEnumAndHotkeyValues() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-rejected-values-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = ConfigLoader.tomlConfigString(
            from: SpacemapConfig.default,
            includeHeaderComments: true
        )
        let invalid = valid
            .replacingOccurrences(of: "rows = 2", with: "rows = -1")
            .replacingOccurrences(of: "cellStyle = \"rects\"", with: "cellStyle = \"broken\"")
            .replacingOccurrences(of: "keyKind = \"keyCode\"", with: "keyKind = \"broken\"")
        try invalid.write(toFile: path, atomically: true, encoding: .utf8)

        let (config, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        let repaired = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.cols, SpacemapConfig.default.cols,
                       "valid neighbours must survive the repair")
        XCTAssertEqual(config.rows, SpacemapConfig.default.rows)
        XCTAssertEqual(config.cellStyle, SpacemapConfig.default.cellStyle)
        XCTAssertEqual(config.hotkey.key, SpacemapConfig.default.hotkey.key)
        XCTAssertTrue(repaired.contains("rows = \(SpacemapConfig.default.rows)"))
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
            from: SpacemapConfig.default,
            includeHeaderComments: true
        )
        let invalid = valid.replacingOccurrences(
            of: "[spaceNames.names]\n",
            with: "[spaceNames.names]\n\"not-a-space\" = \"Name\"\n\"1\" = 42\n"
        )
        try invalid.write(toFile: path, atomically: true, encoding: .utf8)

        let (config, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        let repaired = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.spaceNames, [:])
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
            from: SpacemapConfig.default,
            includeHeaderComments: true
        )
        let mixed = valid.replacingOccurrences(
            of: "[spaceNames.names]\n",
            with: "[spaceNames.names]\n\"1\" = \"Work\"\n\"bad\" = \"Broken\"\n"
        )
        try mixed.write(toFile: path, atomically: true, encoding: .utf8)

        let (config, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        let repaired = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.spaceNames, [1: "Work"])
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
        XCTAssertEqual(result.config.cols, SpacemapConfig.default.cols)
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


    func testBackgroundStyleRepairsInvalidToDefault() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-bgstyle-repair-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = ConfigLoader.tomlConfigString(
            from: SpacemapConfig.default,
            includeHeaderComments: true
        )
        let invalid = valid
            .replacingOccurrences(of: "backgroundStyle = \"glass\"", with: "backgroundStyle = \"broken\"")
            .replacingOccurrences(of: "glassStyle = \"regular\"", with: "glassStyle = \"broken\"")
        try invalid.write(toFile: path, atomically: true, encoding: .utf8)

        let (config, needsRepair) = ConfigLoader.load(from: path, silentMode: true)
        let repaired = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.backgroundStyle, SpacemapConfig.default.backgroundStyle)
        XCTAssertEqual(config.glassStyle, SpacemapConfig.default.glassStyle)
        XCTAssertTrue(repaired.contains("backgroundStyle = \"glass\""))
        XCTAssertTrue(repaired.contains("glassStyle = \"regular\""))
        XCTAssertFalse(repaired.contains("broken"))
    }

    func testRepairConvergesOnSecondLoad() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-converge-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = ConfigLoader.tomlConfigString(
            from: SpacemapConfig.default,
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
        XCTAssertEqual(first.cols, 32)
        XCTAssertEqual(first.glyphStrip.maxIconsPerSpace, 16)
        XCTAssertEqual(second.cols, 32)
        XCTAssertEqual(second.glyphStrip.maxIconsPerSpace, 16)
        XCTAssertTrue(try String(contentsOfFile: path, encoding: .utf8).contains("cols = 32"))
        // A second save would have rotated the first backup; its absence
        // proves the converged load did not rewrite anything.
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + ".bak.1"))
    }

    func testLoadAcceptsBenignTOMLVariantsWithoutRepair() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-benign-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = ConfigLoader.tomlConfigString(
            from: SpacemapConfig.default,
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

        let (config, needsRepair) = ConfigLoader.load(from: path, silentMode: true)

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config.cols, 8)
        XCTAssertEqual(config.rows, 10)
        XCTAssertEqual(config.glyphStrip.maxIconsPerSpace, 8)
    }

    func testU2028SpaceNameIsSanitizedAndRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-loader-2028-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rawName = "Work\u{2028}Space"
        let valid = ConfigLoader.tomlConfigString(
            from: SpacemapConfig.default,
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
        XCTAssertEqual(first.spaceNames[1], "Work Space")
        XCTAssertFalse(rewritten.unicodeScalars.contains { $0.value == 0x2028 })
        XCTAssertFalse(secondRepair)
        XCTAssertEqual(second.spaceNames[1], "Work Space")

        // The writer escapes separators so a label containing one survives a
        // direct write/read cycle too.
        let escaped = ConfigLoader.tomlString(rawName)
        XCTAssertFalse(escaped.unicodeScalars.contains { $0.value == 0x2028 })
        let parsed = try TOMLParser.parse("[spaceNames.names]\n\"1\" = \(escaped)")
        XCTAssertEqual(parsed.config.spaceNames[1], rawName)
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
        XCTAssertEqual(result.config.cols, SpacemapConfig.default.cols)
        XCTAssertEqual(result.config.theme, SpacemapConfig.default.theme)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), bomb)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + ".bak"))
    }

}
