import XCTest
@testable import spacemap

final class MenubarHandlerTests: XCTestCase {

    // MARK: - hotkeyMenuString

    func testHotkeyMenuStringNone() {
        let config = HotkeyConfig(key: .none, modifiers: [])
        XCTAssertEqual(MenubarHandler.hotkeyMenuString(config), "None")
    }

    func testHotkeyMenuStringKeyCodeNoModifier() {
        let config = HotkeyConfig(key: .keyCode(49), modifiers: [])
        XCTAssertEqual(MenubarHandler.hotkeyMenuString(config), "Space")
    }

    func testHotkeyMenuStringKeyCodeWithModifier() {
        let config = HotkeyConfig(key: .keyCode(121), modifiers: .maskControl)
        XCTAssertEqual(MenubarHandler.hotkeyMenuString(config), "⌃PgDn")
    }

    func testHotkeyMenuStringKeyCodeWithMultipleModifiers() {
        let config = HotkeyConfig(key: .keyCode(0), modifiers: [.maskCommand, .maskShift])
        XCTAssertEqual(MenubarHandler.hotkeyMenuString(config), "⌘⇧a")
    }

    func testHotkeyMenuStringMediaKey() {
        let config = HotkeyConfig(key: .mediaKey(.playPause), modifiers: [.maskCommand])
        XCTAssertEqual(MenubarHandler.hotkeyMenuString(config), "⌘play-pause")
    }

    func testHotkeyMenuStringArrowKeys() {
        let leftConfig = HotkeyConfig(key: .keyCode(123), modifiers: [])
        XCTAssertEqual(MenubarHandler.hotkeyMenuString(leftConfig), "←")

        let rightConfig = HotkeyConfig(key: .keyCode(124), modifiers: [])
        XCTAssertEqual(MenubarHandler.hotkeyMenuString(rightConfig), "→")

        let upConfig = HotkeyConfig(key: .keyCode(126), modifiers: [])
        XCTAssertEqual(MenubarHandler.hotkeyMenuString(upConfig), "↑")

        let downConfig = HotkeyConfig(key: .keyCode(125), modifiers: [])
        XCTAssertEqual(MenubarHandler.hotkeyMenuString(downConfig), "↓")
    }

    func testHotkeyMenuStringUnknownKeyCode() {
        let config = HotkeyConfig(key: .keyCode(999), modifiers: [])
        XCTAssertEqual(MenubarHandler.hotkeyMenuString(config), "?")
    }

    func testHotkeyMenuStringHyperModifier() {
        let config = HotkeyConfig(key: .keyCode(36), modifiers: [.maskControl, .maskCommand, .maskAlternate, .maskShift])
        XCTAssertEqual(MenubarHandler.hotkeyMenuString(config), "⌃⌘⌥⇧Return")
    }

    // MARK: - workspacePreviewsEnabled

    func testWorkspacePreviewsEnabledWhenMenuBarVisibleAndNotIconMode() {
        var config = GridConfig.default
        config.hideMenuBarIcon = false
        config.menuBarDisplayMode = .dots
        let handler = makeHandler(config: config)
        XCTAssertTrue(handler.services.yabaiService.workspacePreviewsEnabled(for: config))
    }

    func testWorkspacePreviewsDisabledWhenMenuBarHidden() {
        var config = GridConfig.default
        config.hideMenuBarIcon = true
        let handler = makeHandler(config: config)
        XCTAssertFalse(handler.services.yabaiService.workspacePreviewsEnabled(for: config))
    }

    func testWorkspacePreviewsDisabledWhenIconMode() {
        var config = GridConfig.default
        config.menuBarDisplayMode = .icon
        let handler = makeHandler(config: config)
        XCTAssertFalse(handler.services.yabaiService.workspacePreviewsEnabled(for: config))
    }

    // MARK: - windowGeometryPreviewsEnabled

    func testWindowGeometryPreviewsEnabledWhenDotsMode() {
        var config = GridConfig.default
        config.hideMenuBarIcon = false
        config.menuBarDisplayMode = .dots
        let handler = makeHandler(config: config)
        XCTAssertFalse(handler.services.yabaiService.windowGeometryPreviewsEnabled(for: config))
    }

    func testWindowGeometryPreviewsEnabledWhenNearbyMode() {
        var config = GridConfig.default
        config.hideMenuBarIcon = false
        config.menuBarDisplayMode = .nearby
        let handler = makeHandler(config: config)
        XCTAssertTrue(handler.services.yabaiService.windowGeometryPreviewsEnabled(for: config))
    }

    func testWindowGeometryPreviewsDisabledWhenMenuBarHidden() {
        var config = GridConfig.default
        config.hideMenuBarIcon = true
        let handler = makeHandler(config: config)
        XCTAssertFalse(handler.services.yabaiService.windowGeometryPreviewsEnabled(for: config))
    }

    // MARK: - Helpers

    private func makeHandler(config: GridConfig) -> MenubarHandler {
        MenubarHandler(
            services: SpacemapServices(
                yabaiService: MockYabaiService(),
                alertsService: Alerts() // Uses the Alerts typealias which is AlertsServiceImpl
            ),
            onToggleHUD: {},
            onShowAbout: {},
            onShowSettings: {},
            onInstallCLI: {},
            onCheckForUpdates: {},
            onRestartApp: {},
            onSetLoginAtLogin: { _ in }
        )
    }
}