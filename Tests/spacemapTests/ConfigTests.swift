import XCTest
@testable import spacemap

final class ConfigTests: XCTestCase {

    // MARK: - parseConfig: Grid dimensions

    func testParseGridCols() {
        let c = ConfigReader.parseConfig("GRID_COLS=4")
        XCTAssertEqual(c.cols, 4)
    }

    func testParseGridRows() {
        let c = ConfigReader.parseConfig("GRID_ROWS=3")
        XCTAssertEqual(c.rows, 3)
    }

    func testParseGridDefaults() {
        let c = ConfigReader.parseConfig("")
        XCTAssertEqual(c.cols, GridConfig.default.cols)
        XCTAssertEqual(c.rows, GridConfig.default.rows)
    }

    // MARK: - parseConfig: Cell style

    func testParseCellStyleRects() {
        let c = ConfigReader.parseConfig("CELL_STYLE=rects")
        XCTAssertEqual(c.cellStyle, .rects)
    }

    func testParseCellStyleHybrid() {
        let c = ConfigReader.parseConfig("CELL_STYLE=hybrid")
        XCTAssertEqual(c.cellStyle, .hybrid)
    }

    func testParseCellStyleIcons() {
        let c = ConfigReader.parseConfig("CELL_STYLE=icons")
        XCTAssertEqual(c.cellStyle, .icons)
        XCTAssertTrue(c.showIconStrip)
    }

    func testParseCellStyleIconsOnly() {
        let c = ConfigReader.parseConfig("CELL_STYLE=icons-only")
        XCTAssertEqual(c.cellStyle, .icons)
        XCTAssertFalse(c.showIconStrip)
    }

    func testParseCellStyleThumbnails() {
        let c = ConfigReader.parseConfig("CELL_STYLE=thumbnails")
        XCTAssertEqual(c.cellStyle, .thumbnails)
    }

    func testParseCellStyleUnknownDefaultsToRects() {
        let c = ConfigReader.parseConfig("CELL_STYLE=invalid")
        XCTAssertEqual(c.cellStyle, .rects)
    }

    // MARK: - parseConfig: Boolean parsing

    func testBoolParsingTrue() {
        let c = ConfigReader.parseConfig("SHOW_SPACE_NUMBERS=true")
        XCTAssertTrue(c.showSpaceNumbers)
    }

    func testBoolParsingOne() {
        let c = ConfigReader.parseConfig("SHOW_SPACE_NUMBERS=1")
        XCTAssertTrue(c.showSpaceNumbers)
    }

    func testBoolParsingYes() {
        let c = ConfigReader.parseConfig("SHOW_SPACE_NUMBERS=yes")
        XCTAssertTrue(c.showSpaceNumbers)
    }

    func testBoolParsingOn() {
        let c = ConfigReader.parseConfig("SHOW_SPACE_NUMBERS=on")
        XCTAssertTrue(c.showSpaceNumbers)
    }

    func testBoolParsingOff() {
        let c = ConfigReader.parseConfig("SHOW_SPACE_NUMBERS=off")
        XCTAssertFalse(c.showSpaceNumbers)
    }

    func testBoolParsingFalse() {
        let c = ConfigReader.parseConfig("SHOW_SPACE_NUMBERS=false")
        XCTAssertFalse(c.showSpaceNumbers)
    }

    func testBoolParsingCaseInsensitive() {
        let c = ConfigReader.parseConfig("VIM_KEYS=True")
        XCTAssertTrue(c.useVimKeys)
    }

    // MARK: - parseConfig: All boolean keys

    func testShowSpaceNames() {
        let c = ConfigReader.parseConfig("SHOW_SPACE_NAMES=true")
        XCTAssertTrue(c.showSpaceNames)
    }

    func testShowIconStrip() {
        let c = ConfigReader.parseConfig("SHOW_ICON_STRIP=false")
        XCTAssertFalse(c.showIconStrip)
    }

    func testShowMultiAppIcons() {
        let c = ConfigReader.parseConfig("SHOW_MULTI_APP_ICONS=true")
        XCTAssertTrue(c.showMultiAppIcons)
    }

