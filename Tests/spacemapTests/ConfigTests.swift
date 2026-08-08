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

        [spaceNames.names]
        "1" = "Term"
        "2" = "Code"

        [appearance]
        theme = "dracula"
        mode = "dark"
        backgroundAlpha = 0.5
        iconScale = 0.8
        uiScale = 0.75

        [behavior]
        autoHideTimeout = 10
        displayNavigationWrap = "between"
        useVimKeys = true
        useArrowKeys = true
        customHUDX = 0.25
        customHUDY = 0.75
        focusSpaceOnWindowDrop = "modifier"
        focusSpaceOnWindowDropModifier = "option"
        showHUDOnSpaceChange = true
        hideMenuBarIcon = true
        menuBarDisplayMode = "nearby"
        menuBarNearbyCount = 5
        updateMode = "off"

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

        [advanced]
        socketHealthInterval = 30
        showExtraWindows = true
        """
        let c = Config.parseConfig(config)

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
        XCTAssertEqual(c.spaceNames, [1: "Term", 2: "Code"])
        XCTAssertEqual(c.theme, "dracula")
        XCTAssertEqual(c.mode, .dark)
        XCTAssertEqual(c.backgroundAlpha, 0.5, accuracy: 0.001)
        XCTAssertEqual(c.iconScale, 0.8, accuracy: 0.001)
        XCTAssertEqual(c.uiScale, 0.75, accuracy: 0.001)
        XCTAssertEqual(c.autoHideTimeout, 10)
        XCTAssertEqual(c.displayNavigationWrap, .between)
        XCTAssertTrue(c.useVimKeys)
        XCTAssertTrue(c.useArrowKeys)
        XCTAssertEqual(c.focusSpaceOnWindowDrop, .modifier)
        XCTAssertEqual(c.focusSpaceOnWindowDropModifier, .option)
        XCTAssertTrue(c.showHUDOnSpaceChange)
        XCTAssertTrue(c.hideMenuBarIcon)
        XCTAssertEqual(c.menuBarDisplayMode, .nearby)
        XCTAssertEqual(c.menuBarNearbyCount, 5)
        XCTAssertEqual(c.updateMode, .off)
        XCTAssertEqual(c.hotkey.keyCode, 49)
        XCTAssertTrue(c.hotkey.modifiers.contains(.maskCommand))
        XCTAssertTrue(c.hotkey.modifiers.contains(.maskShift))
        XCTAssertEqual(c.pinnedHotkey.mediaKey, .playPause)
        XCTAssertTrue(c.pinnedHotkey.modifiers.contains(.maskControl))
        XCTAssertEqual(c.hudPosition, .custom(x: 0.25, y: 0.75))
        XCTAssertEqual(c.customHUDX, 0.25, accuracy: 0.001)
        XCTAssertEqual(c.customHUDY, 0.75, accuracy: 0.001)
        XCTAssertEqual(c.socketHealthInterval, 30)
        XCTAssertTrue(c.showExtraWindows)
    }

    func testMissingFieldsUseDefaults() {
        let c = Config.parseConfig("""
        [grid]
        cols = 5
        """)

        XCTAssertEqual(c.cols, 5)
        XCTAssertEqual(c.rows, GridConfig.default.rows)
        XCTAssertEqual(c.theme, GridConfig.default.theme)
        XCTAssertEqual(c.hotkey.keyCode, GridConfig.default.hotkey.keyCode)
        XCTAssertEqual(c.focusSpaceOnWindowDrop, .never)
        XCTAssertEqual(c.focusSpaceOnWindowDropModifier, .command)
        XCTAssertFalse(c.showHUDOnSpaceChange)
    }

    func testInvalidValuesUseDefaults() {
        let c = Config.parseConfig("""
        [grid]
        cols = 0
        rows = "broken"
        cellStyle = "invalid"
        maxSpaces = 99

        [appearance]
        mode = "invalid"
        backgroundAlpha = 2.0
        iconScale = -1.0
        uiScale = 5.0

        [behavior]
        autoHideTimeout = -1
        menuBarDisplayMode = "invalid"
        menuBarNearbyCount = 99

        [advanced]
        socketHealthInterval = 0
        """)

        XCTAssertEqual(c.cols, GridConfig.default.cols)
        XCTAssertEqual(c.rows, GridConfig.default.rows)
        XCTAssertEqual(c.cellStyle, GridConfig.default.cellStyle)
        XCTAssertEqual(c.maxSpaces, GridConfig.default.maxSpaces)
        XCTAssertEqual(c.mode, GridConfig.default.mode)
        XCTAssertEqual(c.backgroundAlpha, GridConfig.default.backgroundAlpha)
        XCTAssertEqual(c.iconScale, GridConfig.default.iconScale)
        XCTAssertEqual(c.uiScale, GridConfig.default.uiScale)
        XCTAssertEqual(c.autoHideTimeout, GridConfig.default.autoHideTimeout)
        XCTAssertEqual(c.menuBarDisplayMode, GridConfig.default.menuBarDisplayMode)
        XCTAssertEqual(c.menuBarNearbyCount, GridConfig.default.menuBarNearbyCount)
        XCTAssertEqual(c.socketHealthInterval, GridConfig.default.socketHealthInterval)
    }

    func testCommentsAndQuotedCommentCharactersParse() {
        let c = Config.parseConfig("""
        # Comment
        [grid]
        cols = 4 # Inline comment

        [appearance]
        theme = "tokyo # night"
        """)

        XCTAssertEqual(c.cols, 4)
        XCTAssertEqual(c.theme, "tokyo # night")
    }

    func testHUDPositionPresets() {
        for (kind, expected) in [
            ("center", HUDPosition.center),
            ("top", HUDPosition.top),
            ("bottom", HUDPosition.bottom)
        ] {
            let c = Config.parseConfig("""
            [behavior.hudPosition]
            kind = "\(kind)"
            """)
            XCTAssertEqual(c.hudPosition, expected)
        }
    }

    func testInvalidCustomHUDPositionUsesCenter() {
        let c = Config.parseConfig("""
        [behavior.hudPosition]
        kind = "custom"
        x = 2.0
        y = 0.5
        """)
        XCTAssertEqual(c.hudPosition, .center)
    }

    func testCustomHUDAndMultiDisplaySettingsRoundTripThroughDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-config-roundtrip-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        Config.silentMode = true
        defer { Config.silentMode = false }

        let original = Config.parseConfig("""
        [grid]
        multiMonitorHUDMode = "separate"
        unifiedHUDVisibility = "all"
        separateHUDVisibility = "active"

        [behavior]
        displayNavigationWrap = "between"
        customHUDX = 0.23
        customHUDY = 0.81
        menuBarDisplayMode = "all"
        menuBarNearbyCount = 7

        [behavior.hudPosition]
        kind = "custom"
        x = 0.23
        y = 0.81
        """)
        Config.saveConfig(original, to: path)
        let reloaded = Config.load(from: path)

        XCTAssertEqual(reloaded.multiMonitorHUDMode, .separate)
        XCTAssertEqual(reloaded.unifiedHUDVisibility, .all)
        XCTAssertEqual(reloaded.separateHUDVisibility, .active)
        XCTAssertEqual(reloaded.displayNavigationWrap, .between)
        XCTAssertEqual(reloaded.menuBarDisplayMode, .all)
        XCTAssertEqual(reloaded.menuBarNearbyCount, 7)
        XCTAssertEqual(reloaded.customHUDX, 0.23, accuracy: 0.001)
        XCTAssertEqual(reloaded.customHUDY, 0.81, accuracy: 0.001)
        XCTAssertEqual(reloaded.hudPosition, .custom(x: 0.23, y: 0.81))
    }

    func testLoadCreatesGroupedDefaultTOMLWhenFileIsMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-config-generation-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("nested/config.toml").path
        defer { try? FileManager.default.removeItem(at: directory) }

        Config.silentMode = true
        defer { Config.silentMode = false }

        let loaded = Config.load(from: path)
        let generated = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertEqual(loaded.cols, GridConfig.default.cols)
        XCTAssertEqual(loaded.theme, GridConfig.default.theme)
        XCTAssertTrue(generated.contains("[grid]"))
        XCTAssertTrue(generated.contains("[spaceNames.names]"))
        XCTAssertTrue(generated.contains("[appearance]"))
        XCTAssertTrue(generated.contains("[behavior.hotkey]"))
        XCTAssertTrue(generated.contains("[advanced]"))
        XCTAssertEqual(Config.load(from: path).cols, GridConfig.default.cols)
    }

    func testLoadRepairsFieldsAndPreservesValidValues() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-config-repair-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        Config.silentMode = true
        defer { Config.silentMode = false }

        let malformed = """
        [grid]
        cols = 5
        rows = "broken"

        [appearance]
        theme = "nord"
        """
        try malformed.write(toFile: path, atomically: true, encoding: .utf8)
        let repaired = Config.load(from: path)
        let healed = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertEqual(repaired.cols, 5)
        XCTAssertEqual(repaired.rows, GridConfig.default.rows)
        XCTAssertEqual(repaired.theme, "nord")
        XCTAssertEqual(try String(contentsOfFile: path + ".bak", encoding: .utf8), malformed)
        XCTAssertTrue(healed.contains("[grid]"))
        XCTAssertTrue(healed.contains("[behavior]"))
        XCTAssertEqual(Config.load(from: path).theme, "nord")
    }

    func testLoadReplacesInvalidTOMLWithDefaultsAndBacksItUp() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-config-invalid-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        Config.silentMode = true
        defer { Config.silentMode = false }

        let invalid = "[grid\ncols = 5"
        try invalid.write(toFile: path, atomically: true, encoding: .utf8)
        let repaired = Config.load(from: path)

        XCTAssertEqual(repaired.cols, GridConfig.default.cols)
        XCTAssertEqual(repaired.theme, GridConfig.default.theme)
        XCTAssertEqual(try String(contentsOfFile: path + ".bak", encoding: .utf8), invalid)
        XCTAssertTrue(try String(contentsOfFile: path, encoding: .utf8).contains("[grid]"))
    }

    func testJSONIsRejectedAndReplacedWithDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-config-json-rejection-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        Config.silentMode = true
        defer { Config.silentMode = false }

        let json = #"{"cols": 5}"#
        try json.write(toFile: path, atomically: true, encoding: .utf8)
        let loaded = Config.load(from: path)

        XCTAssertEqual(loaded.cols, GridConfig.default.cols)
        XCTAssertEqual(try String(contentsOfFile: path + ".bak", encoding: .utf8), json)
    }

    func testPlainConfigIsRejectedAndReplacedWithDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-config-plain-rejection-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        Config.silentMode = true
        defer { Config.silentMode = false }

        let plain = "GRID_COLS=5"
        try plain.write(toFile: path, atomically: true, encoding: .utf8)
        let loaded = Config.load(from: path)

        XCTAssertEqual(loaded.cols, GridConfig.default.cols)
        XCTAssertEqual(try String(contentsOfFile: path + ".bak", encoding: .utf8), plain)
    }

    func testJumpToSpaceEnabledDefaultsToFalse() {
        let configTrue = """
        [behavior]
        jumpToSpaceEnabled = true
        """
        let cTrue = Config.parseConfig(configTrue)
        XCTAssertTrue(cTrue.jumpToSpaceEnabled)

        let configMissing = "[behavior]\nautoHideTimeout = 5"
        let cMissing = Config.parseConfig(configMissing)
        XCTAssertFalse(cMissing.jumpToSpaceEnabled)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-config-jump-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config.toml").path
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        Config.saveConfig(cTrue, to: path)
        let reloaded = Config.load(from: path)
        XCTAssertTrue(reloaded.jumpToSpaceEnabled)
    }
}
