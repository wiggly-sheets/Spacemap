import XCTest
import CoreGraphics
@testable import spacemap

final class HotkeyTests: XCTestCase {

    // MARK: - parseHotkey

    func testParseHotkeyCtrlPageDown() {
        let hk = Hotkey.parseHotkey("ctrl+pgdn")!
        XCTAssertEqual(hk.keyCode, 121)
        XCTAssertTrue(hk.modifiers.contains(.maskControl))
        XCTAssertFalse(hk.modifiers.contains(.maskCommand))
    }

    func testParseHotkeyCmdShiftA() {
        let hk = Hotkey.parseHotkey("cmd+shift+a")!
        XCTAssertEqual(hk.keyCode, 0)
        XCTAssertTrue(hk.modifiers.contains(.maskCommand))
        XCTAssertTrue(hk.modifiers.contains(.maskShift))
    }

    func testParseHotkeyAltEscape() {
        let hk = Hotkey.parseHotkey("alt+escape")!
        XCTAssertEqual(hk.keyCode, 53)
        XCTAssertTrue(hk.modifiers.contains(.maskAlternate))
    }

    func testParseHotkeyNoModifier() {
        let hk = Hotkey.parseHotkey("space")!
        XCTAssertEqual(hk.keyCode, 49)
        XCTAssertTrue(hk.modifiers.isEmpty)
    }

    func testParseHotkeyCaseInsensitive() {
        let hk = Hotkey.parseHotkey("CTRL+PGDN")!
        XCTAssertEqual(hk.keyCode, 121)
        XCTAssertTrue(hk.modifiers.contains(.maskControl))
    }

    func testParseHotkeyUnknownKeyReturnsNil() {
        XCTAssertNil(Hotkey.parseHotkey("ctrl+f21"))
    }

    func testParseMediaKey() {
        let hk = Hotkey.parseHotkey("cmd+play-pause")!
        XCTAssertEqual(hk.mediaKey, .playPause)
        XCTAssertTrue(hk.modifiers.contains(.maskCommand))
    }

    func testParseHotkeyUnknownModifierReturnsNil() {
        XCTAssertNil(Hotkey.parseHotkey("super+a"))
    }

    func testParseHotkeyEmptyReturnsNil() {
        XCTAssertNil(Hotkey.parseHotkey(""))
    }

    func testParseHotkeyNoneDisablesBinding() {
        let hk = Hotkey.parseHotkey("none")!
        XCTAssertTrue(hk.isDisabled)
        XCTAssertEqual(Hotkey.hotkeyToString(hk), "none")
    }

    // MARK: - keyCodeFor

    func testKeyCodeForNamedKeys() {
        XCTAssertEqual(Hotkey.keyCodeFor("space"), 49)
        XCTAssertEqual(Hotkey.keyCodeFor("tab"), 48)
        XCTAssertEqual(Hotkey.keyCodeFor("return"), 36)
        XCTAssertEqual(Hotkey.keyCodeFor("escape"), 53)
        XCTAssertEqual(Hotkey.keyCodeFor("delete"), 51)
        XCTAssertEqual(Hotkey.keyCodeFor("pgdn"), 121)
        XCTAssertEqual(Hotkey.keyCodeFor("pgup"), 116)
        XCTAssertEqual(Hotkey.keyCodeFor("home"), 115)
        XCTAssertEqual(Hotkey.keyCodeFor("end"), 119)
    }

    func testKeyCodeForArrowKeys() {
        XCTAssertEqual(Hotkey.keyCodeFor("left"), 123)
        XCTAssertEqual(Hotkey.keyCodeFor("right"), 124)
        XCTAssertEqual(Hotkey.keyCodeFor("down"), 125)
        XCTAssertEqual(Hotkey.keyCodeFor("up"), 126)
    }

    func testKeyCodeForFunctionKeys() {
        XCTAssertEqual(Hotkey.keyCodeFor("f1"), 122)
        XCTAssertEqual(Hotkey.keyCodeFor("f5"), 96)
        XCTAssertEqual(Hotkey.keyCodeFor("f12"), 111)
        XCTAssertEqual(Hotkey.keyCodeFor("f13"), 105)
        XCTAssertEqual(Hotkey.keyCodeFor("f16"), 106)
        XCTAssertEqual(Hotkey.keyCodeFor("f20"), 90)
    }

    func testKeyCodeForAlphanumeric() {
        XCTAssertEqual(Hotkey.keyCodeFor("a"), 0)
        XCTAssertEqual(Hotkey.keyCodeFor("z"), 6)
        XCTAssertEqual(Hotkey.keyCodeFor("1"), 18)
        XCTAssertEqual(Hotkey.keyCodeFor("0"), 29)
        XCTAssertEqual(Hotkey.keyCodeFor("="), 24)
        XCTAssertEqual(Hotkey.keyCodeFor("-"), 27)
    }

