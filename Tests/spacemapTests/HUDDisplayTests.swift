import XCTest
import CoreGraphics
import AppKit
@testable import spacemap


final class HUDDisplayMockDelegate: HUDDisplayDelegate {
    private(set) var renderCalled = false
    private(set) var renderState: GridState?
    private(set) var updateCellFramesCalled = false
    private(set) var updateCellFramesValue: GridState?
    private(set) var showCalled = false
    private(set) var hideCalled = false

    func render(state: GridState) {
        renderCalled = true
        renderState = state
    }

    func updateCellFrames(state: GridState) {
        updateCellFramesCalled = true
        updateCellFramesValue = state
    }

    func show() {
        showCalled = true
    }

    func hide() {
        hideCalled = true
    }

    func reset() {
        renderCalled = false
        renderState = nil
        updateCellFramesCalled = false
        updateCellFramesValue = nil
        showCalled = false
        hideCalled = false
    }
}

final class HUDDisplayTests: XCTestCase {


    private var delegate: HUDDisplayMockDelegate!
    private var hudDisplay: HUDDisplay!

    private func makeHUDDisplay() -> HUDDisplay {
        HUDDisplay(yabaiService: MockYabaiService())
    }

    private func cannedState(
        config: GridConfig = .default,
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


    func testShowAndHideNotifyDelegate() {
        hudDisplay.show()
        XCTAssertTrue(delegate.showCalled)

        hudDisplay.hide()
        XCTAssertTrue(delegate.hideCalled)
    }

    func testRenderInEitherMultiMonitorModePublishesCellFrames() {
        for mode in [MultiMonitorHUDMode.unified, .separate] {
            delegate.reset()
            var config = GridConfig.default
            config.multiMonitorHUDMode = mode

            hudDisplay.render(state: cannedState(config: config))

            XCTAssertTrue(delegate.updateCellFramesCalled, "mode: \(mode)")
        }
    }

    func testUpdateCellFramesCallsDelegateUpdateCellFrames() {
        let state = cannedState()

        hudDisplay.updateCellFrames(state: state)

        XCTAssertTrue(delegate.updateCellFramesCalled,
            "updateCellFrames() should call delegate.updateCellFrames()")
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
            var config = GridConfig.default
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
        var config = GridConfig.default
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
        var config = GridConfig.default
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
        var config = GridConfig.default
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
        var config = GridConfig.default
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
        var config = GridConfig.default
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
        var config = GridConfig.default
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
        let origin = HUDPosition.custom(x: Double(normalized.x), y: Double(normalized.y))
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

        XCTAssertEqual(HUDDisplay.bestScreenIndex(for: screens[1], screenFrames: screens), 1)
        XCTAssertNil(HUDDisplay.bestScreenIndex(
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
        let identifier = HUDDisplay.displayIdentifier(for: main)

        XCTAssertFalse(identifier.isEmpty)
        XCTAssertTrue(
            HUDDisplay.screen(matchingIdentifier: identifier, screens: [main]) === main
        )
        XCTAssertNil(HUDDisplay.screen(matchingIdentifier: "missing-display", screens: [main]))
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
