import XCTest
import CoreGraphics
@testable import spacemap

final class ConfigModelTests: ModelTestCase {
    func testWindowDropFocusModesRespectHeldModifier() {
        XCTAssertFalse(
            WindowDropFocusMode.never.shouldFocus(
                eventFlags: [.maskCommand],
                requiredModifier: .command
            )
        )
        XCTAssertTrue(
            WindowDropFocusMode.always.shouldFocus(
                eventFlags: [],
                requiredModifier: .command
            )
        )
        XCTAssertTrue(
            WindowDropFocusMode.modifier.shouldFocus(
                eventFlags: [.maskAlternate, .maskShift],
                requiredModifier: .option
            )
        )
        XCTAssertFalse(
            WindowDropFocusMode.modifier.shouldFocus(
                eventFlags: [.maskShift],
                requiredModifier: .option
            )
        )
    }



    func testHotkeyConfigDefault() {
        let hk = HotkeyConfig.default
        XCTAssertEqual(hk.keyCode, 121)
        XCTAssertTrue(hk.modifiers.contains(.maskControl))
    }


    func testSpacemapConfigDefault() {
        let c = SpacemapConfig.default
        XCTAssertEqual(c.cols, 8)
        XCTAssertEqual(c.rows, 2)
        XCTAssertEqual(c.cellStyle, .rects)
        XCTAssertEqual(c.theme, "default")
        XCTAssertEqual(c.maxSpaces, 16)
        XCTAssertEqual(c.multiMonitorHUDMode, .unified)
        XCTAssertEqual(c.unifiedHUDVisibility, .active)
        XCTAssertEqual(c.separateHUDVisibility, .all)
        XCTAssertEqual(c.displayNavigationWrap, .within)
        XCTAssertEqual(c.hudKeys, HUDKeyBindings.default)
        XCTAssertTrue(c.pinnedHotkey.isDisabled)
        XCTAssertEqual(c.hudPosition, .center)
    }


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
        XCTAssertEqual(HUDPosition.custom(x: 0.3, y: 0.7, screen: nil).label, "Custom")
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
        let point = HUDPosition.custom(x: 0.0, y: 1.0, screen: "display-A").point(for: panelSize, screen: screen)
        XCTAssertEqual(point.x, 0)
        XCTAssertEqual(point.y, 880)
    }


    func testAppThemeDefaultValues() {
        let t = AppTheme.default
        XCTAssertEqual(t.background, 0xf2f2f7)
        XCTAssertEqual(t.focused, 0x007aff)
        XCTAssertEqual(t.text, 0x333333)
        XCTAssertEqual(t.rect1, 0x007aff)
        XCTAssertEqual(t.rect2, 0x5ac8fa)
        XCTAssertEqual(t.rect3, 0x34c759)
    }

}
