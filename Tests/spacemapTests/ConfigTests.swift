import XCTest
@testable import spacemap

final class ConfigTests: XCTestCase {
    func testSectionedTOMLParsesEverySetting() {
        let config = """
        [grid]
        cols = 6
        rows = 3
        cellStyle = "icons"
        showMode = "active"
        multiMonitorHUDMode = "separate"
        unifiedHUDVisibility = "all"
        separateHUDVisibility = "active"
        maxSpaces = 12
        showSpaceNumbers = false
        showIconStrip = false
        showMultiAppIcons = true

        [spaceNames]
        showSpaceNames = true
        namingMode = "auto"

        [spaceNames.names]
        "1" = "Term"
        "2" = "Code"

        [appearance]
        theme = "default"
        mode = "dark"
        backgroundAlpha = 0.5
        iconScale = 0.8
        uiScale = 0.75

        [behavior]
        autoHideTimeout = 10
        displayNavigationWrap = "between"
        focusSpaceOnWindowDrop = "modifier"
        focusSpaceOnWindowDropModifier = "option"
        showHUDOnSpaceChange = true
        presence = "none"
        menuBarDisplayMode = "nearby"
        menuBarNearbyCount = 5
        updateMode = "off"

        [hudKeys]
        left = ["x"]
        layoutBSP = ["b", "cmd+b"]

        [behavior.hotkey]
        keyKind = "keyCode"
        keyCode = 49
        modifiers = ["cmd", "shift"]

        [behavior.pinnedHotkey]
        keyKind = "mediaKey"
        mediaKey = "play-pause"
        modifiers = ["ctrl"]

        [behavior.hudPosition]
        kind = "custom"
        x = 0.25
        y = 0.75
        screen = "display-A"

        [advanced]
        socketHealthInterval = 30
        showExtraWindows = true
        """
        let c = ConfigStore.parseConfig(config)

        XCTAssertEqual(c.cols, 6)
        XCTAssertEqual(c.rows, 3)
        XCTAssertEqual(c.cellStyle, .icons)
        XCTAssertEqual(c.showMode, .active)
        XCTAssertEqual(c.multiMonitorHUDMode, .separate)
        XCTAssertEqual(c.unifiedHUDVisibility, .all)
        XCTAssertEqual(c.separateHUDVisibility, .active)
        XCTAssertEqual(c.maxSpaces, 12)
        XCTAssertFalse(c.showSpaceNumbers)
        XCTAssertFalse(c.showIconStrip)
        XCTAssertTrue(c.showMultiAppIcons)
        XCTAssertTrue(c.showSpaceNames)
        XCTAssertEqual(c.namingMode, .auto)
        XCTAssertEqual(c.spaceNames, [1: "Term", 2: "Code"])
        XCTAssertEqual(c.theme, "default")
        XCTAssertEqual(c.mode, .dark)
        XCTAssertEqual(c.backgroundAlpha, 0.5, accuracy: 0.001)
        XCTAssertEqual(c.iconScale, 0.8, accuracy: 0.001)
        XCTAssertEqual(c.uiScale, 0.75, accuracy: 0.001)
        XCTAssertEqual(c.autoHideTimeout, 10)
        XCTAssertEqual(c.displayNavigationWrap, .between)
        XCTAssertEqual(c.hudKeys[.left].compactMap(\.keyCode), [7])
        XCTAssertEqual(c.hudKeys[.layoutBSP].compactMap(\.keyCode), [11, 11])
        XCTAssertEqual(c.hudKeys[.layoutBSP].last?.modifiers, .maskCommand)
        XCTAssertEqual(c.hudKeys[.right], HUDKeyBindings.default[.right])
        XCTAssertEqual(c.focusSpaceOnWindowDrop, .modifier)
        XCTAssertEqual(c.focusSpaceOnWindowDropModifier, .option)
        XCTAssertTrue(c.showHUDOnSpaceChange)
        XCTAssertEqual(c.presence, AppPresence.none)
        XCTAssertEqual(c.menuBarDisplayMode, .nearby)
        XCTAssertEqual(c.menuBarNearbyCount, 5)
        XCTAssertEqual(c.updateMode, .off)
        XCTAssertEqual(c.hotkey.keyCode, 49)
        XCTAssertTrue(c.hotkey.modifiers.contains(.maskCommand))
        XCTAssertTrue(c.hotkey.modifiers.contains(.maskShift))
        XCTAssertEqual(c.pinnedHotkey.mediaKey, .playPause)
        XCTAssertTrue(c.pinnedHotkey.modifiers.contains(.maskControl))
        XCTAssertEqual(c.hudPosition, .custom(x: 0.25, y: 0.75, screen: "display-A"))
        XCTAssertEqual(c.socketHealthInterval, 30)
        XCTAssertTrue(c.showExtraWindows)
    }