    func testKeyCodeForUnknownReturnsNil() {
        XCTAssertNil(Hotkey.keyCodeFor("f21"))
        XCTAssertNil(Hotkey.keyCodeFor("capslock"))
        XCTAssertNil(Hotkey.keyCodeFor("enter"))
        XCTAssertNil(Hotkey.keyCodeFor("backspace"))
        XCTAssertNil(Hotkey.keyCodeFor("pagedown"))
        XCTAssertNil(Hotkey.keyCodeFor("pageup"))
    }

    // MARK: - hotkeyToString

    func testHotkeyToStringCtrlPageDown() {
        let hk = HotkeyConfig(key: .keyCode(121), modifiers: .maskControl)
        XCTAssertEqual(Hotkey.hotkeyToString(hk), "ctrl+pgdn")
    }

    func testHotkeyToStringCmdShiftA() {
        let hk = HotkeyConfig(key: .keyCode(0), modifiers: [.maskCommand, .maskShift])
        XCTAssertEqual(Hotkey.hotkeyToString(hk), "cmd+shift+a")
    }

    func testHotkeyToStringNoModifier() {
        let hk = HotkeyConfig(key: .keyCode(49), modifiers: [])
        XCTAssertEqual(Hotkey.hotkeyToString(hk), "space")
    }

    func testHotkeyToStringAllModifiers() {
        let hk = HotkeyConfig(key: .keyCode(36), modifiers: [.maskControl, .maskCommand, .maskAlternate, .maskShift])
        XCTAssertEqual(Hotkey.hotkeyToString(hk), "hyper+return")
    }

    func testHotkeyToStringMediaKey() {
        let hk = HotkeyConfig(key: .mediaKey(.playPause), modifiers: [.maskCommand])
        XCTAssertEqual(Hotkey.hotkeyToString(hk), "cmd+play-pause")
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
            guard let parsed = Hotkey.parseHotkey(input) else {
                XCTFail("Failed to parse: \(input)")
                continue
            }
            let output = Hotkey.hotkeyToString(parsed)
            // Re-parse the output to verify roundtrip
            let reparsed = Hotkey.parseHotkey(output)
            XCTAssertNotNil(reparsed, "Failed to re-parse: \(output)")
            XCTAssertEqual(reparsed?.keyCode, parsed.keyCode, "keyCode mismatch for \(input)")
        }
    }

    // MARK: - keyCodeToSymbolicString roundtrip

    func testKeyCodeToSymbolicStringExactMapping() {
        XCTAssertEqual(Hotkey.keyCodeToSymbolicString(34), "i")
        XCTAssertEqual(Hotkey.keyCodeToSymbolicString(35), "p")
        XCTAssertEqual(Hotkey.keyCodeToSymbolicString(40), "k")
        XCTAssertEqual(Hotkey.keyCodeToSymbolicString(45), "n")
        XCTAssertEqual(Hotkey.keyCodeToSymbolicString(46), "m")
    }

    func testKeyCodeToSymbolicStringKeypadDelete() {
        XCTAssertEqual(Hotkey.keyCodeToSymbolicString(76), "delete")
    }

    
    func testHyperModifierDisplaysAsHyper() {
        var flags: CGEventFlags = []
        flags.insert(.maskCommand)
        flags.insert(.maskControl)
        flags.insert(.maskAlternate)
        flags.insert(.maskShift)
        XCTAssertEqual(Hotkey.hotkeyModifierString(flags), "hyper")
    }

    func testHyperParseRoundTrip() {
        let parsed = Hotkey.parseHotkey("hyper+k")
        let flags = parsed?.modifiers
        XCTAssertNotNil(parsed)
        XCTAssertTrue(flags?.contains(.maskCommand) == true)
        XCTAssertTrue(flags?.contains(.maskControl) == true)
        XCTAssertTrue(flags?.contains(.maskAlternate) == true)
        XCTAssertTrue(flags?.contains(.maskShift) == true)
        // Round trip: hyper+k should display as hyper+k
        let formatted = Hotkey.hotkeyToString(parsed!)
        XCTAssertEqual(formatted, "hyper+k")
    }

    func testHyperDoesNotMatchThreeModifiers() {
        var flags: CGEventFlags = []
        flags.insert(.maskCommand)
        flags.insert(.maskControl)
        flags.insert(.maskAlternate)
        XCTAssertEqual(Hotkey.hotkeyModifierString(flags), "ctrl+cmd+alt")
    }

