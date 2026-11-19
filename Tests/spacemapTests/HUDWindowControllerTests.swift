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
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        ))
    }


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

    func testFocusedWindowAtOpenPersistsAcrossFrameUpdatesAndClearsOnHide() {
        let yabaiService = MockYabaiService()
        yabaiService.queryFocusedWindowResult = 77
        let state = cannedState()
        yabaiService.buildGridStateResult = state
        let services = SpacemapServices(
            yabaiService: yabaiService,
            themeStore: makeTemporaryThemeStore(),
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

    func testAutoHideRunsTheSameDragTeardownAsAnExplicitHide() throws {
        try withTemporaryHome { home in
            let configPath = home.appendingPathComponent(".config/spacemap/config.toml").path
            try FileManager.default.createDirectory(
                atPath: (configPath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            var config = SpacemapConfig.default
            config.autoHideTimeout = 1
            ConfigStore.silentMode = true
            defer { ConfigStore.silentMode = false }
            ConfigStore.saveConfig(config, to: configPath)

            let yabaiService = MockYabaiService()
            yabaiService.queryFocusedWindowResult = 77
            // A stable polled focus keeps onRefresh from re-arming auto-hide
            // every half second.
            yabaiService.queryFocusedSpaceIndexResult = 1
            yabaiService.buildGridStateResult = cannedState(focusedIndex: 1)
            let controller = HUDWindowController(services: SpacemapServices(
                yabaiService: yabaiService,
                configStore: ConfigStore(),
                themeStore: makeTemporaryThemeStore(),
                alertsService: Alerts()
            ))
            defer { controller.hide() }
            controller.show()
            waitUntil("focused window recorded at open") {
                controller.focusedWindowIDAtOpen == 77
            }
            let dragHandler = try XCTUnwrap(dragHandler(of: controller))
            XCTAssertTrue(dragHandler.isEventTapRequested, "drag targeting arms once the HUD renders")

            waitUntil("auto-hide fires", timeout: 3) {
                !controller.isVisible
            }

            XCTAssertNil(controller.focusedWindowIDAtOpen,
                "auto-hide must clear the presentation's focused window")
            XCTAssertFalse(dragHandler.isEventTapRequested,
                "auto-hide must stop the drag tap like an explicit hide does")
        }
    }

    func testRefreshWhenVisibleFetchesAgain() {
        let yabaiService = MockYabaiService()
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            themeStore: makeTemporaryThemeStore(),
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
            themeStore: makeTemporaryThemeStore(),
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
            themeStore: makeTemporaryThemeStore(),
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

    func testPerformRoutesCommandsToTheirExecutionPaths() {
        let yabaiService = MockYabaiService()
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: nil, label: nil, type: "bsp"),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: nil, label: nil)
        ]
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 1, spaces: spaces)
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        ))
        controller.show()
        waitUntil("focus seeded for perform") {
            controller.seededFocusedSpaceIndex == 1
        }

        controller.perform(.layoutBSP)
        XCTAssertEqual(yabaiService.lastSpaceLayout, .bsp)

        controller.perform(.cycleLayout)
        XCTAssertEqual(yabaiService.lastSpaceLayout, .stack,
                       "cycleLayout advances from the focused space's layout")

        controller.perform(.moveSpaceForward)
        XCTAssertEqual(yabaiService.swapSpacesCallCount, 1,
                       "moveSpaceForward runs the same swap the scalar HUD key used")
        XCTAssertEqual(yabaiService.lastSwapSourceIndex, 1)
        XCTAssertEqual(yabaiService.lastSwapTargetIndex, 2)

        controller.perform(.close)
        XCTAssertFalse(controller.isVisible, "close hides the HUD")
    }

    func testPerformMovesTheFocusedSpaceBack() {
        let yabaiService = MockYabaiService()
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: true, isVisible: nil, label: nil)
        ]
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 2, spaces: spaces)
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        ))
        controller.show()
        waitUntil("focus seeded for moveSpaceBack") {
            controller.seededFocusedSpaceIndex == 2
        }

        controller.perform(.moveSpaceBack)

        XCTAssertEqual(yabaiService.swapSpacesCallCount, 1)
        XCTAssertEqual(yabaiService.lastSwapSourceIndex, 2)
        XCTAssertEqual(yabaiService.lastSwapTargetIndex, 1)
    }

    func testNavigateFocusesTheAdjacentSpace() {        let yabaiService = MockYabaiService()
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: nil, label: nil)
        ]
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 1, spaces: spaces)
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            themeStore: makeTemporaryThemeStore(),
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
            services: SpacemapServices(yabaiService: yabaiService, themeStore: makeTemporaryThemeStore(), alertsService: Alerts()),
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
            services: SpacemapServices(yabaiService: yabaiService, themeStore: makeTemporaryThemeStore(), alertsService: Alerts())
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
            services: SpacemapServices(yabaiService: yabaiService, themeStore: makeTemporaryThemeStore(), alertsService: Alerts())
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

    private func hudInput(of controller: HUDWindowController) -> HUDInput? {
        Mirror(reflecting: controller).children
            .first { $0.label == "hudInput" }?
            .value as? HUDInput
    }

    private func dragHandler(of controller: HUDWindowController) -> WindowDragHandler? {
        Mirror(reflecting: controller).children
            .first { $0.label == "dragHandler" }?
            .value as? WindowDragHandler
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

    func testDeleteSpaceDestroysTheFocusedSpace() {
        let yabaiService = MockYabaiService()
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: true, isVisible: nil, label: nil)
        ]
        yabaiService.buildGridStateResult = cannedState(focusedIndex: 2, spaces: spaces)
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        ))
        controller.show()
        waitUntil("focus seeded for delete") {
            controller.seededFocusedSpaceIndex == 2
        }
        let buildsBefore = yabaiService.buildGridStateCallCount

        controller.perform(.deleteSpace)

        XCTAssertEqual(yabaiService.destroySpaceCallCount, 1)
        XCTAssertEqual(yabaiService.lastDestroySpaceIndex, 2)
        waitUntil("refresh after the destroy settles") {
            yabaiService.buildGridStateCallCount > buildsBefore
        }
    }

    func testSpaceDropSwapsOnlyWhenTheTargetDiffers() {
        let yabaiService = MockYabaiService()
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        ))
        controller.externalDropTarget = 3

        controller.handleSpaceDrop(source: 2)

        XCTAssertEqual(yabaiService.swapSpacesCallCount, 1)
        XCTAssertEqual(yabaiService.lastSwapSourceIndex, 2)
        XCTAssertEqual(yabaiService.lastSwapTargetIndex, 3)

        controller.handleSpaceDrop(source: 3)
        XCTAssertEqual(yabaiService.swapSpacesCallCount, 1,
            "a drop onto its own space must not swap")
    }

    func testWindowDropMovesWindowsToTheHighlightedTarget() {
        let yabaiService = MockYabaiService()
        let controller = HUDWindowController(services: SpacemapServices(
            yabaiService: yabaiService,
            themeStore: makeTemporaryThemeStore(),
            alertsService: Alerts()
        ))
        controller.externalDropTarget = 3

        controller.handleWindowDrop(ids: [7, 8], source: 1)

        XCTAssertEqual(yabaiService.moveWindowCallCount, 1)
        XCTAssertEqual(yabaiService.lastMovedWindowIDs, [7, 8])
        XCTAssertEqual(yabaiService.lastMoveWindowIndex, 3)

        controller.handleWindowDrop(ids: [], source: 1)
        XCTAssertEqual(yabaiService.moveWindowCallCount, 1, "an empty drag must not move windows")
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

    func testExternalDragHoldsAutoHideUntilItEnds() {
        let controller = makeHUDWindowController()
        controller.show()
        XCTAssertTrue(controller.isAutoHideScheduled, "an unpinned HUD arms auto-hide")

        controller.setExternalDragActive(true)
        XCTAssertNil(controller.externalDropTarget)
        XCTAssertFalse(controller.isAutoHideScheduled, "a strip drag must hold auto-hide")

        controller.setExternalDragActive(false)
        XCTAssertTrue(controller.isAutoHideScheduled, "auto-hide re-arms once the drag ends")
    }
}
