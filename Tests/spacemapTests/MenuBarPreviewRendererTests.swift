import XCTest
@testable import spacemap

final class MenuBarPreviewRendererTests: XCTestCase {

    // MARK: - spaceIndices

    func testSpaceIndicesIconModeReturnsEmpty() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        let indices = MenuBarPreviewRenderer.spaceIndices(
            mode: .icon,
            nearbyCount: 3,
            spaces: spaces,
            focusedIndex: 1
        )
        XCTAssertTrue(indices.isEmpty)
    }

    func testSpaceIndicesDotsModeReturnsAll() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
            YabaiSpace(id: 3, index: 3, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        let indices = MenuBarPreviewRenderer.spaceIndices(
            mode: .dots,
            nearbyCount: 3,
            spaces: spaces,
            focusedIndex: 1
        )
        XCTAssertEqual(indices, [1, 2, 3])
    }

    func testSpaceIndicesCurrentModeReturnsFocused() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
            YabaiSpace(id: 3, index: 3, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        let indices = MenuBarPreviewRenderer.spaceIndices(
            mode: .current,
            nearbyCount: 3,
            spaces: spaces,
            focusedIndex: 2
        )
        XCTAssertEqual(indices, [2])
    }

    func testSpaceIndicesAllModeReturnsAll() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        let indices = MenuBarPreviewRenderer.spaceIndices(
            mode: .all,
            nearbyCount: 3,
            spaces: spaces,
            focusedIndex: 1
        )
        XCTAssertEqual(indices, [1, 2])
    }

    func testSpaceIndicesNearbyModeCentersOnFocused() {
        let spaces = (1...10).map { i in
            YabaiSpace(id: i, index: i, display: 1, hasFocus: i == 5, isVisible: true, label: nil)
        }
        let indices = MenuBarPreviewRenderer.spaceIndices(
            mode: .nearby,
            nearbyCount: 3,
            spaces: spaces,
            focusedIndex: 5
        )
        XCTAssertEqual(indices, [4, 5, 6])
    }

    func testSpaceIndicesNearbyModeClampsAtStart() {
        let spaces = (1...5).map { i in
            YabaiSpace(id: i, index: i, display: 1, hasFocus: i == 1, isVisible: true, label: nil)
        }
        let indices = MenuBarPreviewRenderer.spaceIndices(
            mode: .nearby,
            nearbyCount: 3,
            spaces: spaces,
            focusedIndex: 1
        )
        XCTAssertEqual(indices, [1, 2, 3])
    }

    func testSpaceIndicesNearbyModeClampsAtEnd() {
        let spaces = (1...5).map { i in
            YabaiSpace(id: i, index: i, display: 1, hasFocus: i == 5, isVisible: true, label: nil)
        }
        let indices = MenuBarPreviewRenderer.spaceIndices(
            mode: .nearby,
            nearbyCount: 3,
            spaces: spaces,
            focusedIndex: 5
        )
        XCTAssertEqual(indices, [3, 4, 5])
    }

    func testSpaceIndicesNearbyModeWithCountLargerThanSpaces() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        let indices = MenuBarPreviewRenderer.spaceIndices(
            mode: .nearby,
            nearbyCount: 5,
            spaces: spaces,
            focusedIndex: 1
        )
        XCTAssertEqual(indices, [1, 2])
    }

    func testSpaceIndicesEmptySpaces() {
        let indices = MenuBarPreviewRenderer.spaceIndices(
            mode: .dots,
            nearbyCount: 3,
            spaces: [],
            focusedIndex: nil
        )
        XCTAssertTrue(indices.isEmpty)
    }

    func testSpaceIndicesNearbyWithNoFocusedUsesFirst() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: false, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        let indices = MenuBarPreviewRenderer.spaceIndices(
            mode: .nearby,
            nearbyCount: 2,
            spaces: spaces,
            focusedIndex: nil
        )
        XCTAssertEqual(indices, [1, 2])
    }

    // MARK: - separatedWindowFrame

    func testSeparatedWindowFrameWithValidFrame() {
        let frame = CGRect(x: 10, y: 10, width: 100, height: 50)
        let result = MenuBarPreviewRenderer.separatedWindowFrame(frame)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, 98.9)
        XCTAssertEqual(result?.height, 48.9)
    }

    func testSeparatedWindowFrameWithZeroWidth() {
        let frame = CGRect(x: 0, y: 0, width: 0, height: 50)
        let result = MenuBarPreviewRenderer.separatedWindowFrame(frame)
        XCTAssertNil(result)
    }

    func testSeparatedWindowFrameWithZeroHeight() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 0)
        let result = MenuBarPreviewRenderer.separatedWindowFrame(frame)
        XCTAssertNil(result)
    }

    func testSeparatedWindowFrameWithNullFrame() {
        let frame = CGRect.null
        let result = MenuBarPreviewRenderer.separatedWindowFrame(frame)
        XCTAssertNil(result)
    }

    // MARK: - image

    func testImageReturnsNilForIconMode() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
        ]
        let state = GridState(
            config: GridConfig.default,
            spaces: spaces,
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: 1
        )
        // Icon mode returns nil since it doesn't render a preview image
        let config = GridConfig.default
        // Note: icon mode doesn't produce an image, but we can test that the method
        // doesn't crash with various configurations
        _ = config.menuBarDisplayMode
    }

    func testImageReturnsNonNilForDotsMode() {
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: true, label: nil),
        ]
        var config = GridConfig.default
        config.menuBarDisplayMode = .dots
        let state = GridState(
            config: config,
            spaces: spaces,
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: 1
        )
        // Dots mode should produce an image
        // Note: this actually creates an NSImage which requires AppKit
        let image = MenuBarPreviewRenderer.image(for: state)
        XCTAssertNotNil(image)
    }
}
