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
        values.jumpToSpaceEnabled = true
        values.hudPosition = .custom(x: 0.25, y: 0.75)
        values.customHUDX = 0.25
        values.customHUDY = 0.75
        values.hideMenuBarIcon = true
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
        XCTAssertEqual(config.menuBarNearbyCount, GridConfig.default.menuBarNearbyCount)
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
    }

    func testToGridConfigPreservesValidCustomValues() {
        var values = ConfigValues()
        values.cols = 10
        values.rows = 5
        values.cellStyle = .thumbnails
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
        values.menuBarDisplayMode = .dots
        values.menuBarNearbyCount = 7
        values.useVimKeys = true
        values.useArrowKeys = true
        values.jumpToSpaceEnabled = false
        values.hudPosition = .top
        values.showExtraWindows = true
        values.focusSpaceOnWindowDrop = .always
        values.focusSpaceOnWindowDropModifier = .shift
        values.showHUDOnSpaceChange = true
        values.updateMode = .auto

        let (config, needsRepair) = values.toGridConfig()

        XCTAssertFalse(needsRepair)
        XCTAssertEqual(config.cols, 10)
        XCTAssertEqual(config.rows, 5)
        XCTAssertEqual(config.cellStyle, .thumbnails)
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
        XCTAssertFalse(config.jumpToSpaceEnabled)
        XCTAssertEqual(config.hudPosition, .top)
        XCTAssertTrue(config.showExtraWindows)
        XCTAssertEqual(config.focusSpaceOnWindowDrop, .always)
        XCTAssertEqual(config.focusSpaceOnWindowDropModifier, .shift)
        XCTAssertTrue(config.showHUDOnSpaceChange)
        XCTAssertEqual(config.updateMode, .auto)
    }
}
