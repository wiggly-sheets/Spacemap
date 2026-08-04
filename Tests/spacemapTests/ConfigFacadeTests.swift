import XCTest
@testable import spacemap

final class ConfigFacadeTests: XCTestCase {

    // MARK: - ConfigValuesProtocol Conformance

    func testConfigValuesConformsToProtocol() {
        let values = ConfigValues()
        assertConformsToConfigValuesProtocol(values)
    }

    func testConfigValuesFromGridConfigRoundTrip() {
        let config = GridConfig.default
        let values = ConfigValues(from: config)
        assertConformsToConfigValuesProtocol(values)
        XCTAssertEqual(values.cols, config.cols)
        XCTAssertEqual(values.rows, config.rows)
        // HotkeyConfig does not conform to Equatable; compare individual fields
        XCTAssertEqual(values.hotkey?.key, config.hotkey.key)
        XCTAssertEqual(values.pinnedHotkey?.key, config.pinnedHotkey.key)
    }

    // MARK: - TOMLParserProtocol Conformance

    func testTOMLParserConformsToProtocol() {
        let parser: TOMLParserProtocol.Type = TOMLParser.self
        let values = try! parser.parse("[grid]\ncols = 5\n")
        XCTAssertEqual(values.cols, 5)
    }

    // MARK: - ConfigLoaderProtocol Conformance

    func testConfigLoaderConformsToProtocol() {
        let loader: ConfigLoaderProtocol.Type = ConfigLoader.self
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-protocol-test-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        defer { try? FileManager.default.removeItem(at: directory) }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let (values, needsRepair) = loader.load(from: path, silentMode: true)
        assertConformsToConfigValuesProtocol(values)
        XCTAssertTrue(needsRepair)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - Config Facade Delegation Tests

    func testLoadDelegatesToConfigLoader() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-facade-load-\(UUID().uuidString)")
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

        Config.silentMode = true
        defer { Config.silentMode = false }

        let facadeResult = Config.load(from: path)
        let directResult = ConfigLoader.load(from: path, silentMode: true)
            .values.toGridConfig().config

        XCTAssertEqual(facadeResult.cols, directResult.cols)
        XCTAssertEqual(facadeResult.rows, directResult.rows)
        XCTAssertEqual(facadeResult.cellStyle, directResult.cellStyle)
    }

    func testParseConfigDelegatesToTOMLParser() {
        let toml = """
        [grid]
        cols = 8
        rows = 4

        [behavior.hotkey]
        keyKind = "keyCode"
        keyCode = 49
        modifiers = ["cmd"]
        """

        let facadeResult = Config.parseConfig(toml)
        let directResult = try! TOMLParser.parse(toml).toGridConfig().config

        XCTAssertEqual(facadeResult.cols, directResult.cols)
        XCTAssertEqual(facadeResult.rows, directResult.rows)
        XCTAssertEqual(facadeResult.hotkey.keyCode, directResult.hotkey.keyCode)
        XCTAssertTrue(facadeResult.hotkey.modifiers.contains(.maskCommand))
    }

    func testSaveConfigDelegatesToConfigLoader() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-facade-save-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        Config.silentMode = true
        defer { Config.silentMode = false }

        var values = ConfigValues()
        values.cols = 10
        values.rows = 5
        values.theme = "nord"
        let config = values.toGridConfig().config

        Config.saveConfig(config, to: path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        let content = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(content.contains("cols = 10"))
        XCTAssertTrue(content.contains("rows = 5"))
        XCTAssertTrue(content.contains("nord"))
    }

    func testLoadReturnsDefaultWhenFileMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-facade-missing-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        defer { try? FileManager.default.removeItem(at: directory) }

        Config.silentMode = true
        defer { Config.silentMode = false }

        let result = Config.load(from: path)

        XCTAssertEqual(result.cols, GridConfig.default.cols)
        XCTAssertEqual(result.theme, GridConfig.default.theme)
    }

    func testLoadAndSaveRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-facade-roundtrip-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        Config.silentMode = true
        defer { Config.silentMode = false }

        let original = Config.parseConfig("""
        [grid]
        cols = 7
        rows = 4
        cellStyle = "hybrid"

        [behavior.hotkey]
        keyKind = "mediaKey"
        mediaKey = "play-pause"
        modifiers = ["ctrl"]
        """)

        Config.saveConfig(original, to: path)
        let reloaded = Config.load(from: path)

        XCTAssertEqual(reloaded.cols, original.cols)
        XCTAssertEqual(reloaded.rows, original.rows)
        XCTAssertEqual(reloaded.cellStyle, original.cellStyle)
        XCTAssertEqual(reloaded.hotkey.mediaKey, original.hotkey.mediaKey)
        XCTAssertTrue(reloaded.hotkey.modifiers.contains(.maskControl))
    }

    func testSilentModeIsRespected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-facade-silent-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        Config.silentMode = true
        defer { Config.silentMode = false }

        // Should not crash or produce output when silentMode is true
        let result = Config.load(from: path)
        XCTAssertEqual(result.cols, GridConfig.default.cols)
    }

    // MARK: - Helpers

    private func assertConformsToConfigValuesProtocol(_ values: ConfigValuesProtocol) {
        // Verify all protocol properties are accessible
        _ = values.cols
        _ = values.rows
        _ = values.cellStyle
        _ = values.hotkey
        _ = values.pinnedHotkey
        _ = values.socketHealthInterval
        _ = values.uiScale
        _ = values.autoHideTimeout
        _ = values.theme
        _ = values.showMode
        _ = values.multiMonitorHUDMode
        _ = values.unifiedHUDVisibility
        _ = values.separateHUDVisibility
        _ = values.displayNavigationWrap
        _ = values.maxSpaces
        _ = values.backgroundAlpha
        _ = values.mode
        _ = values.iconScale
        _ = values.showSpaceNumbers
        _ = values.showSpaceNames
        _ = values.showIconStrip
        _ = values.showMultiAppIcons
        _ = values.hideMenuBarIcon
        _ = values.menuBarDisplayMode
        _ = values.menuBarNearbyCount
        _ = values.spaceNames
        _ = values.useVimKeys
        _ = values.useArrowKeys
        _ = values.hudPosition
        _ = values.customHUDX
        _ = values.customHUDY
        _ = values.showExtraWindows
        _ = values.focusSpaceOnWindowDrop
        _ = values.focusSpaceOnWindowDropModifier
        _ = values.showHUDOnSpaceChange
        _ = values.updateMode

        // Verify toGridConfig works
        let (config, _) = values.toGridConfig()
        XCTAssertNotNil(config)
    }
}