    func testParseConfigFallsBackToDefaultsForInvalidText() {
        for invalid in ["[grid\ncols = 5", ""] {
            let config = ConfigStore.parseConfig(invalid)

            XCTAssertEqual(config.cols, SpacemapConfig.default.cols)
            XCTAssertEqual(config.rows, SpacemapConfig.default.rows)
            XCTAssertEqual(config.theme, SpacemapConfig.default.theme)
        }
    }

    func testCommentsAndQuotedCommentCharactersParse() {
        let c = ConfigStore.parseConfig("""
        # Comment
        [grid]
        cols = 4 # Inline comment

        [appearance]
        theme = "tokyo # night"
        """)

        XCTAssertEqual(c.cols, 4)
        // Quoted `#` survives parsing and the name is kept even when no theme
        // file matches it; the HUD falls back to the default look at use time.
        XCTAssertEqual(c.theme, "tokyo # night")
    }

    func testHUDPositionPresetsAndInvalidCustomFallBack() {
        for (kind, expected) in [
            ("center", HUDPosition.center),
            ("top", HUDPosition.top),
            ("bottom", HUDPosition.bottom)
        ] {
            let c = ConfigStore.parseConfig("""
            [behavior.hudPosition]
            kind = "\(kind)"
            """)
            XCTAssertEqual(c.hudPosition, expected)
        }

        let invalid = ConfigStore.parseConfig("""
        [behavior.hudPosition]
        kind = "custom"
        x = 2.0
        y = 0.5
        """)
        XCTAssertEqual(invalid.hudPosition, .center)
    }

    func testLoadCreatesGroupedDefaultTOMLWhenFileIsMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-config-generation-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("nested/config.toml").path
        defer { try? FileManager.default.removeItem(at: directory) }

        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        let loaded = ConfigStore.load(from: path)
        let generated = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertEqual(loaded.cols, SpacemapConfig.default.cols)
        XCTAssertEqual(loaded.theme, SpacemapConfig.default.theme)
        XCTAssertTrue(generated.contains("[grid]"))
        XCTAssertTrue(generated.contains("[spaceNames.names]"))
        XCTAssertTrue(generated.contains("namingMode = \"custom\""))
        XCTAssertTrue(generated.contains("autoNameAppCount = 3"))
        XCTAssertTrue(generated.contains("[appearance]"))
        XCTAssertTrue(generated.contains("[behavior.hotkey]"))
        XCTAssertTrue(generated.contains("[advanced]"))
        XCTAssertEqual(ConfigStore.load(from: path).cols, SpacemapConfig.default.cols)
    }

    func testPlainConfigIsRejectedAndReplacedWithDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-config-plain-rejection-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        ConfigStore.silentMode = true
        defer { ConfigStore.silentMode = false }

        let plain = "GRID_COLS=5"
        try plain.write(toFile: path, atomically: true, encoding: .utf8)
        let loaded = ConfigStore.load(from: path)

        XCTAssertEqual(loaded.cols, SpacemapConfig.default.cols)
        XCTAssertEqual(try String(contentsOfFile: path + ".bak", encoding: .utf8), plain)
    }
}