    func testHideMenuBarIcon() {
        let c = ConfigReader.parseConfig("HIDE_MENUBAR_ICON=true")
        XCTAssertTrue(c.hideMenuBarIcon)
    }

    func testVimKeys() {
        let c = ConfigReader.parseConfig("VIM_KEYS=true")
        XCTAssertTrue(c.useVimKeys)
    }

    func testArrowKeys() {
        let c = ConfigReader.parseConfig("ARROW_KEYS=true")
        XCTAssertTrue(c.useArrowKeys)
    }

    func testShowHUDOnSpaceChangeDefaultsOff() {
        XCTAssertFalse(ConfigReader.parseConfig("").showHUDOnSpaceChange)
    }

    func testShowHUDOnSpaceChange() {
        let c = ConfigReader.parseConfig("SHOW_HUD_ON_SPACE_CHANGE=on")
        XCTAssertTrue(c.showHUDOnSpaceChange)
    }

    // MARK: - parseConfig: Numeric values

    func testUIscale() {
        let c = ConfigReader.parseConfig("UI_SCALE=0.5")
        XCTAssertEqual(c.uiScale, 0.5, accuracy: 0.001)
    }

    func testUIscaleOutOfRangeDefaults() {
        let c = ConfigReader.parseConfig("UI_SCALE=5.0")
        XCTAssertEqual(c.uiScale, GridConfig.default.uiScale)
    }

    func testAutoHideTimeout() {
        let c = ConfigReader.parseConfig("AUTO_HIDE_TIMEOUT=10")
        XCTAssertEqual(c.autoHideTimeout, 10)
    }

    func testMaxSpaces() {
        let c = ConfigReader.parseConfig("MAX_SPACES=8")
        XCTAssertEqual(c.maxSpaces, 8)
    }

    func testMaxSpacesOutOfRangeDefaults() {
        let c = ConfigReader.parseConfig("MAX_SPACES=20")
        XCTAssertEqual(c.maxSpaces, GridConfig.default.maxSpaces)
    }

    func testBackgroundAlpha() {
        let c = ConfigReader.parseConfig("BACKGROUND_ALPHA=0.5")
        XCTAssertEqual(c.backgroundAlpha, 0.5, accuracy: 0.001)
    }

    func testIconScale() {
        let c = ConfigReader.parseConfig("ICON_SCALE=0.7")
        XCTAssertEqual(c.iconScale, 0.7, accuracy: 0.001)
    }

    func testIconScaleOutOfRangeDefaults() {
        let c = ConfigReader.parseConfig("ICON_SCALE=2.0")
        XCTAssertEqual(c.iconScale, GridConfig.default.iconScale)
    }

    // MARK: - parseConfig: String values

    func testTheme() {
        let c = ConfigReader.parseConfig("THEME=catppuccin")
        XCTAssertEqual(c.theme, "catppuccin")
    }

    func testShowModeActive() {
        let c = ConfigReader.parseConfig("SHOW_MODE=active")
        XCTAssertEqual(c.showMode, .active)
    }

    func testShowModeAll() {
        let c = ConfigReader.parseConfig("SHOW_MODE=all")
        XCTAssertEqual(c.showMode, .all)
    }

    func testMultiMonitorHUDModeDefaultsToUnified() {
        XCTAssertEqual(ConfigReader.parseConfig("").multiMonitorHUDMode, .unified)
    }

    func testMultiMonitorHUDModeParsesSeparate() {
        XCTAssertEqual(
            ConfigReader.parseConfig("MULTI_MONITOR_HUD_MODE=separate").multiMonitorHUDMode,
            .separate
        )
    }

    func testUnifiedHUDVisibilityDefaultsToActive() {
        XCTAssertEqual(ConfigReader.parseConfig("").unifiedHUDVisibility, .active)
    }

    func testUnifiedHUDVisibilityParsesAll() {
        XCTAssertEqual(
            ConfigReader.parseConfig("UNIFIED_HUD_VISIBILITY=all").unifiedHUDVisibility,
            .all
        )
    }

    func testSeparateHUDVisibilityDefaultsToAll() {
        XCTAssertEqual(ConfigReader.parseConfig("").separateHUDVisibility, .all)
    }

