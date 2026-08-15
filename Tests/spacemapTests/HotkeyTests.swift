import XCTest
import CoreGraphics
@testable import spacemap

final class HotkeyTests: XCTestCase {
    func testRecorderControlSpaceRoundTripsThroughSettingsParser() {
        let input = HotkeyRecorder.hotkeyStringFrom(
            HotkeyConfig(key: .keyCode(49), modifiers: .maskControl)
        )
        let hotkey = Hotkey.parseHotkey(input)

        XCTAssertEqual(input, "ctrl+space")
        XCTAssertEqual(hotkey?.keyCode, 49)
        XCTAssertTrue(hotkey?.modifiers.contains(.maskControl) ?? false)
    }

    func testRecorderOnlyShowsClearControlForAssignedHotkeys() {
        XCTAssertTrue(HotkeyRecorder.canClear("ctrl+space"))
        XCTAssertFalse(HotkeyRecorder.canClear("none"))
        XCTAssertFalse(HotkeyRecorder.canClear(" NONE "))
    }

    func testDuplicateHotkeyBindingsMatchOnlyWhenEnabledAndEquivalent() {
        XCTAssertTrue(SettingsBehavior.matches("ctrl+space", " CTRL + space "))
        XCTAssertTrue(SettingsBehavior.matches("fn+f8", "f8"))
        XCTAssertFalse(SettingsBehavior.matches("none", "none"))
        XCTAssertFalse(SettingsBehavior.matches("ctrl+space", "cmd+space"))
    }

    func testRecorderAcceptsKeyCodeZero() {
        let event = try! XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .control,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "a",
                charactersIgnoringModifiers: "a",
                isARepeat: false,
                keyCode: 0
            )
        )

        let hotkey = Hotkey.parseHotkeyFromEvent(event)
        XCTAssertEqual(HotkeyRecorder.hotkeyStringFrom(hotkey), "ctrl+a")
    }

    func testRecorderIgnoresFunctionModifierForFunctionKeys() {
        let event = try! XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .function,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 100
            )
        )

        let hotkey = Hotkey.parseHotkeyFromEvent(event)
        XCTAssertEqual(HotkeyRecorder.hotkeyStringFrom(hotkey), "f8")
    }

    func testLegacyFunctionModifierIsNormalized() {
        let hotkey = try! XCTUnwrap(Hotkey.parseHotkey("fn+f8"))
        XCTAssertEqual(Hotkey.hotkeyToString(hotkey), "f8")
        XCTAssertFalse(hotkey.modifiers.contains(.maskSecondaryFn))
    }

    func testMediaKeyEventRoundTripsThroughHotkeyConfig() {
        let event = try! XCTUnwrap(
            NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: .control,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (16 << 16) | (0xA << 8),
                data2: 0
            )
        )

        let hotkey = Hotkey.parseHotkeyFromMediaKeyEvent(event)
        XCTAssertEqual(HotkeyRecorder.hotkeyStringFrom(try! XCTUnwrap(hotkey)), "ctrl+play-pause")
    }

    func testBareMediaKeyRoundTripsThroughSettingsParser() {
        let input = HotkeyRecorder.hotkeyStringFrom(
            HotkeyConfig(key: .mediaKey(.playPause), modifiers: [])
        )
        let hotkey = Hotkey.parseHotkey(input)

        XCTAssertEqual(input, "play-pause")
        XCTAssertEqual(hotkey?.mediaKey, .playPause)
        XCTAssertEqual(hotkey?.modifiers, [])
    }

    func testParseSupportedHotkeys() {
        let cases: [(String, CGKeyCode?, MediaKey?, CGEventFlags)] = [
            ("ctrl+pgdn", 121, nil, .maskControl),
            ("cmd+shift+a", 0, nil, [.maskCommand, .maskShift]),
            ("alt+escape", 53, nil, .maskAlternate),
            ("space", 49, nil, []),
            ("cmd+play-pause", nil, .playPause, .maskCommand),
            ("hyper+k", 40, nil, [.maskCommand, .maskControl, .maskAlternate, .maskShift])
        ]

        for (input, keyCode, mediaKey, modifiers) in cases {
            let hotkey = try? XCTUnwrap(Hotkey.parseHotkey(input))
            XCTAssertEqual(hotkey?.keyCode, keyCode, input)
            XCTAssertEqual(hotkey?.mediaKey, mediaKey, input)
            XCTAssertEqual(hotkey?.modifiers, modifiers, input)
        }
    }

    func testRejectsInvalidHotkeys() {
        for input in ["", "super+a", "ctrl+f21", "ctrl+unknown"] {
            XCTAssertNil(Hotkey.parseHotkey(input), input)
        }
    }

    func testDisabledHotkeyRoundTrips() {
        let hotkey = try? XCTUnwrap(Hotkey.parseHotkey("none"))
        XCTAssertTrue(hotkey?.isDisabled ?? false)
        XCTAssertEqual(hotkey.map(Hotkey.hotkeyToString), "none")
    }

    func testNamedKeyCodesRoundTrip() {
        for input in Hotkey.supportedKeyNames {
            let keyCode = Hotkey.keyCodeFor(input)
            XCTAssertNotNil(keyCode, input)
            XCTAssertEqual(keyCode.map(Hotkey.keyCodeToSymbolicString), input, input)
        }
    }

    func testCanonicalHotkeysRoundTrip() {
        for input in ["ctrl+pgdn", "cmd+shift+a", "alt+escape", "ctrl+cmd+space", "f5", "hyper+k"] {
            let parsed = try? XCTUnwrap(Hotkey.parseHotkey(input))
            let serialized = parsed.map(Hotkey.hotkeyToString)
            let reparsed = serialized.flatMap(Hotkey.parseHotkey)
            XCTAssertEqual(reparsed?.key, parsed?.key, input)
            XCTAssertEqual(reparsed?.modifiers, parsed?.modifiers, input)
        }
    }

    func testEventTapRecoveryPolicy() {
        let cases: [(Bool, Bool, Bool, Bool, HotkeyMonitor.EventTapRecoveryAction)] = [
            (false, false, false, false, .waitForPermission),
            (false, true, true, true, .remove),
            (true, false, false, false, .install),
            (true, true, false, false, .reinstall),
            (true, true, true, false, .reenable),
            (true, true, true, true, .none)
        ]

        for (trusted, hasTap, valid, enabled, expected) in cases {
            XCTAssertEqual(
                HotkeyMonitor.recoveryAction(
                    isTrusted: trusted,
                    hasTap: hasTap,
                    tapIsValid: valid,
                    tapIsEnabled: enabled
                ),
                expected
            )
        }
    }
}
