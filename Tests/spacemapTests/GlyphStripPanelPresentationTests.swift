import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


final class GlyphStripPanelPresentationTests: XCTestCase {

    private func enabledConfig() -> SpacemapConfig {
        var config = SpacemapConfig.default
        config.glyphStrip.enabled = true
        return config
    }

    func testContentOnlyRefreshRepaintsEvenWhenTheFrameIsUnchanged() throws {
        _ = NSApplication.shared
        let controller = GlyphStripPanelController(
            yabaiService: MockYabaiService(),
            themeStore: makeTemporaryThemeStore()
        )
        controller.update(config: enabledConfig())
        controller.present()

        let panel = try XCTUnwrap(controller.panel)
        let frame = panel.frame
        // Drain the coalesced refresh scheduled by `update` so a late pass
        // cannot add a second increment during this assertion.
        controller.pendingRefresh?.cancel()
        let repaintsBefore = controller.contentRepaintCount

        controller.present()

        XCTAssertEqual(panel.frame, frame, "the second present must reuse the frame")
        XCTAssertEqual(
            controller.contentRepaintCount,
            repaintsBefore + 1,
            "content changes must request a repaint without a frame move"
        )
    }

    /// A config change must drop the cached panel render, or the next repaint
    /// keeps the old padding.
    func testConfigUpdateRebuildsTheCachedPanelLayout() throws {
        guard NSScreen.main != nil else {
            throw XCTSkip("no display available in this environment")
        }
        _ = NSApplication.shared
        let yabai = MockYabaiService()
        yabai.buildGridStateResult = GridState(
            config: .default,
            spaces: [1, 2].map {
                YabaiSpace(id: $0, index: $0, display: 1, hasFocus: $0 == 1, isVisible: true, label: nil)
            },
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: 1
        )
        let controller = GlyphStripPanelController(
            yabaiService: yabai,
            themeStore: makeTemporaryThemeStore()
        )
        var config = enabledConfig()
        config.glyphStrip.padding = 4
        controller.update(config: config)
        controller.present()

        // The first pass waits for the off-main font load.
        let deadline = Date().addingTimeInterval(2)
        while controller.layout.slots.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        controller.pendingRefresh?.cancel()
        let first = try XCTUnwrap(controller.layout.slots.first)
        XCTAssertEqual(first.minX, 4, accuracy: 0.5)

        // Same config and bounds reuse the cached render.
        let builds = controller.layoutBuildCount
        _ = controller.layout
        XCTAssertEqual(controller.layoutBuildCount, builds)

        var widened = config
        widened.glyphStrip.padding = 12
        controller.update(config: widened)
        controller.pendingRefresh?.cancel()

        let second = try XCTUnwrap(controller.layout.slots.first)
        XCTAssertEqual(second.minX, 12, accuracy: 0.5, "the cache must rebuild from the new config")
        XCTAssertEqual(controller.layoutBuildCount, builds + 1)
    }

