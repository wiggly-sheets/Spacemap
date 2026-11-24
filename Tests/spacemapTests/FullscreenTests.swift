import XCTest
@testable import spacemap

final class FullscreenTests: XCTestCase {
    func testDecodeSpaceFullscreenFlag() throws {
        let json = """
        {"id":7,"index":7,"display":1,"has-focus":true,"is-native-fullscreen":true}
        """.data(using: .utf8)!
        let space = try JSONDecoder().decode(YabaiSpace.self, from: json)
        XCTAssertEqual(space.isNativeFullscreen, true)
    }

    private func state(
        spaceFullscreen: Bool?,
        windowFullscreen: Bool?,
        otherSpaceFullscreen: Bool? = nil
    ) -> GridState {
        var window = YabaiWindow(
            id: 1,
            app: "Safari",
            space: 7,
            frame: .init(x: 0, y: 0, w: 1440, h: 900),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal"
        )
        window.isNativeFullscreen = windowFullscreen
        let spaces = [
            YabaiSpace(
                id: 7, index: 7, display: 1, hasFocus: true, isVisible: true,
                label: nil, isNativeFullscreen: spaceFullscreen
            ),
            YabaiSpace(
                id: 8, index: 8, display: 1, hasFocus: false, isVisible: true,
                label: nil, isNativeFullscreen: otherSpaceFullscreen
            ),
        ]
        return GridState(
            config: .default,
            spaces: spaces,
            windows: [window],
            displayBounds: CGRect(x: 0, y: 0, width: 1440, height: 900),
            focusedIndex: 7
        )
    }

    func testWindowFullscreenFlagIsEnough() {
        XCTAssertEqual(state(spaceFullscreen: false, windowFullscreen: true).isFullscreen(spaceIndex: 7), true)
    }

    func testFullscreenSpaceIsEnoughWhenWindowFlagIsFalse() {
        XCTAssertEqual(state(spaceFullscreen: true, windowFullscreen: false).isFullscreen(spaceIndex: 7), true)
    }

    func testAnotherSpacesFlagDoesNotCount() {
        XCTAssertEqual(state(spaceFullscreen: false, windowFullscreen: false, otherSpaceFullscreen: true).isFullscreen(spaceIndex: 7), false)
    }

    func testMissingFlagsAreUnknown() {
        XCTAssertNil(state(spaceFullscreen: nil, windowFullscreen: nil).isFullscreen(spaceIndex: 7))
    }
}
