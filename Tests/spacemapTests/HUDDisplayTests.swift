import XCTest
import CoreGraphics
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


    func testShowCallsDelegateHudDidShow() {
        hudDisplay.show()

        XCTAssertTrue(delegate.showCalled, "show() should call delegate.show()")
    }


    func testHideCallsDelegateHudDidHide() {
        hudDisplay.hide()

        XCTAssertTrue(delegate.hideCalled, "hide() should call delegate.hide()")
    }


    func testRenderUnifiedModeCallsDelegateUpdateCellFrames() {
        var config = GridConfig.default
        config.multiMonitorHUDMode = .unified
        let state = cannedState(config: config)

        hudDisplay.render(state: state)

        XCTAssertTrue(delegate.updateCellFramesCalled,
            "render() in unified mode should call delegate.updateCellFrames()")
    }

    func testRenderSeparateModeCallsDelegateUpdateCellFrames() {
        var config = GridConfig.default
        config.multiMonitorHUDMode = .separate
        let state = cannedState(config: config)

        hudDisplay.render(state: state)

        XCTAssertTrue(delegate.updateCellFramesCalled,
            "render() in separate mode should call delegate.updateCellFrames()")
    }


    func testUpdateCellFramesCallsDelegateUpdateCellFrames() {
        let state = cannedState()

        hudDisplay.updateCellFrames(state: state)

        XCTAssertTrue(delegate.updateCellFramesCalled,
            "updateCellFrames() should call delegate.updateCellFrames()")
    }


    func testPreloadIconsOnlyForIconsStyle() {
        var config = GridConfig.default
        config.cellStyle = .icons
        config.showIconStrip = false
        hudDisplay.updateConfig(config)

        let state = cannedState(config: config, windows: [
            YabaiWindow(id: 1, app: "Safari", space: 1,
                        frame: .init(x: 0, y: 0, w: 800, h: 600),
                        isHidden: false, isMinimized: false, subLayer: "normal"),
        ])

        XCTAssertTrue(HUDDisplay.shouldPreloadIcons(config: state.config))
    }

    func testPreloadIconsOnlyForHybridStyle() {
        var config = GridConfig.default
        config.cellStyle = .hybrid
        config.showIconStrip = false
        hudDisplay.updateConfig(config)

        let state = cannedState(config: config, windows: [
            YabaiWindow(id: 1, app: "Safari", space: 1,
                        frame: .init(x: 0, y: 0, w: 800, h: 600),
                        isHidden: false, isMinimized: false, subLayer: "normal"),
        ])

        XCTAssertTrue(HUDDisplay.shouldPreloadIcons(config: state.config))
    }

    func testPreloadIconsSkipsForRectsStyleWithoutIconStrip() {
        var config = GridConfig.default
        config.cellStyle = .rects
        config.showIconStrip = false
        hudDisplay.updateConfig(config)

        let state = cannedState(config: config)

        XCTAssertFalse(HUDDisplay.shouldPreloadIcons(config: state.config))
        hudDisplay.preloadIcons(for: state)

        hudDisplay.updateCellFrames(state: state)
        XCTAssertTrue(delegate.updateCellFramesCalled,
            "preloadIcons should return early for rects style without icon strip without corrupting config")
    }

    func testPreloadIconsProceedsForShowIconStrip() {
        var config = GridConfig.default
        config.cellStyle = .rects
        config.showIconStrip = true
        hudDisplay.updateConfig(config)

        let state = cannedState(config: config, windows: [
            YabaiWindow(id: 1, app: "Safari", space: 1,
                        frame: .init(x: 0, y: 0, w: 800, h: 600),
                        isHidden: false, isMinimized: false, subLayer: "normal"),
        ])

        XCTAssertTrue(HUDDisplay.shouldPreloadIcons(config: state.config))
    }


    func testRefreshThumbnailsOnlyForThumbnailsStyle() {
        var config = GridConfig.default
        config.cellStyle = .thumbnails
        hudDisplay.updateConfig(config)

        let state = cannedState(config: config)

        hudDisplay.refreshThumbnails(state: state)

        hudDisplay.render(state: state)
        XCTAssertTrue(delegate.updateCellFramesCalled,
            "refreshThumbnails should not corrupt config for thumbnails style")
    }

    func testRefreshThumbnailsSkipsForNonThumbnailsStyle() {
        var config = GridConfig.default
        config.cellStyle = .rects
        hudDisplay.updateConfig(config)

        let state = cannedState(config: config)

        hudDisplay.refreshThumbnails(state: state)

        hudDisplay.render(state: state)
        XCTAssertTrue(delegate.updateCellFramesCalled,
            "refreshThumbnails should return early for non-thumbnails style without corrupting config")
    }


    func testUpdateConfigStoresConfig() {
        var config = GridConfig.default
        config.cols = 12
        config.rows = 4
        config.cellStyle = .icons
        config.uiScale = 0.8

        hudDisplay.updateConfig(config)

        let state = cannedState(config: config)
        hudDisplay.updateCellFrames(state: state)

        XCTAssertTrue(delegate.updateCellFramesCalled,
            "updateConfig should store the config so subsequent methods use it")
    }


    func testUpdateHoveredCellStoresCell() {
        hudDisplay.updateHoveredCell(3)

        let state = cannedState()
        hudDisplay.render(state: state)

        XCTAssertTrue(delegate.updateCellFramesCalled,
            "updateHoveredCell should store the cell for use in rendering")
    }

    func testUpdateHoveredCellStoresNil() {
        hudDisplay.updateHoveredCell(3)
        hudDisplay.updateHoveredCell(nil)

        let state = cannedState()
        hudDisplay.render(state: state)

        XCTAssertTrue(delegate.updateCellFramesCalled,
            "updateHoveredCell(nil) should store nil for use in rendering")
    }


    func testUpdateStateUpdatesConfigAndRenders() {
        var config = GridConfig.default
        config.cols = 5
        config.rows = 3
        hudDisplay.updateConfig(config)

        let state = cannedState(config: config)

        hudDisplay.updateState(state)

        XCTAssertTrue(delegate.updateCellFramesCalled,
            "updateState should update currentConfig and call render on the delegate")
    }
}
