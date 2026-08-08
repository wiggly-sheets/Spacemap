import XCTest
@testable import spacemap

final class ConfigClerkTests: XCTestCase {

    // MARK: - load(from:) and buildGridConfig() round-trip

    func testLoadAndBuildRoundTrip() {
        let clerk = ConfigClerk()
        let config = GridConfig.default
        clerk.load(from: config)
        let rebuilt = clerk.buildGridConfig()

        XCTAssertEqual(rebuilt.cols, config.cols)
        XCTAssertEqual(rebuilt.rows, config.rows)
        XCTAssertEqual(rebuilt.cellStyle, config.cellStyle)
        XCTAssertEqual(rebuilt.theme, config.theme)
        XCTAssertEqual(rebuilt.showMode, config.showMode)
        XCTAssertEqual(rebuilt.multiMonitorHUDMode, config.multiMonitorHUDMode)
        XCTAssertEqual(rebuilt.unifiedHUDVisibility, config.unifiedHUDVisibility)
        XCTAssertEqual(rebuilt.separateHUDVisibility, config.separateHUDVisibility)
        XCTAssertEqual(rebuilt.displayNavigationWrap, config.displayNavigationWrap)
        XCTAssertEqual(rebuilt.maxSpaces, config.maxSpaces)
        XCTAssertEqual(rebuilt.backgroundAlpha, config.backgroundAlpha)
        XCTAssertEqual(rebuilt.mode, config.mode)
        XCTAssertEqual(rebuilt.iconScale, config.iconScale)
        XCTAssertEqual(rebuilt.showSpaceNumbers, config.showSpaceNumbers)
        XCTAssertEqual(rebuilt.showSpaceNames, config.showSpaceNames)
        XCTAssertEqual(rebuilt.showIconStrip, config.showIconStrip)
        XCTAssertEqual(rebuilt.showMultiAppIcons, config.showMultiAppIcons)
        XCTAssertEqual(rebuilt.hideMenuBarIcon, config.hideMenuBarIcon)
        XCTAssertEqual(rebuilt.menuBarDisplayMode, config.menuBarDisplayMode)
        XCTAssertEqual(rebuilt.menuBarNearbyCount, config.menuBarNearbyCount)
        XCTAssertEqual(rebuilt.useVimKeys, config.useVimKeys)
        XCTAssertEqual(rebuilt.useArrowKeys, config.useArrowKeys)
        XCTAssertEqual(rebuilt.hudPosition, config.hudPosition)
        XCTAssertEqual(rebuilt.showExtraWindows, config.showExtraWindows)
        XCTAssertEqual(rebuilt.focusSpaceOnWindowDrop, config.focusSpaceOnWindowDrop)
        XCTAssertEqual(rebuilt.focusSpaceOnWindowDropModifier, config.focusSpaceOnWindowDropModifier)
        XCTAssertEqual(rebuilt.showHUDOnSpaceChange, config.showHUDOnSpaceChange)
        XCTAssertEqual(rebuilt.updateMode, config.updateMode)
    }

    // MARK: - load(from:) with custom values

