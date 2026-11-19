import XCTest
import CoreGraphics
import AppKit
@testable import spacemap


/// Test double for the display's delegate seam. Only the frame publication
/// that real callers consume is recorded.
final class HUDDisplayMockDelegate: HUDDisplayDelegate {
    private(set) var updateCellFramesCalled = false

    func render(state: GridState) {}

    func updateCellFrames(state: GridState) {
        updateCellFramesCalled = true
    }

    func show() {}

    func hide() {}

    func reset() {
        updateCellFramesCalled = false
    }
}

final class HUDDisplayTests: XCTestCase {


    private var delegate: HUDDisplayMockDelegate!
    private var hudDisplay: HUDDisplay!

    private func makeHUDDisplay() -> HUDDisplay {
        HUDDisplay(yabaiService: MockYabaiService(), themeStore: makeTemporaryThemeStore())
    }

    private func cannedState(
        config: SpacemapConfig = .default,
        spaces: [YabaiSpace] = [],
        windows: [YabaiWindow] = [],
        displays: [YabaiDisplay] = []
    ) -> GridState {
        GridState(
            config: config,
            spaces: spaces,
            windows: windows,
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: nil,
            displays: displays
        )
    }

    override func setUp() {
        super.setUp()
        delegate = HUDDisplayMockDelegate()
        hudDisplay = makeHUDDisplay()
        hudDisplay.delegate = delegate
    }

    override func tearDown() {
        hudDisplay = nil
        delegate = nil
        super.tearDown()
    }


    func testRenderInEitherMultiMonitorModePublishesCellFrames() {
        for mode in [MultiMonitorHUDMode.unified, .separate] {
            delegate.reset()
            var config = SpacemapConfig.default
            config.multiMonitorHUDMode = mode

            hudDisplay.render(state: cannedState(config: config))

            XCTAssertTrue(delegate.updateCellFramesCalled, "mode: \(mode)")
        }
    }

    func testPreloadIconPolicyMatchesStyleAndIconStrip() {
        let cases: [(CellStyle, Bool, GlyphStripIconSource, Bool)] = [
            (.icons, false, .nativeIcons, true),
            (.hybrid, false, .nativeIcons, true),
            (.rects, true, .nativeIcons, true),
            (.rects, false, .nativeIcons, false),
            (.icons, true, .sbarFont, false)
        ]
        for (style, showIconStrip, iconSource, expected) in cases {
            var config = SpacemapConfig.default
            config.cellStyle = style
            config.showIconStrip = showIconStrip
            config.hudIconSource = iconSource

            XCTAssertEqual(
                HUDDisplay.shouldPreloadIcons(config: config),
                expected,
                "style \(style), icon strip \(showIconStrip), source \(iconSource)"
            )
        }
    }

    func testRefreshThumbnailsOnlyRunsForThumbnailStyle() throws {
        guard #available(macOS 14.0, *) else {
            throw XCTSkip("thumbnail refresh requires macOS 14")
        }
        var config = SpacemapConfig.default
        config.cellStyle = .thumbnails
        hudDisplay.updateConfig(config)

        hudDisplay.refreshThumbnails(state: cannedState(config: config))
        XCTAssertEqual(hudDisplay.thumbnailRefreshCount, 1)

