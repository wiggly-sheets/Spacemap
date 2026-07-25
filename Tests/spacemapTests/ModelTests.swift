import XCTest
import CoreGraphics
@testable import spacemap

final class ModelTests: XCTestCase {

    // MARK: - YabaiSpace decoding

    func testDecodeYabaiSpace() throws {
        let json = """
        {"id":1,"index":1,"display":1,"has-focus":true,"label":"Term"}
        """.data(using: .utf8)!
        let space = try JSONDecoder().decode(YabaiSpace.self, from: json)
        XCTAssertEqual(space.id, 1)
        XCTAssertEqual(space.index, 1)
        XCTAssertEqual(space.display, 1)
        XCTAssertTrue(space.hasFocus)
        XCTAssertEqual(space.label, "Term")
    }

    func testDecodeYabaiSpaceNoLabel() throws {
        let json = """
        {"id":2,"index":2,"display":1,"has-focus":false}
        """.data(using: .utf8)!
        let space = try JSONDecoder().decode(YabaiSpace.self, from: json)
        XCTAssertNil(space.label)
    }

    // MARK: - YabaiWindow decoding

    func testDecodeYabaiWindow() throws {
        let json = """
        {"id":10,"app":"Firefox","space":1,"frame":{"x":0,"y":0,"w":800,"h":600},"is-hidden":false,"is-minimized":false,"sub-layer":"below"}
        """.data(using: .utf8)!
        let window = try JSONDecoder().decode(YabaiWindow.self, from: json)
        XCTAssertEqual(window.id, 10)
        XCTAssertEqual(window.app, "Firefox")
        XCTAssertEqual(window.space, 1)
        XCTAssertFalse(window.isHidden)
        XCTAssertFalse(window.isMinimized)
        XCTAssertEqual(window.subLayer, "below")
        XCTAssertEqual(window.cgFrame, CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    func testDecodeYabaiWindowHidden() throws {
        let json = """
        {"id":11,"app":"Safari","space":2,"frame":{"x":100,"y":50,"w":400,"h":300},"is-hidden":true,"is-minimized":true,"sub-layer":"normal"}
        """.data(using: .utf8)!
        let window = try JSONDecoder().decode(YabaiWindow.self, from: json)
        XCTAssertTrue(window.isHidden)
        XCTAssertTrue(window.isMinimized)
        XCTAssertEqual(window.subLayer, "normal")
    }

    // MARK: - GridState

    func testGridStateWindowGrouping() {
        let windows = [
            YabaiWindow(id: 1, app: "A", space: 1, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "below"),
            YabaiWindow(id: 2, app: "B", space: 1, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "below"),
            YabaiWindow(id: 3, app: "C", space: 2, frame: .init(x: 0, y: 0, w: 100, h: 100), isHidden: false, isMinimized: false, subLayer: "below"),
        ]
        let state = GridState(config: .default, spaces: [], windows: windows, displayBounds: .zero, focusedIndex: nil)
        XCTAssertEqual(state.windows(forSpace: 1).count, 2)
        XCTAssertEqual(state.windows(forSpace: 2).count, 1)
        XCTAssertEqual(state.windows(forSpace: 3).count, 0)
    }

    func testGridStateEquality() {
        let a = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: 1)
        let b = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: 1)
        let c = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: 2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testGridStateWindowsEmpty() {
        let state = GridState(config: .default, spaces: [], windows: [], displayBounds: .zero, focusedIndex: nil)
        XCTAssertTrue(state.windows(forSpace: 1).isEmpty)
    }

    // MARK: - HotkeyConfig

    func testHotkeyConfigDefault() {
        let hk = HotkeyConfig.default
        XCTAssertEqual(hk.keyCode, 121)
        XCTAssertTrue(hk.modifiers.contains(.maskControl))
    }

    // MARK: - GridConfig

    func testGridConfigDefault() {
        let c = GridConfig.default
        XCTAssertEqual(c.cols, 8)
        XCTAssertEqual(c.rows, 2)
        XCTAssertEqual(c.cellStyle, .rects)
        XCTAssertEqual(c.theme, "default")
        XCTAssertEqual(c.maxSpaces, 16)
        XCTAssertFalse(c.useVimKeys)
        XCTAssertFalse(c.useArrowKeys)
        XCTAssertEqual(c.hudPosition, .center)
    }

    // MARK: - HUDPosition

    func testHUDPositionCenterLabel() {
        XCTAssertEqual(HUDPosition.center.label, "Center")
    }

    func testHUDPositionTopLabel() {
        XCTAssertEqual(HUDPosition.top.label, "Top")
    }

    func testHUDPositionBottomLabel() {
        XCTAssertEqual(HUDPosition.bottom.label, "Bottom")
    }

    func testHUDPositionCustomLabel() {
        XCTAssertEqual(HUDPosition.custom(x: 0.3, y: 0.7).label, "Custom")
    }

    func testHUDPositionCenterPoint() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panelSize = CGSize(width: 400, height: 200)
        let point = HUDPosition.center.point(for: panelSize, screen: screen)
        XCTAssertEqual(point.x, 760)
        XCTAssertEqual(point.y, 440)
    }

    func testHUDPositionTopPoint() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panelSize = CGSize(width: 400, height: 200)
        let point = HUDPosition.top.point(for: panelSize, screen: screen)
        XCTAssertEqual(point.x, 760)
        XCTAssertEqual(point.y, 840)
    }

    func testHUDPositionBottomPoint() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panelSize = CGSize(width: 400, height: 200)
        let point = HUDPosition.bottom.point(for: panelSize, screen: screen)
        XCTAssertEqual(point.x, 760)
        XCTAssertEqual(point.y, 40)
    }

    func testHUDPositionCustomPoint() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let panelSize = CGSize(width: 400, height: 200)
        let point = HUDPosition.custom(x: 0.0, y: 1.0).point(for: panelSize, screen: screen)
        XCTAssertEqual(point.x, 0)
        XCTAssertEqual(point.y, 880)
    }

    // MARK: - AppTheme

    func testAppThemeDefaultValues() {
        let t = AppTheme.default
        XCTAssertEqual(t.background, 0xf2f2f7)
        XCTAssertEqual(t.focused, 0x007aff)
        XCTAssertEqual(t.text, 0x333333)
        XCTAssertEqual(t.rect1, 0x007aff)
        XCTAssertEqual(t.rect2, 0x5ac8fa)
        XCTAssertEqual(t.rect3, 0x34c759)
    }

    func testAppThemeBuiltinThemesHaveDistinctColors() {
        let themes: [AppTheme] = [.default, .tokyonight, .catppuccin, .dracula, .nord]
        for (i, a) in themes.enumerated() {
            for (j, b) in themes.enumerated() where i != j {
                XCTAssertNotEqual(a.background, b.background, "Themes \(i) and \(j) share background color")
            }
        }
    }
}