    func testLoadPreservesCustomValues() {
        let clerk = ConfigClerk()
        var config = GridConfig.default
        config.cols = 10
        config.rows = 5
        config.cellStyle = .icons
        config.theme = "dracula"
        config.showMode = .active
        config.hotkey = HotkeyConfig(key: .keyCode(49), modifiers: .maskCommand)
        config.pinnedHotkey = HotkeyConfig(key: .none, modifiers: [])
        config.maxSpaces = 12
        config.backgroundAlpha = 0.5
        config.iconScale = 0.8
        config.uiScale = 0.75
        config.autoHideTimeout = 10
        config.socketHealthInterval = 30
        config.showExtraWindows = true
        config.showSpaceNumbers = false
        config.showIconStrip = false
        config.showMultiAppIcons = true
        config.showSpaceNames = true
        config.spaceNames = [1: "Term", 2: "Code"]
        config.useVimKeys = true
        config.useArrowKeys = true
        config.hudPosition = .custom(x: 0.25, y: 0.75)
        config.customHUDX = 0.25
        config.customHUDY = 0.75
        config.hideMenuBarIcon = true
        config.menuBarDisplayMode = .nearby
        config.menuBarNearbyCount = 5
        config.displayNavigationWrap = .between
        config.unifiedHUDVisibility = .all
        config.separateHUDVisibility = .active
        config.multiMonitorHUDMode = .separate
        config.focusSpaceOnWindowDrop = .modifier
        config.focusSpaceOnWindowDropModifier = .option
        config.showHUDOnSpaceChange = true
        config.updateMode = .off

        clerk.load(from: config)
        let rebuilt = clerk.buildGridConfig()

        XCTAssertEqual(rebuilt.cols, 10)
        XCTAssertEqual(rebuilt.rows, 5)
        XCTAssertEqual(rebuilt.cellStyle, .icons)
        XCTAssertEqual(rebuilt.theme, "dracula")
        XCTAssertEqual(rebuilt.showMode, .active)
        XCTAssertEqual(rebuilt.hotkey.keyCode, 49)
        XCTAssertTrue(rebuilt.hotkey.modifiers.contains(.maskCommand))
        XCTAssertTrue(rebuilt.pinnedHotkey.isDisabled)
        XCTAssertEqual(rebuilt.maxSpaces, 12)
        XCTAssertEqual(rebuilt.backgroundAlpha, 0.5)
        XCTAssertEqual(rebuilt.iconScale, 0.8)
        XCTAssertEqual(rebuilt.uiScale, 0.75)
        XCTAssertEqual(rebuilt.autoHideTimeout, 10)
        XCTAssertEqual(rebuilt.socketHealthInterval, 30)
        XCTAssertTrue(rebuilt.showExtraWindows)
        XCTAssertFalse(rebuilt.showSpaceNumbers)
        XCTAssertFalse(rebuilt.showIconStrip)
        XCTAssertTrue(rebuilt.showMultiAppIcons)
        XCTAssertTrue(rebuilt.showSpaceNames)
        XCTAssertEqual(rebuilt.spaceNames, [1: "Term", 2: "Code"])
        XCTAssertTrue(rebuilt.useVimKeys)
        XCTAssertTrue(rebuilt.useArrowKeys)
        XCTAssertEqual(rebuilt.hudPosition, .custom(x: 0.25, y: 0.75))
        XCTAssertEqual(rebuilt.customHUDX, 0.25)
        XCTAssertEqual(rebuilt.customHUDY, 0.75)
        XCTAssertTrue(rebuilt.hideMenuBarIcon)
        XCTAssertEqual(rebuilt.menuBarDisplayMode, .nearby)
        XCTAssertEqual(rebuilt.menuBarNearbyCount, 5)
        XCTAssertEqual(rebuilt.displayNavigationWrap, .between)
        XCTAssertEqual(rebuilt.unifiedHUDVisibility, .all)
        XCTAssertEqual(rebuilt.separateHUDVisibility, .active)
        XCTAssertEqual(rebuilt.multiMonitorHUDMode, .separate)
        XCTAssertEqual(rebuilt.focusSpaceOnWindowDrop, .modifier)
        XCTAssertEqual(rebuilt.focusSpaceOnWindowDropModifier, .option)
        XCTAssertTrue(rebuilt.showHUDOnSpaceChange)
        XCTAssertEqual(rebuilt.updateMode, .off)
    }

    // MARK: - hudPosition

    func testHudPositionCenter() {
        let clerk = ConfigClerk()
        clerk.hudPositionKind = .center
        XCTAssertEqual(clerk.hudPosition, .center)
    }

    func testHudPositionTop() {
        let clerk = ConfigClerk()
        clerk.hudPositionKind = .top
        XCTAssertEqual(clerk.hudPosition, .top)
    }

    func testHudPositionBottom() {
        let clerk = ConfigClerk()
        clerk.hudPositionKind = .bottom
        XCTAssertEqual(clerk.hudPosition, .bottom)
    }

    func testHudPositionCustom() {
        let clerk = ConfigClerk()
        clerk.hudPositionKind = .custom
        clerk.lastCustomHUDX = 0.3
        clerk.lastCustomHUDY = 0.7
        XCTAssertEqual(clerk.hudPosition, .custom(x: 0.3, y: 0.7))
    }

    // MARK: - hotkeyStringFrom

    func testHotkeyStringFromRoundTrip() {
        let config = HotkeyConfig(key: .keyCode(121), modifiers: .maskControl)
        let str = ConfigClerk.hotkeyStringFrom(config)
        XCTAssertEqual(str, "ctrl+pgdn")
    }

    func testHotkeyStringFromNone() {
        let config = HotkeyConfig(key: .none, modifiers: [])
        let str = ConfigClerk.hotkeyStringFrom(config)
        XCTAssertEqual(str, "none")
    }

    // MARK: - hudPositionKind

    func testHudPositionKindFromCenter() {
        XCTAssertEqual(ConfigClerk.hudPositionKind(from: .center), .center)
    }

    func testHudPositionKindFromTop() {
        XCTAssertEqual(ConfigClerk.hudPositionKind(from: .top), .top)
    }

    func testHudPositionKindFromBottom() {
        XCTAssertEqual(ConfigClerk.hudPositionKind(from: .bottom), .bottom)
    }

    func testHudPositionKindFromCustom() {
        XCTAssertEqual(ConfigClerk.hudPositionKind(from: .custom(x: 0.5, y: 0.5)), .custom)
    }
}