    /// A fullscreen exit can leave AppKit treating the strip as visible while
    /// the window server has pinned it to the old space. Reattaching must put
    /// it back on every space, not just the active one.
    func testReattachRestoresAllSpacesBehavior() throws {
        _ = NSApplication.shared
        let controller = GlyphStripPanelController(
            yabaiService: MockYabaiService(),
            themeStore: makeTemporaryThemeStore()
        )
        controller.update(config: enabledConfig())
        controller.present()

        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(panel.isVisible)
        controller.reattachPanelToActiveSpace()

        let restored = expectation(description: "collection behavior restored")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { restored.fulfill() }
        wait(for: [restored], timeout: 1)
        XCTAssertEqual(
            panel.collectionBehavior,
            [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        )
    }

    func testHidingInvalidatesInFlightRefreshAndStalePresentCannotShow() throws {
        _ = NSApplication.shared
        let controller = GlyphStripPanelController(
            yabaiService: MockYabaiService(),
            themeStore: makeTemporaryThemeStore()
        )
        controller.update(config: enabledConfig())
        controller.present()

        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(panel.isVisible)
        let generationBeforeHide = controller.refreshGeneration

        controller.toggleVisibilityByHotkey()
        // Hide fades before ordering out.
        let deadline = Date().addingTimeInterval(1)
        while panel.isVisible, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertFalse(panel.isVisible)
        XCTAssertGreaterThan(controller.refreshGeneration, generationBeforeHide)
        XCTAssertNil(controller.pendingRefresh, "hide must cancel the coalesced refresh")

        // A reply that was already in flight used to call present() and put the
        // strip back on screen; the hidden guard must reject it.
        controller.present()
        XCTAssertFalse(panel.isVisible)
    }

    /// A free-placed strip first honours the display it was saved on, so its
    /// position survives a monitor change; a preset has no such claim, and a
    /// display that is gone must fall through to the usual target.
    func testStoredScreenHonoursCustomPlacementOnly() throws {
        guard let main = NSScreen.main else {
            throw XCTSkip("no display available in this environment")
        }
        var strip = SpacemapConfig.default.glyphStrip
        strip.position = .custom
        strip.customScreen = ScreenContext.displayIdentifier(for: main)
        XCTAssertTrue(GlyphStripPanelController.storedScreen(for: strip, screens: [main]) === main)

        strip.position = .leftOfNotch
        XCTAssertNil(GlyphStripPanelController.storedScreen(for: strip, screens: [main]))

        let identifier = ScreenContext.displayIdentifier(for: main)
        strip.plainPosition = .custom
        strip.plainCustomScreen = identifier
        XCTAssertTrue(GlyphStripPanelController.storedScreen(for: strip, screens: [main]) === main)

        strip.plainPosition = .center
        strip.position = .custom
        strip.customScreen = "gone-display"
        XCTAssertNil(GlyphStripPanelController.storedScreen(for: strip, screens: [main]))

        strip.position = .leftOfNotch
        strip.plainPosition = .custom
        strip.plainCustomScreen = "gone-plain"
        strip.customScreen = identifier
        XCTAssertNil(
            GlyphStripPanelController.storedScreen(for: strip, hasNotch: false, screens: [main]),
            "a plain placement does not reuse the notch display identity"
        )
    }

    func testSettingsUpdateClearsAWedgeRefreshLatch() {
        _ = NSApplication.shared
        let controller = GlyphStripPanelController(
            yabaiService: MockYabaiService(),
            themeStore: makeTemporaryThemeStore()
        )
        controller.update(config: enabledConfig())
        controller.pendingRefresh?.cancel()
        controller.markRefreshWedgedForTesting()
        XCTAssertTrue(controller.refreshInFlight)
        XCTAssertTrue(controller.needsFollowupRefresh)

        controller.update(config: enabledConfig())

        XCTAssertFalse(controller.refreshInFlight, "updateConfig cancellation must not wedge the strip")
        XCTAssertFalse(controller.needsFollowupRefresh)
        XCTAssertNotNil(controller.pendingRefresh, "a fresh refresh should be queued")
    }

    /// A daemon restart makes yabai report no spaces. That empty state must not
    /// replace a painted strip with a lone add button until the next signal.
    func testEmptyStateRefreshKeepsTheLastPaintedStrip() throws {
        guard NSScreen.main != nil else {
            throw XCTSkip("no display available in this environment")
        }
        _ = NSApplication.shared
        let yabai = MockYabaiService()
        yabai.buildGridStateResult = GridState(
            config: .default,
            spaces: [1, 2].map {
                YabaiSpace(id: $0, index: $0, display: 1, hasFocus: $0 == 1, isVisible: true, label: nil)
            },
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: 1
        )
        let controller = GlyphStripPanelController(
            yabaiService: yabai,
            themeStore: makeTemporaryThemeStore()
        )
        controller.update(config: enabledConfig())
        controller.present()

        // The first pass waits for the off-main font load.
        let deadline = Date().addingTimeInterval(2)
        while controller.layout.slots.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        controller.pendingRefresh?.cancel()
        let painted = controller.layout.slots
        XCTAssertFalse(painted.isEmpty, "the strip must paint spaces while yabai is up")

        yabai.buildGridStateResult = GridState(
            config: .default,
            spaces: [],
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: nil
        )
        let buildsBefore = yabai.buildGridStateCallCount
        controller.refresh()
        let emptyDeadline = Date().addingTimeInterval(2)
        while yabai.buildGridStateCallCount == buildsBefore, Date() < emptyDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        // Let the coordinator's main-queue completion paint.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(controller.layout.slots, painted, "an empty state must keep the last painted frame")
    }

    /// A strip hidden by the hotkey and shown again while yabai is down has kept
    /// segments but no frame on screen. The empty-state guard must present them.
    func testStripHiddenDuringDowntimeComesBackWithTheKeptSegments() throws {
        guard NSScreen.main != nil else {
            throw XCTSkip("no display available in this environment")
        }
        _ = NSApplication.shared
        let yabai = MockYabaiService()
        yabai.buildGridStateResult = GridState(
            config: .default,
            spaces: [1, 2].map {
                YabaiSpace(id: $0, index: $0, display: 1, hasFocus: $0 == 1, isVisible: true, label: nil)
            },
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: 1
        )
        let controller = GlyphStripPanelController(
            yabaiService: yabai,
            themeStore: makeTemporaryThemeStore()
        )
        controller.update(config: enabledConfig())
        controller.present()

        // The first pass waits for the off-main font load.
        let deadline = Date().addingTimeInterval(2)
        while controller.layout.slots.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        controller.pendingRefresh?.cancel()
        let painted = controller.layout.slots
        XCTAssertFalse(painted.isEmpty, "the strip must paint spaces while yabai is up")
        let panel = try XCTUnwrap(controller.panel)

        controller.toggleVisibilityByHotkey()
        let hideDeadline = Date().addingTimeInterval(1)
        while panel.isVisible, Date() < hideDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(panel.isVisible)

        // Yabai is down: every state from here on reports no spaces.
        yabai.buildGridStateResult = GridState(
            config: .default,
            spaces: [],
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: nil
        )
        controller.toggleVisibilityByHotkey()

        let showDeadline = Date().addingTimeInterval(2)
        while !panel.isVisible, Date() < showDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(panel.isVisible, "showing the strip during downtime must present it")
        XCTAssertEqual(controller.layout.slots, painted, "the kept frame is reused, not repainted empty")
    }

    func testVerticallyStackedQuartzDisplaysResolveToAppKitScreens() {
        let quartzMaxY: CGFloat = 1080
        let appKitFrames = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 0, y: -1080, width: 1920, height: 1080),
        ]
        let topQuartz = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let bottomQuartz = CGRect(x: 0, y: 1080, width: 1920, height: 1080)