    func testSeparateHUDVisibilityParsesActive() {
        XCTAssertEqual(
            ConfigReader.parseConfig("SEPARATE_HUD_VISIBILITY=active").separateHUDVisibility,
            .active
        )
    }

    func testDisplayNavigationWrapDefaultsToWithin() {
        XCTAssertEqual(ConfigReader.parseConfig("").displayNavigationWrap, .within)
    }

    func testDisplayNavigationWrapParsesBetween() {
        XCTAssertEqual(
            ConfigReader.parseConfig("DISPLAY_NAVIGATION_WRAP=between").displayNavigationWrap,
            .between
        )
    }

    func testModeLight() {
        let c = ConfigReader.parseConfig("MODE=light")
        XCTAssertEqual(c.mode, .light)
    }

    func testModeDark() {
        let c = ConfigReader.parseConfig("MODE=dark")
        XCTAssertEqual(c.mode, .dark)
    }

    func testModeAuto() {
        let c = ConfigReader.parseConfig("MODE=auto")
        XCTAssertEqual(c.mode, .auto)
    }

    // MARK: - parseConfig: Hotkey

    func testHotkeyParsing() {
        let c = ConfigReader.parseConfig("HOTKEY=cmd+shift+f3")
        XCTAssertEqual(c.hotkey.keyCode, 99)
        XCTAssertTrue(c.hotkey.modifiers.contains(.maskCommand))
        XCTAssertTrue(c.hotkey.modifiers.contains(.maskShift))
    }

    func testPinnedHotkeyParsing() {
        let c = ConfigReader.parseConfig("PINNED_HOTKEY=ctrl+alt+f13")
        XCTAssertEqual(c.pinnedHotkey.keyCode, 105)
        XCTAssertTrue(c.pinnedHotkey.modifiers.contains(.maskControl))
        XCTAssertTrue(c.pinnedHotkey.modifiers.contains(.maskAlternate))
    }

    // MARK: - parseConfig: Space names

    func testSpaceNames() {
        let c = ConfigReader.parseConfig("SPACE_NAMES=1:Term,2:Code,5:Browser")
        XCTAssertEqual(c.spaceNames[1], "Term")
        XCTAssertEqual(c.spaceNames[2], "Code")
        XCTAssertEqual(c.spaceNames[5], "Browser")
        XCTAssertNil(c.spaceNames[3])
    }

    func testSpaceNamesWithSpaces() {
        let c = ConfigReader.parseConfig("SPACE_NAMES=1:My Terminal,2:My Code")
        XCTAssertEqual(c.spaceNames[1], "My Terminal")
        XCTAssertEqual(c.spaceNames[2], "My Code")
    }

    // MARK: - parseConfig: Comments and whitespace

    func testCommentsIgnored() {
        let config = """
        # This is a comment
        GRID_COLS=4
        # Another comment
        GRID_ROWS=3
        """
        let c = ConfigReader.parseConfig(config)
        XCTAssertEqual(c.cols, 4)
        XCTAssertEqual(c.rows, 3)
    }

    func testInlineComments() {
        let c = ConfigReader.parseConfig("GRID_COLS=6 # number of columns")
        XCTAssertEqual(c.cols, 6)
    }

    func testWhitespaceTrimmed() {
        let c = ConfigReader.parseConfig("  GRID_COLS  =  5  ")
        XCTAssertEqual(c.cols, 5)
    }

    func testEmptyLinesIgnored() {
        let config = """

        GRID_COLS=3

        GRID_ROWS=4

        """
        let c = ConfigReader.parseConfig(config)
        XCTAssertEqual(c.cols, 3)
        XCTAssertEqual(c.rows, 4)
    }

    // MARK: - parseConfig: Multi-line integration

