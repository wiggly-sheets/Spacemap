import XCTest
@testable import spacemap

final class MenubarHandlerTests: XCTestCase {


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

    func testToggleHUDMenuTitleReflectsCurrentHotkey() {
        let handler = makeHandler()
        var config = GridConfig.default
        config.hotkey = HotkeyConfig(key: .keyCode(49), modifiers: [.maskCommand, .maskShift])

        XCTAssertEqual(handler.toggleHUDMenuTitle(config: config), "Show/Hide Map (⌘+⇧+Space)")
    }


    func testWorkspacePreviewsEnabledWhenMenuBarVisibleAndNotIconMode() {
        var config = GridConfig.default
        config.presence = .menuBar
        config.menuBarDisplayMode = .dots
        XCTAssertTrue(config.needsWorkspacePreviews)
    }

    func testWorkspacePreviewsDisabledWhenMenuBarHidden() {
        var config = GridConfig.default
        config.presence = AppPresence.none
        XCTAssertFalse(config.needsWorkspacePreviews)
    }

    func testWorkspacePreviewsDisabledWhenIconMode() {
        var config = GridConfig.default
        config.menuBarDisplayMode = .icon
        XCTAssertFalse(config.needsWorkspacePreviews)
    }

    func testDotPreviewStateSkipsWindowGeometry() {
        var config = GridConfig.default
        config.menuBarDisplayMode = .dots
        let spaces = [YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil)]

        let state = MenubarHandler.dotPreviewState(config: config, spaces: spaces)

        XCTAssertEqual(state.focusedIndex, 1)
        XCTAssertEqual(state.spaces.count, 1)
        XCTAssertEqual(state.spaces.first?.index, 1)
        XCTAssertTrue(state.windows.isEmpty)
    }


    func testWindowGeometryPreviewsEnabledWhenDotsMode() {
        var config = GridConfig.default
        config.presence = .menuBar
        config.menuBarDisplayMode = .dots
        XCTAssertFalse(config.needsWindowGeometryPreviews)
    }

    func testWindowGeometryPreviewsEnabledWhenNearbyMode() {
        var config = GridConfig.default
        config.presence = .menuBar
        config.menuBarDisplayMode = .nearby
        XCTAssertTrue(config.needsWindowGeometryPreviews)
    }

    func testWindowGeometryPreviewsDisabledWhenMenuBarHidden() {
        var config = GridConfig.default
        config.presence = AppPresence.none
        XCTAssertFalse(config.needsWindowGeometryPreviews)
    }


    func testProfileMenuSignatureTracksNamesAndActiveIndex() {
        var config = GridConfig.default
        config.spaceNameProfiles = [
            SpaceNameProfile(name: "Work"),
            SpaceNameProfile(name: "Play"),
        ]
        config.activeSpaceNameProfileIndex = 0
        let initial = MenubarHandler.profileSignature(for: config)

        config.spaceNameProfiles[1].name = "Games"
        XCTAssertNotEqual(MenubarHandler.profileSignature(for: config), initial)

        let renamed = MenubarHandler.profileSignature(for: config)
        config.activeSpaceNameProfileIndex = 1
        XCTAssertNotEqual(MenubarHandler.profileSignature(for: config), renamed)
    }

    func testEveryMenuItemTargetsHandlerThatRespondsToItsAction() {
        let handler = makeHandler()
        let menu = handler.makeMenu(config: GridConfig.default)

        for item in menu.items {
            guard let action = item.action else { continue }  // separators carry no action
            XCTAssertNotNil(item.target, "no target for menu item: \(item.title)")
            XCTAssertTrue(item.target?.responds(to: action) == true, "target cannot perform \(action) for: \(item.title)")
        }
    }

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
            onSetLoginAtLogin: { _ in },
            onChangeSpaceNameProfile: { _ in }
        )
    }

    private func makeHotkeyHandler() -> HotkeyHandler {
        HotkeyHandler(hud: HUDWindowController(services: SpacemapServices(yabaiService: MockYabaiService())))
    }
}
