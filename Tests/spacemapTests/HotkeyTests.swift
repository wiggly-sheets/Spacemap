import XCTest
import CoreGraphics
@testable import spacemap

final class HotkeyTests: XCTestCase {

    // MARK: - parseHotkey

    func testParseHotkeyCtrlPageDown() {
        let hk = ConfigReader.parseHotkey("ctrl+pgdn")!
        XCTAssertEqual(hk.keyCode, 121)
        XCTAssertTrue(hk.modifiers.contains(.maskControl))
        XCTAssertFalse(hk.modifiers.contains(.maskCommand))
    }

    func testParseHotkeyCmdShiftA() {
        let hk = ConfigReader.parseHotkey("cmd+shift+a")!
        XCTAssertEqual(hk.keyCode, 0)
        XCTAssertTrue(hk.modifiers.contains(.maskCommand))
        XCTAssertTrue(hk.modifiers.contains(.maskShift))
    }

    func testParseHotkeyAltEscape() {
        let hk = ConfigReader.parseHotkey("alt+escape")!
        XCTAssertEqual(hk.keyCode, 53)
        XCTAssertTrue(hk.modifiers.contains(.maskAlternate))
    }

    func testParseHotkeyNoModifier() {
        let hk = ConfigReader.parseHotkey("space")!
        XCTAssertEqual(hk.keyCode, 49)
        XCTAssertTrue(hk.modifiers.isEmpty)
    }

    func testParseHotkeyCaseInsensitive() {
        let hk = ConfigReader.parseHotkey("CTRL+PGDN")!
        XCTAssertEqual(hk.keyCode, 121)
        XCTAssertTrue(hk.modifiers.contains(.maskControl))
    }

    func testParseHotkeyUnknownKeyReturnsNil() {
        XCTAssertNil(ConfigReader.parseHotkey("ctrl+f21"))
    }

    func testParseHotkeyUnknownModifierReturnsNil() {
        XCTAssertNil(ConfigReader.parseHotkey("super+a"))
    }

    func testParseHotkeyEmptyReturnsNil() {
        XCTAssertNil(ConfigReader.parseHotkey(""))
    }

    // MARK: - keyCodeFor

    func testKeyCodeForNamedKeys() {
        XCTAssertEqual(ConfigReader.keyCodeFor("space"), 49)
        XCTAssertEqual(ConfigReader.keyCodeFor("tab"), 48)
        XCTAssertEqual(ConfigReader.keyCodeFor("return"), 36)
        XCTAssertEqual(ConfigReader.keyCodeFor("enter"), 36)
        XCTAssertEqual(ConfigReader.keyCodeFor("escape"), 53)
        XCTAssertEqual(ConfigReader.keyCodeFor("delete"), 51)
        XCTAssertEqual(ConfigReader.keyCodeFor("backspace"), 51)
        XCTAssertEqual(ConfigReader.keyCodeFor("pgdn"), 121)
        XCTAssertEqual(ConfigReader.keyCodeFor("pagedown"), 121)
        XCTAssertEqual(ConfigReader.keyCodeFor("pgup"), 116)
        XCTAssertEqual(ConfigReader.keyCodeFor("pageup"), 116)
        XCTAssertEqual(ConfigReader.keyCodeFor("home"), 115)
        XCTAssertEqual(ConfigReader.keyCodeFor("end"), 119)
    }

    func testKeyCodeForArrowKeys() {
        XCTAssertEqual(ConfigReader.keyCodeFor("left"), 123)
        XCTAssertEqual(ConfigReader.keyCodeFor("right"), 124)
        XCTAssertEqual(ConfigReader.keyCodeFor("down"), 125)
        XCTAssertEqual(ConfigReader.keyCodeFor("up"), 126)
    }

    func testKeyCodeForFunctionKeys() {
        XCTAssertEqual(ConfigReader.keyCodeFor("f1"), 122)
        XCTAssertEqual(ConfigReader.keyCodeFor("f5"), 96)
        XCTAssertEqual(ConfigReader.keyCodeFor("f12"), 111)
        XCTAssertEqual(ConfigReader.keyCodeFor("f13"), 105)
        XCTAssertEqual(ConfigReader.keyCodeFor("f16"), 106)
        XCTAssertEqual(ConfigReader.keyCodeFor("f20"), 90)
    }

    func testKeyCodeForAlphanumeric() {
        XCTAssertEqual(ConfigReader.keyCodeFor("a"), 0)
        XCTAssertEqual(ConfigReader.keyCodeFor("z"), 6)
        XCTAssertEqual(ConfigReader.keyCodeFor("1"), 18)
        XCTAssertEqual(ConfigReader.keyCodeFor("0"), 29)
        XCTAssertEqual(ConfigReader.keyCodeFor("="), 24)
        XCTAssertEqual(ConfigReader.keyCodeFor("-"), 27)
    }

    func testKeyCodeForUnknownReturnsNil() {
        XCTAssertNil(ConfigReader.keyCodeFor("f21"))
        XCTAssertNil(ConfigReader.keyCodeFor("capslock"))
    }

    // MARK: - hotkeyToString

    func testHotkeyToStringCtrlPageDown() {
        let hk = HotkeyConfig(keyCode: 121, modifiers: .maskControl)
        XCTAssertEqual(ConfigReader.hotkeyToString(hk), "ctrl+pgdn")
    }

    func testHotkeyToStringCmdShiftA() {
        let hk = HotkeyConfig(keyCode: 0, modifiers: [.maskCommand, .maskShift])
        XCTAssertEqual(ConfigReader.hotkeyToString(hk), "cmd+shift+a")
    }

    func testHotkeyToStringNoModifier() {
        let hk = HotkeyConfig(keyCode: 49, modifiers: [])
        XCTAssertEqual(ConfigReader.hotkeyToString(hk), "space")
    }

    func testHotkeyToStringAllModifiers() {
        let hk = HotkeyConfig(keyCode: 36, modifiers: [.maskControl, .maskCommand, .maskAlternate, .maskShift])
        XCTAssertEqual(ConfigReader.hotkeyToString(hk), "ctrl+cmd+alt+shift+return")
    }

    // MARK: - Roundtrip

    func testRoundtripHotkey() {
        let inputs = [
            "ctrl+pgdn",
            "cmd+shift+a",
            "alt+escape",
            "ctrl+cmd+space",
            "f5",
        ]
        for input in inputs {
            guard let parsed = ConfigReader.parseHotkey(input) else {
                XCTFail("Failed to parse: \(input)")
                continue
            }
            let output = ConfigReader.hotkeyToString(parsed)
            // Re-parse the output to verify roundtrip
            let reparsed = ConfigReader.parseHotkey(output)
            XCTAssertNotNil(reparsed, "Failed to re-parse: \(output)")
            XCTAssertEqual(reparsed?.keyCode, parsed.keyCode, "keyCode mismatch for \(input)")
        }
    }

    // MARK: - cellStyleName

    func testCellStyleName() {
        XCTAssertEqual(ConfigReader.cellStyleName(.rects), "rects")
        XCTAssertEqual(ConfigReader.cellStyleName(.icons), "icons")
        XCTAssertEqual(ConfigReader.cellStyleName(.thumbnails), "thumbnails")
    }
}
