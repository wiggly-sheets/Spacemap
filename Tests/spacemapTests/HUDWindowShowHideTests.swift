import XCTest
import CoreGraphics
@testable import spacemap

final class HUDWindowShowHideTests: HUDWindowControllerTestCase {
    func testShowFetchesStateAndMakesHUDVisible() {
        let yabaiService = MockYabaiService()
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        ))
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        controller.show()

        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(yabaiService.buildGridStateCallCount, 1,
                       "show() must fetch the live grid state")
    }

    func testHideMakesHUDInvisibleAndClearsPin() {
        let controller = makeHUDWindowController()
        controller.show()
        controller.pin()
        XCTAssertTrue(controller.isPinned)

        controller.hide()

        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(controller.isPinned, "hiding must not leave the HUD pinned")
    }

    func testToggleDebounceResetsThenSecondToggleHides() {
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isVisible, "HUD should start hidden")

        controller.toggle()
        XCTAssertTrue(controller.isVisible)
        waitUntil("toggle debounce reset", timeout: 0.5) {
            !controller.isToggling
        }

        controller.toggle()
        XCTAssertFalse(controller.isVisible)
    }

    func testToggleIsNoOpWhileAToggleIsInFlight() {
        let controller = makeHUDWindowController()

        controller.toggle()
        XCTAssertTrue(controller.isToggling)
        XCTAssertTrue(controller.isVisible)

        controller.toggle()

        XCTAssertTrue(controller.isVisible, "second toggle() should be ignored while toggling")
    }

    func testTogglePinnedPinsThenHidesTheHUD() {
        let controller = makeHUDWindowController()
        XCTAssertFalse(controller.isPinned, "HUD should start unpinned")

        controller.togglePinned()
        XCTAssertTrue(controller.isPinned)
        XCTAssertTrue(controller.isVisible, "pinning a hidden HUD must show it")
        waitUntil("pinned toggle debounce reset", timeout: 0.5) {
            !controller.isToggling
        }

        controller.togglePinned()
        XCTAssertFalse(controller.isVisible)
    }

    func testPinKeepsTheHUDVisible() {
        let controller = makeHUDWindowController()
        controller.show()

        controller.pin()

        XCTAssertTrue(controller.isPinned)
        XCTAssertTrue(controller.isVisible, "pin() should keep the HUD visible")
    }

    func testReloadConfigAppliesInjectedConfigToEveryWiredSurface() throws {
        try withTemporaryHome { home in
            let configPath = home.appendingPathComponent(".config/spacemap/config.toml").path
            try FileManager.default.createDirectory(
                atPath: (configPath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            var initial = SpacemapConfig.default
            initial.hudKeys = .default
            initial.jumpToSpaceEnabled = false
            initial.hudShadow = true
            initial.hudPosition = .center
            initial.multiMonitorHUDMode = .unified
            initial.unifiedHUDVisibility = .active
            ConfigStore.silentMode = true
            defer { ConfigStore.silentMode = false }
            ConfigStore.saveConfig(initial, to: configPath)

            let configStore = ConfigStore()
            XCTAssertEqual(configStore.configPath, configPath)
            let themeStore = ThemeStore(
                directory: home.appendingPathComponent(".config/spacemap/themes")
            )
            var coordinatorConfig = initial
            let yabaiService = MockYabaiService()
            yabaiService.buildGridStateResult = cannedState(focusedIndex: 1)
            let coordinator = GridStateCoordinator(
                config: initial,
                yabaiService: yabaiService,
                configLoader: { coordinatorConfig }
            )
            let controller = HUDWindowController(
                services: SpacemapServices(
                    yabaiService: yabaiService,
                    configStore: configStore,
                    themeStore: themeStore,
                    alertsService: Alerts()
                ),
                coordinator: coordinator
            )
            defer { controller.hide() }
            controller.show()
            waitUntil("panel created for reload test") {
                controller.inputPanel != nil
            }
            let panel = try XCTUnwrap(controller.inputPanel)
            let input = try XCTUnwrap(hudInput(of: controller))
            XCTAssertEqual(input.config?.hudKeys, HUDKeyBindings.default)
            XCTAssertTrue(panel.hasShadow)

            let themesPath = home.appendingPathComponent(".config/spacemap/themes").path
            try FileManager.default.createDirectory(atPath: themesPath, withIntermediateDirectories: true)
            let themeContent = """
            [colors]
            background = "#101010"
            focused = "#202020"
            text = "#303030"
            dropTarget = "#404040"
            cellBg = "#505050"
            cellBgFocused = "#606060"
            rect1 = "#707070"
            rect2 = "#808080"
            rect3 = "#909090"
            """
            try themeContent.write(
                toFile: (themesPath as NSString).appendingPathComponent("my-theme.toml"),
                atomically: true,
                encoding: .utf8
            )

            var updated = initial
            var hudKeys = HUDKeyBindings.default
            hudKeys[.left] = [HotkeyConfig(key: .keyCode(7), modifiers: [])]
            updated.hudKeys = hudKeys
            updated.jumpToSpaceEnabled = true
            updated.hudShadow = false
            updated.hudPosition = .custom(x: 0.2, y: 0.2, screen: nil)
            updated.theme = "my theme"
            coordinatorConfig = updated
            ConfigStore.saveConfig(updated, to: configPath)

            controller.reloadConfig()

            XCTAssertEqual(input.config?.hudKeys, updated.hudKeys)
            XCTAssertNil(input.config?.hudKeys.command(for: 4, flags: []),
                "the reloaded config must replace the old navigation keys")
            XCTAssertEqual(input.config?.jumpToSpaceEnabled, true)
            XCTAssertFalse(panel.hasShadow, "display must receive the reloaded appearance")
            XCTAssertEqual(coordinator.config, updated, "coordinator must receive the reloaded config")
            XCTAssertTrue(themeStore.allNames().contains("my theme"),
                          "theme reload must see the newly written theme file")
        }
    }

    func testHideStopsInputTimersAndClearsPendingFocus() throws {
        let yabaiService = MockYabaiService()
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 1)
        let coordinator = GridStateCoordinator(config: .default, yabaiService: yabaiService)
        let controller = HUDWindowController(
            services: SpacemapServices(yabaiService: yabaiService, themeStore: makeTemporaryThemeStore(), alertsService: Alerts()),
            coordinator: coordinator
        )
        controller.show()
        waitUntil("state ready for hide wiring") {
            coordinator.latestState != nil
        }
        let input = try XCTUnwrap(hudInput(of: controller))
        input.startPollTimer()
        var timersCleared: Bool?
        input.onStopForTesting = { timersCleared = $0 }
        _ = coordinator.updateFocusedIndex(2)
        XCTAssertEqual(coordinator.pendingFocusedSpaceIndex, 2)

        controller.hide()

        XCTAssertEqual(timersCleared, true, "hide() must stop the input timers and poll")
        XCTAssertNil(coordinator.pendingFocusedSpaceIndex, "hide() must clear pending focus")
    }

    func testShowSeedsLastFocusedSpaceIndex() {
        let yabaiService = MockYabaiService()
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 3, display: 1, hasFocus: true, isVisible: nil, label: nil)
        ]
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 3, spaces: spaces)
        let coordinator = GridStateCoordinator(config: .default, yabaiService: yabaiService)
        let controller = HUDWindowController(
            services: SpacemapServices(yabaiService: yabaiService, themeStore: makeTemporaryThemeStore(), alertsService: Alerts()),
            coordinator: coordinator
        )
        let fetched = expectation(description: "state fetched")
        coordinator.fetch { fetched.fulfill() }
        wait(for: [fetched], timeout: 2)

        controller.show()

        XCTAssertEqual(controller.seededFocusedSpaceIndex, 3,
            "first arrow key must move from the installed focus, not no-op")
    }

    func testShowSettingsHidesTheHUDAndForwards() {
        var forwarded = 0
        let controller = makeHUDWindowController()
        controller.onShowSettings = { forwarded += 1 }
        controller.show()

        controller.showSettings()

        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(forwarded, 1)
    }

}
