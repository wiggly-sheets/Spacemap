import XCTest
@testable import spacemap

final class ConfigFacadeTests: XCTestCase {

    func testConfigValuesFromGridConfigPreservesCoreSettings() {
        var config = GridConfig.default
        config.cols = 6
        config.rows = 3
        config.hotkey = HotkeyConfig(key: .keyCode(49), modifiers: .maskCommand)

        let values = ConfigValues(from: config)

        XCTAssertEqual(values.cols, config.cols)
        XCTAssertEqual(values.rows, config.rows)
        XCTAssertEqual(values.hotkey, config.hotkey)
        XCTAssertEqual(values.pinnedHotkey, config.pinnedHotkey)
        XCTAssertEqual(values.glyphStripHotkey, config.glyphStripHotkey)
    }

    func testLoadAndSaveRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-facade-roundtrip-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        AppConfig.silentMode = true
        defer { AppConfig.silentMode = false }

        let original = AppConfig.parseConfig("""
        [grid]
        cols = 7
        rows = 4
        cellStyle = "hybrid"

        [behavior.hotkey]
        keyKind = "mediaKey"
        mediaKey = "play-pause"
        modifiers = ["ctrl"]
        """)

        AppConfig.saveConfig(original, to: path)
        let reloaded = AppConfig.load(from: path)

        XCTAssertEqual(reloaded.cols, original.cols)
        XCTAssertEqual(reloaded.rows, original.rows)
        XCTAssertEqual(reloaded.cellStyle, original.cellStyle)
        XCTAssertEqual(reloaded.hotkey.mediaKey, original.hotkey.mediaKey)
        XCTAssertTrue(reloaded.hotkey.modifiers.contains(.maskControl))
    }
}