    func testFullConfig() {
        let config = """
        GRID_COLS=6
        GRID_ROWS=3
        CELL_STYLE=icons
        HOTKEY=cmd+shift+space
        UI_SCALE=0.75
        THEME=dracula
        SHOW_MODE=active
        MODE=dark
        VIM_KEYS=true
        ARROW_KEYS=true
        SPACE_NAMES=1:Term,2:Code
        """
        let c = ConfigReader.parseConfig(config)
        XCTAssertEqual(c.cols, 6)
        XCTAssertEqual(c.rows, 3)
        XCTAssertEqual(c.cellStyle, .icons)
        XCTAssertEqual(c.hotkey.keyCode, 49)
        XCTAssertTrue(c.hotkey.modifiers.contains(.maskCommand))
        XCTAssertTrue(c.hotkey.modifiers.contains(.maskShift))
        XCTAssertEqual(c.uiScale, 0.75, accuracy: 0.001)
        XCTAssertEqual(c.theme, "dracula")
        XCTAssertEqual(c.showMode, .active)
        XCTAssertEqual(c.mode, .dark)
        XCTAssertTrue(c.useVimKeys)
        XCTAssertTrue(c.useArrowKeys)
        XCTAssertEqual(c.spaceNames[1], "Term")
        XCTAssertEqual(c.spaceNames[2], "Code")
    }

    func testJSONConfig() {
        let config = """
        {
          "cols": 6,
          "rows": 3,
          "cellStyle": "icons",
          "hotkey": {
            "keyCode": 49,
            "modifiers": ["cmd", "shift"]
          },
          "pinnedHotkey": {
            "keyKind": "mediaKey",
            "mediaKey": "play-pause",
            "modifiers": ["ctrl"]
          },
          "socketHealthInterval": 30,
          "uiScale": 0.75,
          "autoHideTimeout": 10,
          "theme": "dracula",
          "showMode": "active",
          "multiMonitorHUDMode": "separate",
          "unifiedHUDVisibility": "all",
          "separateHUDVisibility": "active",
          "displayNavigationWrap": "between",
          "maxSpaces": 12,
          "backgroundAlpha": 0.5,
          "mode": "dark",
          "iconScale": 0.8,
          "showSpaceNumbers": false,
          "showSpaceNames": true,
          "showIconStrip": false,
          "showMultiAppIcons": true,
          "hideMenuBarIcon": true,
          "spaceNames": { "1": "Term", "2": "Code" },
          "useVimKeys": true,
          "useArrowKeys": true,
          "hudPosition": { "kind": "custom", "x": 0.25, "y": 0.75 },
          "customHUDX": 0.25,
          "customHUDY": 0.75,
          "showExtraWindows": true,
          "focusSpaceOnWindowDrop": true,
          "showHUDOnSpaceChange": true,
          "updateMode": "off"
        }
        """
        let c = ConfigReader.parseConfig(config)
        XCTAssertEqual(c.cols, 6)
        XCTAssertEqual(c.rows, 3)
        XCTAssertEqual(c.cellStyle, .icons)
        XCTAssertEqual(c.hotkey.keyCode, 49)
        XCTAssertTrue(c.hotkey.modifiers.contains(.maskCommand))
        XCTAssertTrue(c.hotkey.modifiers.contains(.maskShift))
        XCTAssertEqual(c.pinnedHotkey.mediaKey, .playPause)
        XCTAssertTrue(c.pinnedHotkey.modifiers.contains(.maskControl))
        XCTAssertEqual(c.socketHealthInterval, 30)
        XCTAssertEqual(c.uiScale, 0.75, accuracy: 0.001)
        XCTAssertEqual(c.autoHideTimeout, 10)
        XCTAssertEqual(c.theme, "dracula")
        XCTAssertEqual(c.showMode, .active)
        XCTAssertEqual(c.multiMonitorHUDMode, .separate)
        XCTAssertEqual(c.unifiedHUDVisibility, .all)
        XCTAssertEqual(c.separateHUDVisibility, .active)
        XCTAssertEqual(c.displayNavigationWrap, .between)
        XCTAssertEqual(c.maxSpaces, 12)
        XCTAssertEqual(c.backgroundAlpha, 0.5, accuracy: 0.001)
        XCTAssertEqual(c.mode, .dark)
        XCTAssertEqual(c.iconScale, 0.8, accuracy: 0.001)
        XCTAssertFalse(c.showSpaceNumbers)
        XCTAssertTrue(c.showSpaceNames)
        XCTAssertFalse(c.showIconStrip)
        XCTAssertTrue(c.showMultiAppIcons)
        XCTAssertTrue(c.hideMenuBarIcon)
        XCTAssertEqual(c.spaceNames[1], "Term")
        XCTAssertEqual(c.spaceNames[2], "Code")
        XCTAssertTrue(c.useVimKeys)
        XCTAssertTrue(c.useArrowKeys)
        if case .custom(let x, let y) = c.hudPosition {
            XCTAssertEqual(x, 0.25, accuracy: 0.001)
            XCTAssertEqual(y, 0.75, accuracy: 0.001)
        } else {
            XCTFail("Expected custom HUD position")
        }
        XCTAssertEqual(c.customHUDX, 0.25, accuracy: 0.001)
        XCTAssertEqual(c.customHUDY, 0.75, accuracy: 0.001)
        XCTAssertTrue(c.showExtraWindows)
        XCTAssertTrue(c.focusSpaceOnWindowDrop)
        XCTAssertTrue(c.showHUDOnSpaceChange)
        XCTAssertEqual(c.updateMode, .off)
    }