        let topAppKit = ScreenContext.appKitFrame(
            forQuartzFrame: topQuartz,
            quartzMaxY: quartzMaxY
        )
        let bottomAppKit = ScreenContext.appKitFrame(
            forQuartzFrame: bottomQuartz,
            quartzMaxY: quartzMaxY
        )

        XCTAssertEqual(topAppKit, appKitFrames[0])
        XCTAssertEqual(bottomAppKit, appKitFrames[1])
        XCTAssertEqual(
            ScreenContext.bestScreenIndex(for: topAppKit, screenFrames: appKitFrames),
            0
        )
        XCTAssertEqual(
            ScreenContext.bestScreenIndex(for: bottomAppKit, screenFrames: appKitFrames),
            1
        )
        // The raw Quartz frame does not live in AppKit's coordinate space.
        XCTAssertFalse(appKitFrames[0].intersects(bottomQuartz))
    }

    func testMenuBarRowUsesNotchSafeAreaInset() {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let visible = CGRect(x: 0, y: 0, width: 1710, height: 1075)

        let notched = ScreenContext.menuBarRow(
            screenFrame: screen,
            visibleFrame: visible,
            safeAreaTop: 37.5
        )
        XCTAssertEqual(notched, CGRect(x: 0, y: 1074.5, width: 1710, height: 37.5))

        let plainVisible = CGRect(x: 0, y: 0, width: 1710, height: 1088)
        let plain = ScreenContext.menuBarRow(
            screenFrame: screen,
            visibleFrame: plainVisible,
            safeAreaTop: 0
        )
        XCTAssertEqual(plain, CGRect(x: 0, y: 1088, width: 1710, height: 24))
    }

    func testAccessibilityLabelsDescribeSpacesAppsAndControls() {
        XCTAssertEqual(
            GlyphStrip.accessibilityLabel(
                for: .init(spaceIndex: 3, runs: [.index("3"), .app("Safari"), .app("Terminal")]),
                focused: true
            ),
            "Space 3, Safari, Terminal, Current space"
        )
        XCTAssertEqual(
            GlyphStrip.accessibilityLabel(
                for: .init(spaceIndex: 2, runs: [.index("2"), .placeholder]),
                focused: false
            ),
            "Space 2, Empty"
        )
        XCTAssertEqual(
            GlyphStrip.accessibilityLabel(for: .init(spaceIndex: 4, runs: [.add]), focused: false),
            "Add space"
        )
        XCTAssertEqual(
            GlyphStrip.accessibilityLabel(for: .init(spaceIndex: nil, runs: [.separator]), focused: false),
            "Display separator"
        )
    }

    func testAccessibilityLabelIncludesTheSpaceNameWhenShown() {
        XCTAssertEqual(
            GlyphStrip.accessibilityLabel(
                for: .init(spaceIndex: 3, runs: [.index("3 Web"), .app("Safari")]),
                focused: false,
                spaceName: "Web"
            ),
            "Space 3 — Web, Safari"
        )
    }

    func testAccessibilityNameUsesTheSameTrimAndBlankRuleAsThePaintedLabel() {
        var options = GlyphStrip.Options(.default)
        options.spaceLabelStyle = .names
        options.spaceNames = [1: "  Web  ", 2: "   "]

        XCTAssertEqual(GlyphStrip.spaceName(for: 1, options: options), "Web",
                       "VoiceOver must not read the padding the strip trims")
        XCTAssertNil(GlyphStrip.spaceName(for: 2, options: options),
                     "a blank name paints the number, so VoiceOver must not read it either")

        options.spaceLabelStyle = .numbers
        XCTAssertNil(GlyphStrip.spaceName(for: 1, options: options),
                     "numbers mode never exposes a name")
    }
}
