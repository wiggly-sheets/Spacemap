import XCTest
import CoreGraphics
@testable import spacemap

final class GridStateTests: ModelTestCase {
    func testGridStateEquality() {
        let a = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: 1)
        let b = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: 1)
        let c = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: 2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testGridStateEqualityIncludesRenderedContentAndConfiguration() {
        let space = YabaiSpace(
            id: 1,
            index: 1,
            display: 1,
            hasFocus: true,
            isVisible: true,
            label: nil
        )
        let window = YabaiWindow(
            id: 1,
            app: "Finder",
            space: 1,
            frame: .init(x: 0, y: 0, w: 100, h: 100),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal"
        )
        let base = GridState(
            config: .default,
            spaces: [],
            windows: [],
            displayBounds: .zero,
            focusedIndex: 1
        )
        let changedSpaces = GridState(
            config: .default,
            spaces: [space],
            windows: [],
            displayBounds: .zero,
            focusedIndex: 1
        )
        let changedWindows = GridState(
            config: .default,
            spaces: [],
            windows: [window],
            displayBounds: .zero,
            focusedIndex: 1
        )
        var changedConfig = SpacemapConfig.default
        changedConfig.uiScale = 0.75
        let changedConfiguration = GridState(
            config: changedConfig,
            spaces: [],
            windows: [],
            displayBounds: .zero,
            focusedIndex: 1
        )

        XCTAssertNotEqual(base, changedSpaces)
        XCTAssertNotEqual(base, changedWindows)
        XCTAssertNotEqual(base, changedConfiguration)
    }

    func testGridStateWindowsEmpty() {
        let state = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertTrue(state.windows(forSpace: 1).isEmpty)
    }

    func testGridStateGroupsSpacesAndUsesOwningDisplayBounds() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 2, hasFocus: false, isVisible: true, label: nil),
            YabaiSpace(id: 3, index: 3, display: 1, hasFocus: false, isVisible: false, label: nil)
        ]
        let displays = [
            YabaiDisplay(index: 1, frame: .init(x: 0, y: 0, w: 1440, h: 900), hasFocus: true),
            YabaiDisplay(index: 2, frame: .init(x: 1440, y: 0, w: 1920, h: 1080), hasFocus: false)
        ]
        let state = GridState(
            config: .default,
            spaces: spaces,
            windows: [],
            displayBounds: .zero,
            focusedIndex: 1,
            displays: displays
        )

        XCTAssertEqual(state.populatedDisplayIndices, [1, 2])
        XCTAssertEqual(state.spaces(forDisplay: 1).map(\.index), [1, 3])
        XCTAssertEqual(state.spaces(forDisplay: 2).map(\.index), [2])
        XCTAssertEqual(state.displayIndex(forSpace: 2), 2)
        XCTAssertEqual(state.displayBounds(forSpace: 2), CGRect(x: 1440, y: 0, width: 1920, height: 1080))
    }


    func testDisplayIndexForMissingSpaceReturnsNil() {
        let state = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertNil(state.displayIndex(forSpace: 99), "Unknown space should return nil")
    }

    func testDisplayBoundsForMissingSpaceReturnsFallback() {
        let fallback = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let state = GridState(config: .default, spaces: [], windows: [], displayBounds: fallback, focusedIndex: nil)
        XCTAssertEqual(state.displayBounds(forSpace: 99), fallback, "Unknown space should return displayBounds")
    }

    func testDisplayBoundsForSpaceWithDisplay() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 2, hasFocus: false, isVisible: true, label: nil),
        ]
        let displays = [
            YabaiDisplay(index: 2, frame: .init(x: 1440, y: 0, w: 1920, h: 1080), hasFocus: false),
        ]
        let state = GridState(
            config: .default,
            spaces: spaces,
            windows: [],
            displayBounds: .zero,
            focusedIndex: nil,
            displays: displays
        )
        XCTAssertEqual(state.displayBounds(forSpace: 1), CGRect(x: 1440, y: 0, width: 1920, height: 1080))
    }

    func testPopulatedDisplayIndicesEmpty() {
        let state = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertTrue(state.populatedDisplayIndices.isEmpty, "No spaces should mean no display indices")
    }

    func testPopulatedDisplayIndicesDeduplicatedAndSorted() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 2, hasFocus: false, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 3, index: 3, display: 2, hasFocus: false, isVisible: true, label: nil),
            YabaiSpace(id: 4, index: 4, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        let state = GridState(config: .default, spaces: spaces, windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertEqual(state.populatedDisplayIndices, [1, 2], "Should be deduplicated and sorted")
    }

    func testSpacesForDisplayEmpty() {
        let state = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertTrue(state.spaces(forDisplay: 1).isEmpty, "No spaces should return empty array")
    }

    func testSpacesForDisplayFilteredAndSorted() {
        let spaces = [
            YabaiSpace(id: 1, index: 3, display: 1, hasFocus: false, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 3, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        let state = GridState(config: .default, spaces: spaces, windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertEqual(state.spaces(forDisplay: 1).map(\.index), [1, 2, 3], "Should be sorted by index")
    }

    func testSpacesForDisplayDifferentDisplay() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 2, hasFocus: false, isVisible: true, label: nil),
        ]
        let state = GridState(config: .default, spaces: spaces, windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertEqual(state.spaces(forDisplay: 1).map(\.index), [1])
        XCTAssertEqual(state.spaces(forDisplay: 2).map(\.index), [2])
        XCTAssertTrue(state.spaces(forDisplay: 3).isEmpty)
    }

    func testWindowsForSpaceEmpty() {
        let state = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertTrue(state.windows(forSpace: 1).isEmpty, "No windows should return empty array")
    }

    func testWindowsForSpaceGroupedCorrectly() {
        let windows = [
            YabaiWindow(id: 1, app: "A", space: 1, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 2, app: "B", space: 1, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "normal"),
            YabaiWindow(id: 3, app: "C", space: 2, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "normal"),
        ]
        let state = GridState(config: .default, spaces: [], windows: windows, displayBounds: .zero, focusedIndex: nil)
        XCTAssertEqual(state.windows(forSpace: 1).count, 2)
        XCTAssertEqual(state.windows(forSpace: 2).count, 1)
        XCTAssertEqual(state.windows(forSpace: 3).count, 0)
    }


    func testGridStateWithDisplays() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
        ]
        let displays = [
            YabaiDisplay(index: 1, frame: .init(x: 0, y: 0, w: 1440, h: 900), hasFocus: true),
        ]
        let state = GridState(
            config: .default,
            spaces: spaces,
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: 1,
            displays: displays
        )
        XCTAssertEqual(state.displays.count, 1)
        XCTAssertEqual(state.displays.first?.index, 1)
    }


}