    func testJSONCConfig() {
        let config = """
        // comment
        {
          /* block */
          "cols": 4,
          "rows": 2,
          "cellStyle": "rects",
          "hotkey": {
            "keyCode": 121,
            "modifiers": ["ctrl"]
          },
          "socketHealthInterval": 60,
          "uiScale": 0.5,
          "autoHideTimeout": 5,
          "theme": "default",
          "showMode": "all",
          "multiMonitorHUDMode": "unified",
          "unifiedHUDVisibility": "active",
          "separateHUDVisibility": "all",
          "displayNavigationWrap": "within",
          "maxSpaces": 16,
          "backgroundAlpha": 0.3,
          "mode": "auto",
          "iconScale": 0.5,
          "showSpaceNumbers": true,
          "showSpaceNames": true,
          "showIconStrip": true,
          "showMultiAppIcons": false,
          "hideMenuBarIcon": false,
          "spaceNames": {},
          "useVimKeys": false,
          "useArrowKeys": false,
          "hudPosition": { "kind": "center" },
          "customHUDX": 0.5,
          "customHUDY": 0.5,
          "showExtraWindows": false,
          "updateMode": "notify"
        }
        """
        let c = ConfigReader.parseConfig(config)
        XCTAssertEqual(c.cols, 4)
        XCTAssertEqual(c.rows, 2)
        XCTAssertEqual(c.hotkey.keyCode, 121)
        XCTAssertTrue(c.hotkey.modifiers.contains(.maskControl))
        XCTAssertFalse(c.focusSpaceOnWindowDrop)
        XCTAssertFalse(c.showHUDOnSpaceChange)
    }

    func testPartialJSONPreservesValidFieldsAndDefaultsInvalidFields() {
        let c = ConfigReader.parseConfig("""
        {
          "cols": 5,
          "rows": "invalid",
          "theme": "dracula",
          "maxSpaces": 99
        }
        """)

        XCTAssertEqual(c.cols, 5)
        XCTAssertEqual(c.rows, GridConfig.default.rows)
        XCTAssertEqual(c.theme, "dracula")
        XCTAssertEqual(c.maxSpaces, GridConfig.default.maxSpaces)
        XCTAssertFalse(c.focusSpaceOnWindowDrop)
    }

    func testLoadRepairsMalformedConfigOnEveryLoadAndCreatesBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-config-tests-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("config").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        ConfigReader.silentMode = true
        defer { ConfigReader.silentMode = false }

        try #"{"cols": 4}"#.write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(ConfigReader.load(from: path).cols, 4)

        let secondMalformedConfig = #"{"theme":"nord","rows":"broken"}"#
        try secondMalformedConfig.write(toFile: path, atomically: true, encoding: .utf8)
        let repaired = ConfigReader.load(from: path)

        XCTAssertEqual(repaired.theme, "nord")
        XCTAssertEqual(repaired.rows, GridConfig.default.rows)
        XCTAssertEqual(try String(contentsOfFile: path + ".bak", encoding: .utf8), secondMalformedConfig)

