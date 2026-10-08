import XCTest
@testable import spacemap

final class ConfigValuesTests: XCTestCase {

    func testToGridConfigWithAllFieldsSet() {
        var values = ConfigValues()
        values.cols = 6
        values.rows = 3
        values.cellStyle = .icons
        values.theme = "dracula"
        values.mode = .dark
        values.showMode = .active
        values.hotkey = HotkeyConfig(key: .keyCode(49), modifiers: .maskCommand)
        values.pinnedHotkey = HotkeyConfig(key: .none, modifiers: [])
        values.glyphStripHotkey = HotkeyConfig(key: .keyCode(100), modifiers: .maskShift)
        values.maxSpaces = 12
        values.backgroundAlpha = 0.5
        values.hudShadow = false
        values.iconScale = 0.8
        values.uiScale = 0.75
        values.autoHideTimeout = 10
        values.socketHealthInterval = 30
        values.showExtraWindows = true
        values.showSpaceNumbers = false
        values.showIconStrip = false
        values.showMultiAppIcons = true
        values.showSpaceNames = true
        values.spaceNames = [1: "Term", 2: "Code"]
        values.useVimKeys = true
        values.useArrowKeys = true
        values.useExtendedKeys = true
        values.jumpToSpaceEnabled = true
        values.hudPosition = .custom(x: 0.25, y: 0.75)
        values.customHUDX = 0.25
        values.customHUDY = 0.75
        values.hideMenuBarIcon = true
        values.glyphStrip = GlyphStripConfig(enabled: true)
        values.menuBarDisplayMode = .nearby
        values.menuBarNearbyCount = 5
        values.displayNavigationWrap = .between
        values.unifiedHUDVisibility = .all
        values.separateHUDVisibility = .active
        values.multiMonitorHUDMode = .separate
        values.focusSpaceOnWindowDrop = .modifier
        values.focusSpaceOnWindowDropModifier = .option
        values.showHUDOnSpaceChange = true
        values.updateMode = .off
        values.appFont = AppFontConfig(updateMode: .auto, installedVersion: "v3.0.5", lastCheck: 1700000000)

        let (config, needsRepair) = values.toGridConfig()

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config.cols, 6)
        XCTAssertEqual(config.rows, 3)
        XCTAssertEqual(config.cellStyle, .icons)
        XCTAssertEqual(config.theme, "dracula")
        XCTAssertEqual(config.mode, .dark)
        XCTAssertEqual(config.showMode, .active)
        XCTAssertEqual(config.hotkey.keyCode, 49)
        XCTAssertTrue(config.hotkey.modifiers.contains(.maskCommand))
        XCTAssertEqual(config.pinnedHotkey.key, .none)
        XCTAssertEqual(config.glyphStripHotkey, HotkeyConfig(key: .keyCode(100), modifiers: .maskShift))
        XCTAssertEqual(config.maxSpaces, 12)
        XCTAssertEqual(config.backgroundAlpha, 0.5, accuracy: 0.001)
        XCTAssertFalse(config.hudShadow)
        XCTAssertEqual(config.iconScale, 0.8, accuracy: 0.001)
        XCTAssertEqual(config.uiScale, 0.75, accuracy: 0.001)
        XCTAssertEqual(config.autoHideTimeout, 10)
        XCTAssertEqual(config.socketHealthInterval, 30)
        XCTAssertTrue(config.showExtraWindows)
        XCTAssertFalse(config.showSpaceNumbers)
        XCTAssertFalse(config.showIconStrip)
        XCTAssertTrue(config.showMultiAppIcons)
        XCTAssertTrue(config.showSpaceNames)
        XCTAssertEqual(config.spaceNames, [1: "Term", 2: "Code"])
        XCTAssertTrue(config.useVimKeys)
        XCTAssertTrue(config.useArrowKeys)
        XCTAssertTrue(config.useExtendedKeys)
        XCTAssertTrue(config.jumpToSpaceEnabled)
        XCTAssertEqual(config.hudPosition, .custom(x: 0.25, y: 0.75))
        XCTAssertEqual(config.customHUDX, 0.25, accuracy: 0.001)
        XCTAssertEqual(config.customHUDY, 0.75, accuracy: 0.001)
        XCTAssertTrue(config.hideMenuBarIcon)
        XCTAssertEqual(config.menuBarDisplayMode, .nearby)
        XCTAssertEqual(config.menuBarNearbyCount, 5)
        XCTAssertEqual(config.displayNavigationWrap, .between)
        XCTAssertEqual(config.unifiedHUDVisibility, .all)
        XCTAssertEqual(config.separateHUDVisibility, .active)
        XCTAssertEqual(config.multiMonitorHUDMode, .separate)
        XCTAssertEqual(config.focusSpaceOnWindowDrop, .modifier)
        XCTAssertEqual(config.focusSpaceOnWindowDropModifier, .option)
        XCTAssertTrue(config.showHUDOnSpaceChange)
        XCTAssertEqual(config.updateMode, .off)
        XCTAssertTrue(config.glyphStrip.enabled)
        XCTAssertEqual(config.appFont.updateMode, .auto)
        XCTAssertEqual(config.appFont.installedVersion, "v3.0.5")
        XCTAssertEqual(config.appFont.lastCheck, 1700000000)
    }

    func testToGridConfigWithFullGlyphStripTable() {
        var values = ConfigValues()
        // Mirror testToGridConfigWithAllFieldsSet: nothing may be nil or the
        // repair flag trips.
        values.cols = 8
        values.rows = 2
        values.cellStyle = .rects
        values.hotkey = .default
        values.pinnedHotkey = HotkeyConfig(key: .none, modifiers: [])
        values.glyphStripHotkey = HotkeyConfig(key: .none, modifiers: [])
        values.socketHealthInterval = 60
        values.uiScale = 0.5
        values.autoHideTimeout = 5
        values.theme = "default"
        values.showMode = .all
        values.multiMonitorHUDMode = .unified
        values.unifiedHUDVisibility = .active
        values.separateHUDVisibility = .all
        values.displayNavigationWrap = .within
        values.maxSpaces = 16
        values.backgroundAlpha = 0.3
        values.hudShadow = true
        values.mode = .auto
        values.iconScale = 0.5
        values.showSpaceNumbers = true
        values.showSpaceNames = true
        values.showIconStrip = true
        values.showMultiAppIcons = false
        values.hideMenuBarIcon = false
        values.menuBarDisplayMode = .icon
        values.menuBarNearbyCount = 3
        values.spaceNames = [:]
        values.useVimKeys = false
        values.useArrowKeys = false
        values.useExtendedKeys = true
        values.jumpToSpaceEnabled = false
        values.hudPosition = .center
        values.customHUDX = 0.5
        values.customHUDY = 0.5
        values.showExtraWindows = false
        values.focusSpaceOnWindowDrop = .never
        values.focusSpaceOnWindowDropModifier = .command
        values.showHUDOnSpaceChange = false
        values.updateMode = .notify
        values.appFont = .default

        var strip = GlyphStripConfig.default
        strip.enabled = true
        strip.showSpaceNumbers = false
        strip.showLayoutSuffix = false
        strip.showAppIcons = false
        strip.dedupeAppsPerSpace = false
        strip.maxIconsPerSpace = 4
        strip.iconSize = 14
        strip.indexSize = 9
        strip.highlightCurrentSpace = false
        strip.backgroundMaterial = .liquidGlass
        strip.shape = .pill
        strip.backgroundOpacity = 0.5
        strip.cornerRadius = 6
        strip.showDisplaySeparators = false
        strip.showAddSpaceButton = false
        strip.showPlaceholders = false
        strip.leftClickAction = .toggleFullscreen
        strip.rightClickAction = .none
        strip.middleClickAction = .balanceWindows
        strip.position = .center
        values.glyphStrip = strip

        let (config, needsRepair) = values.toGridConfig()

        XCTAssertFalse(needsRepair)
        // No colour resolution pass any more: the strip's palette is fixed by
        // theme roles at draw time, so every key survives untouched.
        XCTAssertEqual(config.glyphStrip, strip)
    }

    func testNewMaterialAndShapeKeysRoundTripThroughTheConfigString() throws {
        var values = ConfigValues()
        var strip = GlyphStripConfig.default
        strip.backgroundMaterial = .liquidGlass
        strip.shape = .bar
        values.glyphStrip = strip

        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = try TOMLParser.parse(toml)

        XCTAssertEqual(reread.glyphStrip?.backgroundMaterial, .liquidGlass)
        XCTAssertEqual(reread.glyphStrip?.shape, .bar)
    }

    func testToGridConfigClampsGlyphStripNumbersAndFlagsRepair() {
        var values = ConfigValues()
        var strip = GlyphStripConfig.default
        strip.iconSize = 100
        strip.backgroundOpacity = -2
        strip.maxIconsPerSpace = -1
        values.glyphStrip = strip

        let (config, needsRepair) = values.toGridConfig()

        XCTAssertTrue(needsRepair, "every other key is nil here too")
        XCTAssertEqual(config.glyphStrip.iconSize, 24)
        XCTAssertEqual(config.glyphStrip.backgroundOpacity, 0.01)
        XCTAssertEqual(config.glyphStrip.maxIconsPerSpace, 0)
    }

    func testToGridConfigWithMissingFieldsUsesDefaults() {
        var values = ConfigValues()
        values.cols = 5
        values.rows = nil
        values.cellStyle = nil
        values.theme = nil
        let (config, needsRepair) = values.toGridConfig()

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.cols, 5)
        XCTAssertEqual(config.rows, GridConfig.default.rows)
        XCTAssertEqual(config.cellStyle, GridConfig.default.cellStyle)
        XCTAssertEqual(config.theme, GridConfig.default.theme)
    }

    func testToGridConfigClampsInvalidValuesToDefaults() {
        var values = ConfigValues()
        values.cols = 0
        values.rows = -1
        values.maxSpaces = 99
        values.backgroundAlpha = 2.0
        values.iconScale = -1.0
        values.uiScale = 5.0
        values.autoHideTimeout = -1
        values.menuBarNearbyCount = 99

        let (config, needsRepair) = values.toGridConfig()

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.cols, GridConfig.default.cols)
        XCTAssertEqual(config.rows, GridConfig.default.rows)
        XCTAssertEqual(config.maxSpaces, GridConfig.default.maxSpaces)
        XCTAssertEqual(config.backgroundAlpha, GridConfig.default.backgroundAlpha)
        XCTAssertEqual(config.iconScale, GridConfig.default.iconScale)
        XCTAssertEqual(config.uiScale, GridConfig.default.uiScale)
        XCTAssertEqual(config.autoHideTimeout, GridConfig.default.autoHideTimeout)
        XCTAssertEqual(config.menuBarNearbyCount, 16)
    }

    func testToGridConfigWithEmptyConfigReturnsDefaults() {
        let values = ConfigValues()
        let (config, needsRepair) = values.toGridConfig()

        XCTAssertTrue(needsRepair)
        XCTAssertEqual(config.cols, GridConfig.default.cols)
        XCTAssertEqual(config.rows, GridConfig.default.rows)
        XCTAssertEqual(config.cellStyle, GridConfig.default.cellStyle)
        XCTAssertEqual(config.theme, GridConfig.default.theme)
        XCTAssertEqual(config.showMode, GridConfig.default.showMode)
        XCTAssertEqual(config.hotkey.keyCode, GridConfig.default.hotkey.keyCode)
        XCTAssertEqual(config.glyphStripHotkey, GridConfig.default.glyphStripHotkey,
                       "old configs without the key load with the strip hotkey unbound")
    }

    func testUseExtendedKeysRoundTripsAndDefaultsTrueWhenMissing() throws {
        var values = ConfigValues()
        values.useExtendedKeys = false

        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = try TOMLParser.parse(toml)

        XCTAssertEqual(reread.useExtendedKeys, false)

        let defaults = ConfigValues()
        let (config, needsRepair) = defaults.toGridConfig()

        XCTAssertTrue(config.useExtendedKeys, "old configs without the key load with extended keys enabled")
        XCTAssertTrue(needsRepair, "the nil key should flag repair so the file is rewritten, like its siblings")
    }

    func testGlyphStripHotkeyRoundTripsThroughTheConfigString() throws {
        var values = ConfigValues()
        values.glyphStripHotkey = HotkeyConfig(key: .keyCode(100), modifiers: [.maskCommand, .maskShift])

        let toml = ConfigLoader.tomlConfigString(from: values, includeHeaderComments: false)
        let reread = try TOMLParser.parse(toml)

        XCTAssertEqual(reread.glyphStripHotkey, values.glyphStripHotkey)
    }

    func testToGridConfigPreservesValidCustomValues() {
        var values = ConfigValues()
        values.cols = 10
        values.rows = 5
        values.cellStyle = .thumbnails
        values.hotkey = .default
        values.pinnedHotkey = HotkeyConfig(key: .none, modifiers: [])
        values.glyphStripHotkey = HotkeyConfig(key: .keyCode(100), modifiers: .maskShift)
        values.socketHealthInterval = 37
        values.uiScale = 0.37
        values.autoHideTimeout = 7
        values.theme = "nord"
        values.mode = .light
        values.showMode = .all
        values.multiMonitorHUDMode = .unified
        values.unifiedHUDVisibility = .active
        values.separateHUDVisibility = .all
        values.displayNavigationWrap = .within
        values.maxSpaces = 8
        values.backgroundAlpha = 0.7
        values.hudShadow = true
        values.iconScale = 0.6
        values.showSpaceNumbers = true
        values.showSpaceNames = false
        values.showIconStrip = true
        values.showMultiAppIcons = false
        values.hideMenuBarIcon = false
        values.glyphStrip = GlyphStripConfig.default
        values.menuBarDisplayMode = .dots
        values.menuBarNearbyCount = 7
        values.useVimKeys = true
        values.useArrowKeys = true
        values.useExtendedKeys = true
        values.jumpToSpaceEnabled = false
        values.hudPosition = .top
        values.customHUDX = 0.42
        values.customHUDY = 0.58
        values.showExtraWindows = true
        values.focusSpaceOnWindowDrop = .always
        values.focusSpaceOnWindowDropModifier = .shift
        values.showHUDOnSpaceChange = true
        values.updateMode = .auto
        values.appFont = .default

        let (config, needsRepair) = values.toGridConfig()

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config.cols, 10)
        XCTAssertEqual(config.rows, 5)
        XCTAssertEqual(config.cellStyle, .thumbnails)
        XCTAssertEqual(config.socketHealthInterval, 37)
        XCTAssertEqual(config.uiScale, 0.37, accuracy: 0.001)
        XCTAssertEqual(config.autoHideTimeout, 7)
        XCTAssertEqual(config.theme, "nord")
        XCTAssertEqual(config.mode, .light)
        XCTAssertEqual(config.showMode, .all)
        XCTAssertEqual(config.multiMonitorHUDMode, .unified)
        XCTAssertEqual(config.unifiedHUDVisibility, .active)
        XCTAssertEqual(config.separateHUDVisibility, .all)
        XCTAssertEqual(config.displayNavigationWrap, .within)
        XCTAssertEqual(config.maxSpaces, 8)
        XCTAssertEqual(config.backgroundAlpha, 0.7, accuracy: 0.001)
        XCTAssertTrue(config.hudShadow)
        XCTAssertEqual(config.iconScale, 0.6, accuracy: 0.001)
        XCTAssertTrue(config.showSpaceNumbers)
        XCTAssertFalse(config.showSpaceNames)
        XCTAssertTrue(config.showIconStrip)
        XCTAssertFalse(config.showMultiAppIcons)
        XCTAssertFalse(config.hideMenuBarIcon)
        XCTAssertEqual(config.menuBarDisplayMode, .dots)
        XCTAssertEqual(config.menuBarNearbyCount, 7)
        XCTAssertTrue(config.useVimKeys)
        XCTAssertTrue(config.useArrowKeys)
        XCTAssertTrue(config.useExtendedKeys)
        XCTAssertFalse(config.jumpToSpaceEnabled)
        XCTAssertEqual(config.hudPosition, .top)
        XCTAssertEqual(config.customHUDX, 0.42, accuracy: 0.001)
        XCTAssertEqual(config.customHUDY, 0.58, accuracy: 0.001)
        XCTAssertTrue(config.showExtraWindows)
        XCTAssertEqual(config.focusSpaceOnWindowDrop, .always)
        XCTAssertEqual(config.focusSpaceOnWindowDropModifier, .shift)
        XCTAssertTrue(config.showHUDOnSpaceChange)
        XCTAssertEqual(config.updateMode, .auto)
    }
}