        config.cellStyle = .rects
        hudDisplay.updateConfig(config)
        hudDisplay.refreshThumbnails(state: cannedState(config: config))
        XCTAssertEqual(hudDisplay.thumbnailRefreshCount, 1,
                       "non-thumbnail styles must not start captures")
    }

    func testUpdateStateCreatesTheUnifiedPanel() {
        let state = cannedState()
        hudDisplay.screenFramesOverride = [CGRect(x: 0, y: 0, width: 1440, height: 900)]

        hudDisplay.updateState(state)

        XCTAssertNotNil(hudDisplay.unifiedPanel,
            "updateState must run the same panel-sync path as render")
    }

    func testUpdateStateRemovesStaleDisplayPanels() {
        var config = SpacemapConfig.default
        config.multiMonitorHUDMode = .unified
        config.unifiedHUDVisibility = .all
        hudDisplay.screenFramesOverride = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        ]
        let displayOne = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil)
        ]
        let displayTwo = [
            YabaiSpace(id: 2, index: 2, display: 2, hasFocus: true, isVisible: true, label: nil)
        ]

        hudDisplay.updateState(cannedState(config: config, spaces: displayOne))
        XCTAssertEqual(hudDisplay.displayPanelIndices, [1])

        hudDisplay.updateState(cannedState(config: config, spaces: displayTwo))
        XCTAssertEqual(hudDisplay.displayPanelIndices, [2],
            "a display that no longer has spaces must lose its panel")
    }

    func testUpdateStateDedupesMirroredScreenFrames() {
        var config = SpacemapConfig.default
        config.multiMonitorHUDMode = .unified
        config.unifiedHUDVisibility = .all
        let mirrored = CGRect(x: 0, y: 0, width: 1440, height: 900)
        hudDisplay.screenFramesOverride = [mirrored, mirrored]
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 2, hasFocus: false, isVisible: true, label: nil)
        ]

        hudDisplay.updateState(cannedState(config: config, spaces: spaces))

        XCTAssertEqual(hudDisplay.displayPanelIndices, [1],
            "two displays resolving to one physical screen must not stack panels")
    }

    func testUpdateStateCreatesPanelsInSeparateMode() {
        var config = SpacemapConfig.default
        config.multiMonitorHUDMode = .separate
        config.separateHUDVisibility = .all
        hudDisplay.screenFramesOverride = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: false, label: nil)
        ]

        hudDisplay.updateState(cannedState(config: config, spaces: spaces))

        XCTAssertEqual(hudDisplay.displayPanelIndices, [1])
    }

    func testHideClearsHoverAndRenderedStateButKeepsPanels() throws {
        let state = cannedState()
        hudDisplay.screenFramesOverride = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        hudDisplay.updateState(state)
        let panel = try XCTUnwrap(hudDisplay.unifiedPanel)
        hudDisplay.updateHoveredCell(3)

        hudDisplay.hide()

        XCTAssertNil(hudDisplay.hoveredCell, "hide must clear drop-target state")
        XCTAssertNil(hudDisplay.hoverState.cell, "hide must clear the observable hover")
        XCTAssertNil(hudDisplay.renderedState, "hide must drop the rendered state")
        XCTAssertTrue(hudDisplay.unifiedPanel === panel,
            "the panel must survive hide so show does not rebuild it")
        let deadline = Date().addingTimeInterval(1)
        while panel.isVisible, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertFalse(panel.isVisible, "the retained panel must be ordered out")
    }

    func testUpdateHoveredCellDoesNoRenderOrPreloadWork() {
        var config = SpacemapConfig.default
        config.cellStyle = .thumbnails
        hudDisplay.updateConfig(config)
        hudDisplay.screenFramesOverride = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        hudDisplay.updateState(cannedState(config: config))
        let renders = hudDisplay.fullRenderCount
        let iconPreloads = hudDisplay.iconPreloadCount
        let thumbnailRefreshes = hudDisplay.thumbnailRefreshCount

        hudDisplay.updateHoveredCell(2)

        XCTAssertEqual(hudDisplay.hoveredCell, 2)
        XCTAssertEqual(hudDisplay.hoverState.cell, 2)
        XCTAssertEqual(hudDisplay.fullRenderCount, renders, "hover must not re-render")
        XCTAssertEqual(hudDisplay.iconPreloadCount, iconPreloads, "hover must not preload icons")
        XCTAssertEqual(hudDisplay.thumbnailRefreshCount, thumbnailRefreshes,
            "hover must not refresh thumbnails")

        // Repeating the same hover is a no-op (coalesces repeat deliveries).
        hudDisplay.updateHoveredCell(2)
        XCTAssertEqual(hudDisplay.hoveredCell, 2)
    }

    func testPrewarmOnlyWarmsIconsNeverCapturesThumbnails() {
        var config = SpacemapConfig.default
        config.cellStyle = .thumbnails
        hudDisplay.updateConfig(config)

        hudDisplay.prewarm(state: cannedState(config: config, spaces: [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil)
        ]))

        XCTAssertEqual(hudDisplay.thumbnailRefreshCount, 0,
            "launch warmup must not run ScreenCaptureKit captures")
    }

    func testNormalizedPositionRoundTripsExactlyThroughCustomPoint() throws {
        let screenFrame = CGRect(x: 100, y: 50, width: 1600, height: 1000)
        let panelSize = CGSize(width: 420, height: 260)
        let panelFrame = CGRect(x: 500, y: 300, width: panelSize.width, height: panelSize.height)

        let normalized = try XCTUnwrap(HUDDisplay.normalizedPosition(
            panelFrame: panelFrame,
            screenFrame: screenFrame
        ))
        let origin = HUDPosition.custom(x: Double(normalized.x), y: Double(normalized.y), screen: nil)
            .point(for: panelSize, screen: screenFrame)

        XCTAssertEqual(origin.x, panelFrame.minX, accuracy: 0.0001)
        XCTAssertEqual(origin.y, panelFrame.minY, accuracy: 0.0001)
    }

    func testNormalizedPositionRejectsPanelLargerThanScreen() {
        XCTAssertNil(HUDDisplay.normalizedPosition(
            panelFrame: CGRect(x: 0, y: 0, width: 2000, height: 900),
            screenFrame: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        ))
    }

    func testBestScreenIndexMatchesExactFrameAndRejectsStaleFrame() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        ]

        XCTAssertEqual(ScreenContext.bestScreenIndex(for: screens[1], screenFrames: screens), 1)
        XCTAssertNil(ScreenContext.bestScreenIndex(
            for: CGRect(x: 5000, y: 5000, width: 1920, height: 1080),
            screenFrames: screens
        ), "a display frame matching no screen must be rejected")
    }

    func testDeduplicatedAssignmentsDropsMirroredScreens() {
        let first = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let second = CGRect(x: 1920, y: 0, width: 2560, height: 1440)

        let assignments = HUDDisplay.deduplicatedAssignments([
            (displayIndex: 1, screenFrame: first),
            (displayIndex: 2, screenFrame: first),
            (displayIndex: 3, screenFrame: second)
        ])

        XCTAssertEqual(assignments.map(\.displayIndex), [1, 3])
    }

    func testDisplayIdentifierRoundTripsToItsScreen() throws {
        guard let main = NSScreen.main else {
            throw XCTSkip("no display available in this environment")
        }
        let identifier = ScreenContext.displayIdentifier(for: main)

        XCTAssertFalse(identifier.isEmpty)
        XCTAssertTrue(
            ScreenContext.screen(matchingIdentifier: identifier, screens: [main]) === main
        )
        XCTAssertNil(ScreenContext.screen(matchingIdentifier: "missing-display", screens: [main]))
        XCTAssertNil(ScreenContext.screen(matchingIdentifier: "", screens: [main]),
                     "an unpaired custom position must not match a screen")
    }

    /// A finished drag stores the fraction pair with the display it landed on,
    /// so a restore replays the exact origin instead of combining a new screen
    /// with an old fraction.
    func testCustomPositionCarriesFractionsAndScreenIdentity() throws {
        guard let main = NSScreen.main else {
            throw XCTSkip("no display available in this environment")
        }
        let screenFrame = CGRect(x: 100, y: 50, width: 1600, height: 1000)
        let panelSize = CGSize(width: 420, height: 260)
        let panelFrame = CGRect(x: 500, y: 300, width: panelSize.width, height: panelSize.height)

        let position = try XCTUnwrap(HUDDisplay.customPosition(
            panelFrame: panelFrame,
            screenFrame: screenFrame,
            screen: main
        ))

        XCTAssertEqual(position.screenIdentifier, ScreenContext.displayIdentifier(for: main))
        let origin = position.point(for: panelSize, screen: screenFrame)
        XCTAssertEqual(origin.x, panelFrame.minX, accuracy: 0.0001)
        XCTAssertEqual(origin.y, panelFrame.minY, accuracy: 0.0001)
    }

    /// Dragging the HUD past a screen edge yields a fraction outside 0...1.
    /// The decoder rejects such a value and resets the position to Center, so
    /// the saved fraction must clamp and survive the reload unchanged.
    func testCustomPositionClampsPanelDraggedPastScreenEdge() throws {
        guard let main = NSScreen.main else {
            throw XCTSkip("no display available in this environment")
        }
        let screenFrame = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let panelFrame = CGRect(x: -120, y: 940, width: 420, height: 260)

        let position = try XCTUnwrap(HUDDisplay.customPosition(
            panelFrame: panelFrame,
            screenFrame: screenFrame,
            screen: main
        ))
        guard case .custom(let x, let y, _) = position else {
            return XCTFail("expected a custom position")
        }
        XCTAssertEqual(x, 0, "a panel dragged off the left edge clamps to 0")
        XCTAssertEqual(y, 1, "a panel dragged off the top edge clamps to 1")

        var config = SpacemapConfig.default
        config.hudPosition = position
        let (reread, needsRepair) = try TOMLParser.parse(
            ConfigLoader.tomlConfigString(from: config, includeHeaderComments: false)
        )
        XCTAssertFalse(needsRepair)
        XCTAssertEqual(reread.hudPosition, position, "clamped fractions must re-decode unchanged")
    }

    /// A strip straddling two displays belongs to the one holding most of it,
    /// so a drag saves the display it visibly sits on instead of the first one
    /// it touches.
    func testLargestIntersectionPicksMajorityScreen() {
        let left = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let right = CGRect(x: 1600, y: 0, width: 1200, height: 1000)

        // 200 points over the left display, 300 over the right one.
        let straddling = CGRect(x: 1400, y: 400, width: 500, height: 60)
        XCTAssertEqual(
            ScreenContext.largestIntersection(screenFrames: [left, right], frame: straddling),
            1
        )
        XCTAssertNil(ScreenContext.largestIntersection(screenFrames: [], frame: straddling))
        XCTAssertNil(
            ScreenContext.largestIntersection(
                screenFrames: [left],
                frame: CGRect(x: 4000, y: 4000, width: 100, height: 60)
            ),
            "a frame on no screen has no majority"
        )
    }

    func testRenderLeavesPanelOriginAloneWhilePanelDragIsActive() throws {
        hudDisplay.screenFramesOverride = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        var dragging = false
        hudDisplay.isPanelDragging = { dragging }
        let state = cannedState()
        hudDisplay.updateState(state)
        let panel = try XCTUnwrap(hudDisplay.unifiedPanel)
        let origin = panel.frame.origin

        // Simulate the user dragging the panel away from its computed origin.
        panel.setFrameOrigin(CGPoint(x: origin.x + 40, y: origin.y + 20))
        let dragOrigin = panel.frame.origin
        dragging = true
        hudDisplay.updateState(state)

        XCTAssertEqual(panel.frame.origin, dragOrigin,
            "a render mid-drag must not snap the panel back")

        dragging = false
        hudDisplay.updateState(state)
        XCTAssertEqual(panel.frame.origin, origin,
            "the computed position returns once the drag ends")
    }
}
