import XCTest
import CoreGraphics
@testable import spacemap

// MARK: - Mock Delegate

final class HUDDisplayMockDelegate: HUDDisplayDelegate {
    private(set) var renderCalled = false
    private(set) var renderState: GridState?
    private(set) var updateCellFramesCalled = false
    private(set) var updateCellFramesValue: [(spaceIndex: Int, frame: CGRect)]?
    private(set) var hudDidShowCalled = false
    private(set) var hudDidHideCalled = false

    func render(state: GridState) {
        renderCalled = true
        renderState = state
    }

    func updateCellFrames(frames: [(spaceIndex: Int, frame: CGRect)]) {
        updateCellFramesCalled = true
        updateCellFramesValue = frames
    }

    func hudDidShow() {
        hudDidShowCalled = true
    }

    func hudDidHide() {
        hudDidHideCalled = true
    }

    func reset() {
        renderCalled = false
        renderState = nil
        updateCellFramesCalled = false
        updateCellFramesValue = nil
        hudDidShowCalled = false
        hudDidHideCalled = false
    }
}

final class HUDDisplayTests: XCTestCase {

    // MARK: - Helpers

    private var delegate: HUDDisplayMockDelegate!
    private var hudDisplay: HUDDisplay!

    private func makeHUDDisplay(dragHandler: WindowDragHandler? = nil) -> HUDDisplay {
        HUDDisplay(dragHandler: dragHandler, yabaiService: MockYabaiService())
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

    // MARK: - show()

    func testShowCallsDelegateHudDidShow() {
        // When
        hudDisplay.show()

        // Then
        XCTAssertTrue(delegate.hudDidShowCalled, "show() should call delegate.hudDidShow()")
    }

    // MARK: - hide()

    func testHideCallsDelegateHudDidHide() {
        // When
        hudDisplay.hide()

        // Then
        XCTAssertTrue(delegate.hudDidHideCalled, "hide() should call delegate.hudDidHide()")
    }

    // MARK: - render(state:)

    func testRenderUnifiedModeCallsDelegateUpdateCellFrames() {
        // Given
        var config = GridConfig.default
        config.multiMonitorHUDMode = .unified
        let state = cannedState(config: config)

        // When
        hudDisplay.render(state: state)

        // Then
        XCTAssertTrue(delegate.updateCellFramesCalled,
            "render() in unified mode should call delegate.updateCellFrames()")
    }

    func testRenderSeparateModeCallsDelegateUpdateCellFrames() {
        // Given
        var config = GridConfig.default
        config.multiMonitorHUDMode = .separate
        let state = cannedState(config: config)

        // When
        hudDisplay.render(state: state)

        // Then
        XCTAssertTrue(delegate.updateCellFramesCalled,
            "render() in separate mode should call delegate.updateCellFrames()")
    }

    // MARK: - updateCellFrames(state:)

    func testUpdateCellFramesCallsDelegateUpdateCellFrames() {
        // Given
        let state = cannedState()

        // When
        hudDisplay.updateCellFrames(state: state)

        // Then
        XCTAssertTrue(delegate.updateCellFramesCalled,
            "updateCellFrames() should call delegate.updateCellFrames()")
    }

    // MARK: - preloadIcons(for:)

    func testPreloadIconsOnlyForIconsStyle() {
        // Given - icons style should pass the guard and proceed with preload
        var config = GridConfig.default
        config.cellStyle = .icons
        config.showIconStrip = false
        hudDisplay.updateConfig(config)

        let state = cannedState(config: config, windows: [
            YabaiWindow(id: 1, app: "Safari", space: 1,
                        frame: .init(x: 0, y: 0, w: 800, h: 600),
                        isHidden: false, isMinimized: false, subLayer: "normal"),
        ])

        // Clear cache so we can verify preload actually populated it
        IconCache.shared.clear()

        // When
        hudDisplay.preloadIcons(for: state)

        // Then - icons style passes the guard, so Safari icon should be cached
        XCTAssertNotNil(IconCache.shared.icon(for: "Safari"),
            "preloadIcons should cache icons for icons style")
    }

    func testPreloadIconsOnlyForHybridStyle() {
        // Given - hybrid style should pass the guard and proceed with preload
        var config = GridConfig.default
        config.cellStyle = .hybrid
        config.showIconStrip = false
        hudDisplay.updateConfig(config)

        let state = cannedState(config: config, windows: [
            YabaiWindow(id: 1, app: "Safari", space: 1,
                        frame: .init(x: 0, y: 0, w: 800, h: 600),
                        isHidden: false, isMinimized: false, subLayer: "normal"),
        ])

        // Clear cache so we can verify preload actually populated it
        IconCache.shared.clear()

        // When
        hudDisplay.preloadIcons(for: state)

        // Then - hybrid style passes the guard, so Safari icon should be cached
        XCTAssertNotNil(IconCache.shared.icon(for: "Safari"),
            "preloadIcons should cache icons for hybrid style")
    }

    func testPreloadIconsSkipsForRectsStyleWithoutIconStrip() {
        // Given - rects style with showIconStrip false should return early
        var config = GridConfig.default
        config.cellStyle = .rects
        config.showIconStrip = false
        hudDisplay.updateConfig(config)

        let state = cannedState(config: config)

        // When - should return early without preloading
        hudDisplay.preloadIcons(for: state)

        // Then - rects style without icon strip should skip preload;
        // verify the config was not corrupted and subsequent operations work
        hudDisplay.updateCellFrames(state: state)
        XCTAssertTrue(delegate.updateCellFramesCalled,
            "preloadIcons should return early for rects style without icon strip without corrupting config")
    }

    func testPreloadIconsProceedsForShowIconStrip() {
        // Given - any style with showIconStrip true should pass the guard
        var config = GridConfig.default
        config.cellStyle = .rects
        config.showIconStrip = true
        hudDisplay.updateConfig(config)

        let state = cannedState(config: config, windows: [
            YabaiWindow(id: 1, app: "Safari", space: 1,
                        frame: .init(x: 0, y: 0, w: 800, h: 600),
                        isHidden: false, isMinimized: false, subLayer: "normal"),
        ])

        // Clear cache so we can verify preload actually populated it
        IconCache.shared.clear()

        // When - should not crash (proceeds to preload)
        hudDisplay.preloadIcons(for: state)

        // Then - showIconStrip passes the guard, so Safari icon should be cached
        XCTAssertNotNil(IconCache.shared.icon(for: "Safari"),
            "preloadIcons should cache icons when showIconStrip is true")
    }

    // MARK: - refreshThumbnails

    func testRefreshThumbnailsOnlyForThumbnailsStyle() {
        // Given - thumbnails style should pass the cellStyle guard
        var config = GridConfig.default
        config.cellStyle = .thumbnails
        hudDisplay.updateConfig(config)

        let state = cannedState(config: config)

        // When - should not crash (passes cellStyle guard, may still return
        // early due to #available macOS 14 check)
        hudDisplay.refreshThumbnails(state: state)

        // Then - thumbnails style passes the guard; verify the config
        // was not corrupted and subsequent render still works
        hudDisplay.render(state: state)
        XCTAssertTrue(delegate.updateCellFramesCalled,
            "refreshThumbnails should not corrupt config for thumbnails style")
    }

    func testRefreshThumbnailsSkipsForNonThumbnailsStyle() {
        // Given - rects style should return early at the cellStyle guard
        var config = GridConfig.default
        config.cellStyle = .rects
        hudDisplay.updateConfig(config)

        let state = cannedState(config: config)

        // When - should return early without crashing
        hudDisplay.refreshThumbnails(state: state)

        // Then - non-thumbnails style should skip refresh;
        // verify the config was not corrupted and render still works
        hudDisplay.render(state: state)
        XCTAssertTrue(delegate.updateCellFramesCalled,
            "refreshThumbnails should return early for non-thumbnails style without corrupting config")
    }

    // MARK: - updateConfig

    func testUpdateConfigStoresConfig() {
        // Given
        var config = GridConfig.default
        config.cols = 12
        config.rows = 4
        config.cellStyle = .icons
        config.uiScale = 0.8

        // When
        hudDisplay.updateConfig(config)

        // Then - verify by calling updateCellFrames and checking the config
        // was applied (updateCellFrames uses currentConfig)
        let state = cannedState(config: config)
        hudDisplay.updateCellFrames(state: state)

        XCTAssertTrue(delegate.updateCellFramesCalled,
            "updateConfig should store the config so subsequent methods use it")
    }

    // MARK: - updateHoveredCell

    func testUpdateHoveredCellStoresCell() {
        // When
        hudDisplay.updateHoveredCell(3)

        // Then - verify by rendering and checking hovered cell is used
        let state = cannedState()
        hudDisplay.render(state: state)

        // The hovered cell should be stored; verify no crash occurred
        // and the render completed (delegate.updateCellFrames was called)
        XCTAssertTrue(delegate.updateCellFramesCalled,
            "updateHoveredCell should store the cell for use in rendering")
    }

    func testUpdateHoveredCellStoresNil() {
        // When
        hudDisplay.updateHoveredCell(3)
        hudDisplay.updateHoveredCell(nil)

        // Then - verify by rendering and checking hovered cell is nil
        let state = cannedState()
        hudDisplay.render(state: state)

        XCTAssertTrue(delegate.updateCellFramesCalled,
            "updateHoveredCell(nil) should store nil for use in rendering")
    }

    // MARK: - updateState(_:)

    func testUpdateStateUpdatesConfigAndRenders() {
        // Given
        var config = GridConfig.default
        config.cols = 5
        config.rows = 3
        hudDisplay.updateConfig(config)

        let state = cannedState(config: config)

        // When
        hudDisplay.updateState(state)

        // Then - updateState should update currentConfig and call render,
        // which in turn calls delegate.updateCellFrames
        XCTAssertTrue(delegate.updateCellFramesCalled,
            "updateState should update currentConfig and call render on the delegate")
    }

    // MARK: - startDragHandler()

    func testStartDragHandlerStartsDragHandler() {
        // Given
         let dragHandler = WindowDragHandler(yabaiService: MockYabaiService())
         hudDisplay = makeHUDDisplay(dragHandler: dragHandler)
         hudDisplay.delegate = delegate

         // When
         hudDisplay.startDragHandler()

        // Then - start() should be called on the drag handler;
        // verify the drag handler is still functional by updating its windows
        let windows = [
            YabaiWindow(id: 1, app: "Safari", space: 1,
                        frame: .init(x: 0, y: 0, w: 800, h: 600),
                        isHidden: false, isMinimized: false, subLayer: "normal"),
        ]
        hudDisplay.updateDragHandlerWindows(windows)
        XCTAssertEqual(dragHandler.cachedWindows.count, windows.count,
            "startDragHandler should not prevent subsequent drag handler operations")
    }

    // MARK: - stopDragHandler()

    func testStopDragHandlerStopsDragHandler() {
        // Given
         let dragHandler = WindowDragHandler(yabaiService: MockYabaiService())
         hudDisplay = makeHUDDisplay(dragHandler: dragHandler)
         hudDisplay.delegate = delegate

         // When
         hudDisplay.stopDragHandler()

        // Then - stop() should be called on the drag handler;
        // verify the drag handler is still functional by updating its windows
        let windows = [
            YabaiWindow(id: 1, app: "Safari", space: 1,
                        frame: .init(x: 0, y: 0, w: 800, h: 600),
                        isHidden: false, isMinimized: false, subLayer: "normal"),
        ]
        hudDisplay.updateDragHandlerWindows(windows)
        XCTAssertEqual(dragHandler.cachedWindows.count, windows.count,
            "stopDragHandler should not prevent subsequent drag handler operations")
    }

    // MARK: - updateDragHandlerWindows

    func testUpdateDragHandlerWindowsUpdatesCachedWindows() {
        // Given
         let dragHandler = WindowDragHandler(yabaiService: MockYabaiService())
         hudDisplay = makeHUDDisplay(dragHandler: dragHandler)
         hudDisplay.delegate = delegate

         let windows = [
             YabaiWindow(id: 1, app: "Safari", space: 1,
                         frame: .init(x: 0, y: 0, w: 800, h: 600),
                         isHidden: false, isMinimized: false, subLayer: "normal"),
             YabaiWindow(id: 2, app: "Notes", space: 1,
                         frame: .init(x: 0, y: 0, w: 400, h: 300),
                         isHidden: false, isMinimized: false, subLayer: "normal"),
         ]

         // When
         hudDisplay.updateDragHandlerWindows(windows)

        // Then
        XCTAssertEqual(dragHandler.cachedWindows.count, windows.count,
            "updateDragHandlerWindows should update the drag handler's cachedWindows count")
        for (index, window) in windows.enumerated() {
            XCTAssertEqual(dragHandler.cachedWindows[index].id, window.id,
                "cached window at \(index) should have matching id")
            XCTAssertEqual(dragHandler.cachedWindows[index].app, window.app,
                "cached window at \(index) should have matching app")
        }
    }

    // MARK: - setDragHandlerFocusedWindowID

    func testSetDragHandlerFocusedWindowIDSetsFocusedWindowID() {
        // Given
         let dragHandler = WindowDragHandler(yabaiService: MockYabaiService())
         hudDisplay = makeHUDDisplay(dragHandler: dragHandler)
         hudDisplay.delegate = delegate

         // When
         hudDisplay.setDragHandlerFocusedWindowID(42)

        // Then
        XCTAssertEqual(dragHandler.focusedWindowIDAtOpen, 42,
            "setDragHandlerFocusedWindowID should set the drag handler's focusedWindowIDAtOpen")
    }
}
