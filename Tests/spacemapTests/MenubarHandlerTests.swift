import XCTest
@testable import spacemap

final class MenubarHandlerTests: XCTestCase {

    // MARK: - hotkeyMenuString

    func testHotkeyMenuStringNone() {
        let config = HotkeyConfig(key: .none, modifiers: [])
        XCTAssertEqual(makeHandler().hotkeyMenuString(config), "None")
    }

    func testHotkeyMenuStringKeyCodeNoModifier() {
        let config = HotkeyConfig(key: .keyCode(49), modifiers: [])
        XCTAssertEqual(makeHandler().hotkeyMenuString(config), "Space")
    }

    func testHotkeyMenuStringKeyCodeWithModifier() {
        let config = HotkeyConfig(key: .keyCode(121), modifiers: .maskControl)
        XCTAssertEqual(makeHandler().hotkeyMenuString(config), "⌃+PgDn")
    }

    func testHotkeyMenuStringKeyCodeWithMultipleModifiers() {
        let config = HotkeyConfig(key: .keyCode(0), modifiers: [.maskCommand, .maskShift])
        XCTAssertEqual(makeHandler().hotkeyMenuString(config), "⌘+⇧+?")
    }

    func testHotkeyMenuStringMediaKey() {
        let config = HotkeyConfig(key: .mediaKey(.playPause), modifiers: [.maskCommand])
        XCTAssertEqual(makeHandler().hotkeyMenuString(config), "⌘+play-pause")
    }

    func testHotkeyMenuStringArrowKeys() {
        let handler = makeHandler()
        XCTAssertEqual(handler.hotkeyMenuString(HotkeyConfig(key: .keyCode(123), modifiers: [])), "←")
        XCTAssertEqual(handler.hotkeyMenuString(HotkeyConfig(key: .keyCode(124), modifiers: [])), "→")
        XCTAssertEqual(handler.hotkeyMenuString(HotkeyConfig(key: .keyCode(126), modifiers: [])), "↑")
        XCTAssertEqual(handler.hotkeyMenuString(HotkeyConfig(key: .keyCode(125), modifiers: [])), "↓")
    }

    func testHotkeyMenuStringUnknownKeyCode() {
        let config = HotkeyConfig(key: .keyCode(999), modifiers: [])
        XCTAssertEqual(makeHandler().hotkeyMenuString(config), "?")
    }

    func testHotkeyMenuStringHyperModifier() {
        let config = HotkeyConfig(key: .keyCode(36), modifiers: [.maskControl, .maskCommand, .maskAlternate, .maskShift])
        XCTAssertEqual(makeHandler().hotkeyMenuString(config), "⌃+⌘+⌥+⇧+Return")
    }

    // MARK: - workspacePreviewsEnabled

    func testWorkspacePreviewsEnabledWhenMenuBarVisibleAndNotIconMode() {
        var config = GridConfig.default
        config.hideMenuBarIcon = false
        config.menuBarDisplayMode = .dots
        XCTAssertTrue(makeHotkeyHandler().workspacePreviewsEnabled(for: config))
    }

    func testWorkspacePreviewsDisabledWhenMenuBarHidden() {
        var config = GridConfig.default
        config.hideMenuBarIcon = true
        XCTAssertFalse(makeHotkeyHandler().workspacePreviewsEnabled(for: config))
    }

    func testWorkspacePreviewsDisabledWhenIconMode() {
        var config = GridConfig.default
        config.menuBarDisplayMode = .icon
        XCTAssertFalse(makeHotkeyHandler().workspacePreviewsEnabled(for: config))
    }

    // MARK: - windowGeometryPreviewsEnabled

    func testWindowGeometryPreviewsEnabledWhenDotsMode() {
        var config = GridConfig.default
        config.hideMenuBarIcon = false
        config.menuBarDisplayMode = .dots
        XCTAssertFalse(makeHotkeyHandler().windowGeometryPreviewsEnabled(for: config))
    }

    func testWindowGeometryPreviewsEnabledWhenNearbyMode() {
        var config = GridConfig.default
        config.hideMenuBarIcon = false
        config.menuBarDisplayMode = .nearby
        XCTAssertTrue(makeHotkeyHandler().windowGeometryPreviewsEnabled(for: config))
    }

    func testWindowGeometryPreviewsDisabledWhenMenuBarHidden() {
        var config = GridConfig.default
        config.hideMenuBarIcon = true
        XCTAssertFalse(makeHotkeyHandler().windowGeometryPreviewsEnabled(for: config))
    }

    // MARK: - Helpers

    private func makeHandler() -> MenubarHandler {
        MenubarHandler(
            yabaiService: MockYabaiService(),
            onToggleHUD: {},
            onShowAbout: {},
            onShowSettings: {},
            onInstallCLI: {},
            onCheckForUpdates: {},
            onRestartApp: {},
            onGetConfig: { GridConfig.default },
            onSetLoginAtLogin: { _ in }
        )
    }

    private func makeHotkeyHandler() -> HotkeyHandler {
        HotkeyHandler(hud: HUDWindowController(services: SpacemapServices(yabaiService: MockYabaiService())))
    }
}