        let healedText = try String(contentsOfFile: path, encoding: .utf8)
        let healed = ConfigReader.parseConfig(healedText)
        XCTAssertEqual(healed.theme, "nord")
        XCTAssertEqual(healed.rows, GridConfig.default.rows)
    }

    func testLegacyConfigMigratesToCanonicalJSONCPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-config-migration-\(UUID().uuidString)")
        let legacyPath = directory.appendingPathComponent("config").path
        let canonicalPath = directory.appendingPathComponent("spacemap.jsonc").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try "GRID_COLS=5".write(toFile: legacyPath, atomically: true, encoding: .utf8)
        ConfigReader.migrateLegacyConfigIfNeeded(from: legacyPath, to: canonicalPath)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: canonicalPath))
        XCTAssertEqual(ConfigReader.load(from: canonicalPath).cols, 5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: canonicalPath + ".bak"))
    }

    func testCanonicalConfigWinsWhenLegacyConfigAlsoExists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-config-precedence-\(UUID().uuidString)")
        let legacyPath = directory.appendingPathComponent("config").path
        let canonicalPath = directory.appendingPathComponent("spacemap.jsonc").path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try "GRID_COLS=3".write(toFile: legacyPath, atomically: true, encoding: .utf8)
        try "GRID_COLS=7".write(toFile: canonicalPath, atomically: true, encoding: .utf8)
        ConfigReader.migrateLegacyConfigIfNeeded(from: legacyPath, to: canonicalPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyPath))
        XCTAssertEqual(ConfigReader.load(from: canonicalPath).cols, 7)
    }

    func testLegacyFocusSpaceOnWindowDrop() {
        let c = ConfigReader.parseConfig("FOCUS_SPACE_ON_WINDOW_DROP=on")
        XCTAssertTrue(c.focusSpaceOnWindowDrop)
    }

    // MARK: - parseConfig: Backward compat

    func testShowNamesBackwardCompat() {
        let c = ConfigReader.parseConfig("SHOW_NAMES=true")
        XCTAssertTrue(c.showSpaceNumbers)
    }

    // MARK: - parseConfig: HUD_POSITION

    func testParseHudPositionCenter() {
        let c = ConfigReader.parseConfig("HUD_POSITION=center")
        XCTAssertEqual(c.hudPosition, .center)
    }

    func testParseHudPositionTop() {
        let c = ConfigReader.parseConfig("HUD_POSITION=top")
        XCTAssertEqual(c.hudPosition, .top)
    }

    func testParseHudPositionBottom() {
        let c = ConfigReader.parseConfig("HUD_POSITION=bottom")
        XCTAssertEqual(c.hudPosition, .bottom)
    }

    func testParseHudPositionCustom() {
        let c = ConfigReader.parseConfig("HUD_POSITION=0.3,0.7")
        XCTAssertEqual(c.hudPosition, .custom(x: 0.3, y: 0.7))
    }

    func testParseHudPositionDefault() {
        let c = ConfigReader.parseConfig("")
        XCTAssertEqual(c.hudPosition, .center)
    }

    func testParseHudPositionInvalidCustom() {
        let c = ConfigReader.parseConfig("HUD_POSITION=2.0,0.5")
        XCTAssertEqual(c.hudPosition, .center)
    }

    func testHudPositionStringRoundtrip() {
        let presets: [HUDPosition] = [.center, .top, .bottom]
        for pos in presets {
            let str = ConfigReader.hudPositionString(pos)
            let c = ConfigReader.parseConfig("HUD_POSITION=\(str)")
            XCTAssertEqual(c.hudPosition, pos)
        }
    }

    func testHudPositionCustomUsesCustomXY() {
        let c = ConfigReader.parseConfig("""
            HUD_POSITION=custom
            CUSTOM_HUD_X=0.25
            CUSTOM_HUD_Y=0.75
            """)
        if case .custom(let x, let y) = c.hudPosition {
            XCTAssertEqual(x, 0.25, accuracy: 0.001)
            XCTAssertEqual(y, 0.75, accuracy: 0.001)
        } else {
            XCTFail("Expected .custom, got \(c.hudPosition)")
        }
    }
}
