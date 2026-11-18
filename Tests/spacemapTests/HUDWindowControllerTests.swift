import XCTest
import CoreGraphics
@testable import spacemap


final class HUDWindowControllerTests: XCTestCase {


    private func cannedState(
        focusedIndex: Int? = nil,
        spaces: [YabaiSpace] = [],
        windows: [YabaiWindow] = [],
        displays: [YabaiDisplay] = []
    ) -> GridState {
        GridState(
            config: .default,
            spaces: spaces,
            windows: windows,
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: focusedIndex,
            displays: displays
        )
    }

    private func makeHUDWindowController() -> HUDWindowController {
        HUDWindowController(services: SpacemapServices(
            yabaiService: MockYabaiService(),
            alertsService: Alerts()
        ))
    }


    func testShowFetchesStateAndMakesHUDVisible() {
        let yabaiService = MockYabaiService()
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
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
            var initial = GridConfig.default
            initial.hudKeys = .default
            initial.jumpToSpaceEnabled = false
            initial.hudShadow = true
            initial.hudPosition = .center
            initial.multiMonitorHUDMode = .unified
            initial.unifiedHUDVisibility = .active
            AppConfig.silentMode = true
            defer { AppConfig.silentMode = false }
            AppConfig.saveConfig(initial, to: configPath)

            let appConfig = AppConfig()
            XCTAssertEqual(appConfig.configPath, configPath)
            let themeService = ThemeManager()
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
                    appConfig: appConfig,
                    themeService: themeService,
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
            updated.hudPosition = .custom(x: 0.2, y: 0.2)
            updated.theme = "my theme"
            coordinatorConfig = updated
            AppConfig.saveConfig(updated, to: configPath)

            controller.reloadConfig()

            XCTAssertEqual(input.config?.hudKeys, updated.hudKeys)
            XCTAssertNil(HUDInput.hudKeyAction(
                keyCode: 4,
                flags: [],
                bindings: input.config?.hudKeys ?? .default
            ), "the reloaded config must replace the old navigation keys")
            XCTAssertEqual(input.config?.jumpToSpaceEnabled, true)
            XCTAssertFalse(panel.hasShadow, "display must receive the reloaded appearance")
            XCTAssertEqual(coordinator.config, updated, "coordinator must receive the reloaded config")
            XCTAssertTrue(themeService.allNames().contains("my theme"),
                          "theme reload must see the newly written theme file")
        }
    }

    func testHideStopsInputTimersAndClearsPendingFocus() throws {
        let yabaiService = MockYabaiService()
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 1)
        let coordinator = GridStateCoordinator(config: .default, yabaiService: yabaiService)
        let controller = HUDWindowController(
            services: SpacemapServices(yabaiService: yabaiService, alertsService: Alerts()),
            coordinator: coordinator
        )
        controller.show()
        waitUntil("state ready for hide wiring") {
            coordinator.latestState != nil
        }
        let input = try XCTUnwrap(hudInput(of: controller))
        input.autoHideTimeout = 30
        input.resetAutoHideTimer()
        var timersCleared: Bool?
        input.onStopForTesting = { timersCleared = $0 }
        _ = coordinator.updateFocusedIndex(2)
        XCTAssertEqual(coordinator.pendingFocusedSpaceIndex, 2)

        controller.hide()

        XCTAssertEqual(timersCleared, true, "hide() must stop the input timers and poll")
        XCTAssertNil(coordinator.pendingFocusedSpaceIndex, "hide() must clear pending focus")
    }

    func testFocusedWindowAtOpenPersistsAcrossFrameUpdatesAndClearsOnHide() {
        let yabaiService = MockYabaiService()
        yabaiService.queryFocusedWindowResult = 77
        let state = cannedState()
        yabaiService.buildGridStateResult = state
        let services = SpacemapServices(
            yabaiService: yabaiService,
            alertsService: Alerts()
        )
        let coordinator = GridStateCoordinator(config: .default, yabaiService: yabaiService)
        let controller = HUDWindowController(services: services, coordinator: coordinator)

        controller.show()
        waitUntil("focused window recorded at open") {
            controller.focusedWindowIDAtOpen == 77
        }
        controller.updateCellFrames(state: state)
        XCTAssertEqual(controller.focusedWindowIDAtOpen, 77)

        controller.hide()
        XCTAssertNil(controller.focusedWindowIDAtOpen)
    }

    func testRefreshWhenVisibleFetchesAgain() {
        let yabaiService = MockYabaiService()
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            alertsService: Alerts()
        ))
        controller.show()
        let buildsBefore = yabaiService.buildGridStateCallCount

        controller.refresh()

        XCTAssertGreaterThan(yabaiService.buildGridStateCallCount, buildsBefore)
        XCTAssertTrue(controller.isVisible)
    }

    func testRefreshWhenHiddenPrewarmsWithoutShowing() {
        let yabaiService = MockYabaiService()
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            alertsService: Alerts()
        ))

        controller.refresh()

        XCTAssertEqual(yabaiService.buildGridStateCallCount, 1,
                       "a hidden refresh with no cached state must prewarm the state")
        XCTAssertFalse(controller.isVisible)
    }

    func testRefreshWhenHiddenWithCachedStateReadsTheLiveFocus() {
        let yabaiService = MockYabaiService()
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 1)
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            alertsService: Alerts()
        ))
        controller.show()
        waitUntil("state cached at show") {
            controller.seededFocusedSpaceIndex == 1
        }
        controller.hide()
        let queriesBefore = yabaiService.queryFocusedSpaceIndexCallCount

        controller.refresh()

        XCTAssertEqual(yabaiService.queryFocusedSpaceIndexCallCount, queriesBefore + 1)
        XCTAssertFalse(controller.isVisible)
    }

    func testNavigateFocusesTheAdjacentSpace() {
        let yabaiService = MockYabaiService()
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: nil, label: nil)
        ]
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 1, spaces: spaces)
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            alertsService: Alerts()
        ))
        controller.show()
        waitUntil("focus seeded from fetched state") {
            controller.seededFocusedSpaceIndex == 1
        }

        controller.navigate(direction: .right)

        XCTAssertEqual(yabaiService.focusSpaceAsyncCallCount, 1)
    }

    func testRecentSpaceFocusUsesLiteralYabaiTarget() {
        let yabaiService = MockYabaiService()
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 3, display: 1, hasFocus: true, isVisible: nil, label: nil)
        ]
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 3, spaces: spaces)
        let coordinator = GridStateCoordinator(config: .default, yabaiService: yabaiService)
        let controller = HUDWindowController(
            services: SpacemapServices(yabaiService: yabaiService, alertsService: Alerts()),
            coordinator: coordinator
        )

        controller.show()
        XCTAssertEqual(yabaiService.focusSpaceTargetCallCount, 0)

        controller.focusRecent()

        XCTAssertEqual(yabaiService.focusSpaceTargetCallCount, 1)
        XCTAssertEqual(yabaiService.lastFocusSpaceTarget, SpaceFocusTarget(argument: "recent"))
    }

    func testRecentSpaceFocusRunsOffTheMainThreadQueue() {
        let yabaiService = MockYabaiService()
        yabaiService.runsYabaiQueueImmediately = false
        let controller = HUDWindowController(
            services: SpacemapServices(yabaiService: yabaiService, alertsService: Alerts())
        )

        controller.focusRecent()

        XCTAssertEqual(yabaiService.focusSpaceTargetCallCount, 0,
            "focusRecent must not run yabai synchronously on the main thread")
        yabaiService.performPendingYabaiQueueBlocks()
        XCTAssertEqual(yabaiService.focusSpaceTargetCallCount, 1)
        XCTAssertEqual(yabaiService.lastFocusSpaceTarget, SpaceFocusTarget(argument: "recent"))
    }

    func testRecentSpaceFocusRefreshesStateAfterFocusCompletes() {
        let yabaiService = MockYabaiService()
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 3, display: 1, hasFocus: true, isVisible: nil, label: nil)
        ]
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 3, spaces: spaces)
        let controller = HUDWindowController(
            services: SpacemapServices(yabaiService: yabaiService, alertsService: Alerts())
        )
        controller.show()
        waitUntil("initial show settled") {
            controller.seededFocusedSpaceIndex == 3
        }
        let buildsBefore = yabaiService.buildGridStateCallCount

        controller.focusRecent()

        waitUntil("refresh after recent focus") {
            yabaiService.buildGridStateCallCount > buildsBefore
        }
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
            services: SpacemapServices(yabaiService: yabaiService, alertsService: Alerts()),
            coordinator: coordinator
        )
        let fetched = expectation(description: "state fetched")
        coordinator.fetch { fetched.fulfill() }
        wait(for: [fetched], timeout: 2)

        controller.show()

        XCTAssertEqual(controller.seededFocusedSpaceIndex, 3,
            "first arrow key must move from the installed focus, not no-op")
    }

    private func hudInput(of controller: HUDWindowController) -> HUDInput? {
        Mirror(reflecting: controller).children
            .first { $0.label == "hudInput" }?
            .value as? HUDInput
    }

    private func withTemporaryHome(_ body: (URL) throws -> Void) throws {
        // CFFIXED_USER_HOME is process-wide: this test must not share a process
        // with other home-reading tests. `swift test --parallel` isolates each
        // worker in its own process; in-process XCTest parallelism would not.
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-hud-reload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let previous = getenv("CFFIXED_USER_HOME").map { String(cString: $0) }
        setenv("CFFIXED_USER_HOME", home.path, 1)
        defer {
            if let previous {
                setenv("CFFIXED_USER_HOME", previous, 1)
            } else {
                unsetenv("CFFIXED_USER_HOME")
            }
            try? FileManager.default.removeItem(at: home)
        }
        try body(home)
    }

    private func waitUntil(
        _ message: String,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(message)", file: file, line: line)
    }

    func testHoverCellUpdatesOnlyHoverState() {
        let controller = makeHUDWindowController()
        controller.show()
        let display = controller.hudDisplayForTesting
        let renders = display.fullRenderCount
        let iconPreloads = display.iconPreloadCount
        let thumbnailRefreshes = display.thumbnailRefreshCount
        let panelOrigin = controller.inputPanel?.frame.origin

        controller.handleHoverCell(3)

        XCTAssertEqual(display.hoveredCell, 3)
        XCTAssertEqual(display.hoverState.cell, 3)
        XCTAssertEqual(display.fullRenderCount, renders, "hover must not re-render the HUD")
        XCTAssertEqual(display.iconPreloadCount, iconPreloads, "hover must not preload icons")
        XCTAssertEqual(display.thumbnailRefreshCount, thumbnailRefreshes,
            "hover must not refresh thumbnails")
        XCTAssertEqual(controller.inputPanel?.frame.origin, panelOrigin,
            "hover must not move or resize the panel")

        controller.handleHoverCell(nil)
        XCTAssertNil(display.hoveredCell)
    }
}
