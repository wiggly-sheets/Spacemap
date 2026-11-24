import XCTest
import CoreGraphics
@testable import spacemap

final class HUDWindowRefreshTests: HUDWindowControllerTestCase {
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

}