func testKeyCodeToSymbolicStringAlphanumericRoundtrip() {
        let keys = ["i", "p", "l", "j", "k", "n", "m", "u", "o", "a", "z", "0", "=", "-"]
        for key in keys {
            guard let code = Hotkey.keyCodeFor(key) else {
                XCTFail("Key not found: \(key)")
                continue
            }
            XCTAssertEqual(Hotkey.keyCodeToSymbolicString(code), key, "Roundtrip failed for \(key)")
        }
    }

    func testKeyCodeToSymbolicStringRoundtrip() {
        let keys = ["space", "tab", "return", "escape", "delete", "pgdn", "pgup", "home", "end", "left", "right", "down", "up", "f1", "f5", "f12", "f13", "f16", "f20", "a", "z", "1", "0", "=", "-"]
        for key in keys {
            guard let code = Hotkey.keyCodeFor(key) else {
                XCTFail("Key not found: \(key)")
                continue
            }
            let sym = Hotkey.keyCodeToSymbolicString(code)
            guard let roundtrip = Hotkey.keyCodeFor(sym) else {
                XCTFail("Symbol not found: \(sym)")
                continue
            }
            XCTAssertEqual(roundtrip, code, "Roundtrip failed for \(key)")
        }
    }

    // MARK: - modifiers roundtrip

    func testModifiersRoundtrip() {
        let inputs: [[String]] = [
            [],
            ["ctrl"],
            ["cmd", "alt"],
            ["shift", "fn"],
            ["ctrl", "cmd", "alt", "shift", "fn"]
        ]
        for names in inputs {
            let flags = Hotkey.modifiers(from: names)
            let roundtrip = Hotkey.modifierNames(for: flags)
            XCTAssertEqual(roundtrip, names, "Modifiers roundtrip failed for \(names)")
        }
    }

    func testHotkeyModifierStringIncludesFn() {
        XCTAssertEqual(Hotkey.hotkeyModifierString(.maskSecondaryFn), "fn")
        XCTAssertEqual(Hotkey.hotkeyModifierString([.maskControl, .maskSecondaryFn]), "ctrl+fn")
        XCTAssertEqual(Hotkey.hotkeyModifierString([.maskCommand, .maskShift, .maskSecondaryFn]), "cmd+shift+fn")
    }

    // MARK: - Event tap recovery

    func testEventTapRecoveryHandlesPermissionChanges() {
        XCTAssertEqual(
            HotkeyMonitor.recoveryAction(
                isTrusted: false,
                hasTap: false,
                tapIsValid: false,
                tapIsEnabled: false
            ),
            .waitForPermission
        )
        XCTAssertEqual(
            HotkeyMonitor.recoveryAction(
                isTrusted: false,
                hasTap: true,
                tapIsValid: true,
                tapIsEnabled: true
            ),
            .remove
        )
        XCTAssertEqual(
            HotkeyMonitor.recoveryAction(
                isTrusted: true,
                hasTap: false,
                tapIsValid: false,
                tapIsEnabled: false
            ),
            .install
        )
    }

    func testEventTapRecoveryHandlesInvalidAndDisabledTaps() {
        XCTAssertEqual(
            HotkeyMonitor.recoveryAction(
                isTrusted: true,
                hasTap: true,
                tapIsValid: false,
                tapIsEnabled: false
            ),
            .reinstall
        )
        XCTAssertEqual(
            HotkeyMonitor.recoveryAction(
                isTrusted: true,
                hasTap: true,
                tapIsValid: true,
                tapIsEnabled: false
            ),
            .reenable
        )
        XCTAssertEqual(
            HotkeyMonitor.recoveryAction(
                isTrusted: true,
                hasTap: true,
                tapIsValid: true,
                tapIsEnabled: true
            ),
            .none
        )
    }

    // MARK: - cellStyleName

    func testCellStyleName() {
        XCTAssertEqual(Config.cellStyleName(.rects), "rects")
        XCTAssertEqual(Config.cellStyleName(.hybrid), "hybrid")
        XCTAssertEqual(Config.cellStyleName(.icons), "icons")
        XCTAssertEqual(Config.cellStyleName(.thumbnails), "thumbnails")
        XCTAssertEqual(Config.cellStyleName(.simple), "simple")
    }

    // MARK: - HotkeyConfig

    func testHotkeyConfigDefault() {
        let hk = HotkeyConfig.default
        XCTAssertEqual(hk.keyCode, 121)
        XCTAssertTrue(hk.modifiers.contains(.maskControl))
        XCTAssertFalse(hk.isDisabled)
    }

    func testHotkeyConfigNoneIsDisabled() {
        let hk = HotkeyConfig(key: .none, modifiers: [])
        XCTAssertTrue(hk.isDisabled)
        XCTAssertNil(hk.keyCode)
        XCTAssertNil(hk.mediaKey)
    }

    func testHotkeyConfigMediaKey() {
        let hk = HotkeyConfig(key: .mediaKey(.playPause), modifiers: .maskCommand)
        XCTAssertFalse(hk.isDisabled)
        XCTAssertEqual(hk.mediaKey, .playPause)
        XCTAssertNil(hk.keyCode)
    }

    // MARK: - HotkeyKey

    func testHotkeyKeyEquatable() {
        let a = HotkeyKey.keyCode(121)
        let b = HotkeyKey.keyCode(121)
        let c = HotkeyKey.keyCode(49)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testHotkeyKeyMediaKeyEquatable() {
        let a = HotkeyKey.mediaKey(.playPause)
        let b = HotkeyKey.mediaKey(.playPause)
        let c = HotkeyKey.mediaKey(.nextTrack)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - MediaKey

    func testMediaKeyAllCases() {
        XCTAssertEqual(MediaKey.playPause.rawValue, "play-pause")
        XCTAssertEqual(MediaKey.nextTrack.rawValue, "next-track")
        XCTAssertEqual(MediaKey.previousTrack.rawValue, "previous-track")
        XCTAssertEqual(MediaKey.volumeUp.rawValue, "volume-up")
        XCTAssertEqual(MediaKey.volumeDown.rawValue, "volume-down")
        XCTAssertEqual(MediaKey.mute.rawValue, "mute")
        XCTAssertEqual(MediaKey.brightnessUp.rawValue, "brightness-up")
        XCTAssertEqual(MediaKey.brightnessDown.rawValue, "brightness-down")
    }

    // MARK: - WindowDropFocusMode

    func testWindowDropFocusModeNever() {
        XCTAssertFalse(WindowDropFocusMode.never.shouldFocus(eventFlags: [], requiredModifier: .command))
        XCTAssertFalse(WindowDropFocusMode.never.shouldFocus(eventFlags: [.maskCommand], requiredModifier: .command))
    }

    func testWindowDropFocusModeAlways() {
        XCTAssertTrue(WindowDropFocusMode.always.shouldFocus(eventFlags: [], requiredModifier: .command))
        XCTAssertTrue(WindowDropFocusMode.always.shouldFocus(eventFlags: [.maskCommand], requiredModifier: .command))
    }

    func testWindowDropFocusModeModifierWithNoModifier() {
        XCTAssertFalse(WindowDropFocusMode.modifier.shouldFocus(eventFlags: [], requiredModifier: .command))
    }

    // MARK: - WindowDropFocusModifier

    func testWindowDropFocusModifierEventFlags() {
        XCTAssertEqual(WindowDropFocusModifier.command.eventFlag, .maskCommand)
        XCTAssertEqual(WindowDropFocusModifier.function.eventFlag, .maskSecondaryFn)
        XCTAssertEqual(WindowDropFocusModifier.option.eventFlag, .maskAlternate)
        XCTAssertEqual(WindowDropFocusModifier.control.eventFlag, .maskControl)
        XCTAssertEqual(WindowDropFocusModifier.shift.eventFlag, .maskShift)
    }

    // MARK: - HUDPosition

    func testHUDPositionAllPresets() {
        XCTAssertEqual(HUDPosition.allPresets, [.center, .top, .bottom])
    }

    func testHUDPositionCustomX() {
        let pos = HUDPosition.custom(x: 0.5, y: 0.5)
        if case .custom(let x, let y) = pos {
            XCTAssertEqual(x, 0.5)
            XCTAssertEqual(y, 0.5)
        } else {
            XCTFail("Expected custom position")
        }
    }

    // MARK: - HUDPositionKind

    func testHUDPositionKindFromPosition() {
        XCTAssertEqual(HUDPositionKind(from: .center), .center)
        XCTAssertEqual(HUDPositionKind(from: .top), .top)
        XCTAssertEqual(HUDPositionKind(from: .bottom), .bottom)
        XCTAssertEqual(HUDPositionKind(from: .custom(x: 0.5, y: 0.5)), .custom)
    }

    // MARK: - GridState focusedIndex equality

    func testGridStateEqualityIgnoresNonFocusedFields() {
        let state1 = GridState(
            config: .default,
            spaces: [],
            windows: [],
            displayBounds: .zero,
            focusedIndex: 1,
            displays: []
        )
        let state2 = GridState(
            config: .default,
            spaces: [YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil)],
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            focusedIndex: 1,
            displays: []
        )
        XCTAssertEqual(state1, state2, "GridState equality only compares focusedIndex")
    }
}
