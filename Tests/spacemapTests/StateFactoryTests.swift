import XCTest
@testable import spacemap

final class StateFactoryTests: XCTestCase {
    
    func testStateCreation() throws {
        let config = GridConfig.default
        let spaces: [YabaiSpace] = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        let windows: [YabaiWindow] = [
            YabaiWindow(id: 10, app: "Safari", space: 1, frame: .init(x: 0, y: 0, w: 800, h: 600), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 20, app: "Notes", space: 2, frame: .init(x: 0, y: 0, w: 400, h: 300), isHidden: false, isMinimized: false, subLayer: "normal"),
        ]
        let displays: [YabaiDisplay] = [
            YabaiDisplay(index: 1, frame: .init(x: 0, y: 0, w: 2560, h: 1440), hasFocus: true),
        ]
        
        let baseState = GridState(
            config: config,
            spaces: spaces,
            windows: windows,
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: 1,
            displays: displays
        )
        
        let state = StateFactory.state(baseState, withFocusedIndex: 2)
        
        XCTAssertNotNil(state, "State should be created successfully")
        XCTAssertEqual(state.config.cols, config.cols, "Config should be preserved")
        XCTAssertEqual(state.spaces.count, spaces.count, "Spaces count should be preserved")
        XCTAssertEqual(state.windows.count, windows.count, "Windows count should be preserved")
        XCTAssertEqual(state.focusedIndex, 2, "Focused index should be updated")
        XCTAssertEqual(state.displays.count, displays.count, "Displays count should be preserved")
    }
    
    func testStateWithConfig() throws {
        let config = GridConfig.default
        let newConfig = GridConfig(
            cols: 4, rows: 2, cellStyle: .rects, hotkey: .default,
            pinnedHotkey: HotkeyConfig(key: .none, modifiers: []),
            socketHealthInterval: 60, uiScale: 0.5, autoHideTimeout: 5,
            theme: "default", showMode: .all, multiMonitorHUDMode: .unified,
            unifiedHUDVisibility: .active, separateHUDVisibility: .all,
            displayNavigationWrap: .within, maxSpaces: 16, backgroundAlpha: 0.3,
            mode: .auto, iconScale: 0.5, showSpaceNumbers: true,
            showSpaceNames: true, showIconStrip: true, showMultiAppIcons: false,
            hideMenuBarIcon: false, menuBarDisplayMode: .icon,
            menuBarNearbyCount: 3, spaceNames: [:], useVimKeys: false,
            useArrowKeys: false, hudPosition: .center, customHUDX: 0.5,
            customHUDY: 0.5, showExtraWindows: false,
            focusSpaceOnWindowDrop: .never, focusSpaceOnWindowDropModifier: .command,
            showHUDOnSpaceChange: false,
            updateMode: .notify
        )
        let spaces: [YabaiSpace] = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
        ]
        let windows: [YabaiWindow] = [
            YabaiWindow(id: 10, app: "Safari", space: 1, frame: .init(x: 0, y: 0, w: 800, h: 600), isHidden: false, isMinimized: false, subLayer: "normal"),
        ]
        let displays: [YabaiDisplay] = [
            YabaiDisplay(index: 1, frame: .init(x: 0, y: 0, w: 2560, h: 1440), hasFocus: true),
        ]
        
        let baseState = GridState(
            config: config,
            spaces: spaces,
            windows: windows,
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: 1,
            displays: displays
        )
        
        let state = StateFactory.state(baseState, withConfig: newConfig)
        
        XCTAssertNotNil(state, "State should be created successfully")
        XCTAssertEqual(state.config.cols, 4, "Config should be updated")
        XCTAssertEqual(state.spaces.count, spaces.count, "Spaces count should be preserved")
        XCTAssertEqual(state.windows.count, windows.count, "Windows count should be preserved")
        XCTAssertEqual(state.focusedIndex, 1, "Focused index should be preserved")
    }
    
    func testEmptyStateCreation() throws {
        let state = StateFactory.emptyState(config: GridConfig.default)
        XCTAssertNotNil(state, "Empty state should be created")
        XCTAssertEqual(state.spaces.count, 0, "Empty state should have no spaces")
        XCTAssertEqual(state.windows.count, 0, "Empty state should have no windows")
        XCTAssertEqual(state.focusedIndex, nil, "Empty state should have no focused index")
    }
}