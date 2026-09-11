import XCTest
import CoreGraphics
@testable import spacemap

final class HUDInputTests: XCTestCase {
    func testNumberKeysSupportMainKeyboardAndKeypad() {
        XCTAssertEqual(HUDInput.numberFromKeyCode(keyCode: 18, flags: []), 1)
        XCTAssertEqual(HUDInput.numberFromKeyCode(keyCode: 29, flags: []), 0)
        XCTAssertEqual(HUDInput.numberFromKeyCode(keyCode: 92, flags: []), 9)
        XCTAssertNil(HUDInput.numberFromKeyCode(keyCode: 18, flags: .maskCommand))
    }

    func testSettingsShortcutRequiresCommandSlash() {
        XCTAssertTrue(HUDInput.isSettingsShortcut(keyCode: 43, flags: .maskCommand))
        XCTAssertFalse(HUDInput.isSettingsShortcut(keyCode: 43, flags: []))
        XCTAssertFalse(HUDInput.isSettingsShortcut(keyCode: 0, flags: .maskCommand))
    }

    func testNavigationDirectionRespectsEnabledModesAndModifiers() {
        let cases: [(CGKeyCode, CGEventFlags, Bool, Bool, SpaceNavigationDirection?)] = [
            (123, [], true, false, .left), (124, [], true, false, .right),
            (125, [], true, false, .down), (126, [], true, false, .up),
            (4, [], false, true, .left), (37, [], false, true, .right),
            (38, [], false, true, .down), (40, [], false, true, .up),
            (123, .maskCommand, true, false, nil), (123, [], false, false, nil),
            (6, [], true, true, nil)
        ]

        for (keyCode, flags, arrows, vim, expected) in cases {
            XCTAssertEqual(
                HUDInput.navigationDirection(
                    keyCode: keyCode,
                    flags: flags,
                    useArrowKeys: arrows,
                    useVimKeys: vim
                ),
                expected
            )
        }
    }

    func testAccessibilityRevocationNotifiesOwner() {
        let input = HUDInput(panel: nil)
        let revoked = expectation(description: "accessibility revocation")
        input.updateVisibility(true)
        input.onAccessibilityRevoked = { revoked.fulfill() }

        input.handleAccessibilityState(isTrusted: false)

        wait(for: [revoked], timeout: 0.1)
    }

    func testReopeningWhileUntrustedNotifiesEachPresentation() {
        let input = HUDInput(panel: nil)
        var notificationCount = 0
        input.onAccessibilityRevoked = { notificationCount += 1 }

        input.updateVisibility(true)
        input.handleAccessibilityState(isTrusted: false)
        input.updateVisibility(false)
        input.updateVisibility(true)
        input.handleAccessibilityState(isTrusted: false)

        XCTAssertEqual(notificationCount, 2)
    }

    func testKeyboardCaptureFailsOpenWhenAccessibilityIsRevoked() {
        XCTAssertFalse(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: false,
                isVisible: true,
                isPinned: false,
                type: .keyDown,
                action: .navigate(direction: .left)
            )
        )
    }

    func testPinnedHUDOnlyConsumesRecognizedKeyDownActions() {
        XCTAssertFalse(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: true,
                isPinned: true,
                type: .keyDown,
                action: .none
            )
        )
        XCTAssertFalse(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: true,
                isPinned: true,
                type: .keyUp,
                action: .navigate(direction: .left)
            )
        )
        XCTAssertTrue(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: true,
                isPinned: true,
                type: .keyDown,
                action: .navigate(direction: .left)
            )
        )
    }

    func testUnpinnedHUDConsumesKeyboardEventsWhileVisible() {
        XCTAssertTrue(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: true,
                isPinned: false,
                type: .keyDown,
                action: .none
            )
        )
        XCTAssertTrue(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: true,
                isPinned: false,
                type: .keyUp,
                action: .none
            )
        )
    }

    func testKeyboardTapRecoveryRepairsInvalidAndDisabledTaps() {
        XCTAssertEqual(
            HUDInput.keyboardTapRecoveryAction(
                isTrusted: false,
                hasTap: true,
                tapIsValid: true,
                tapIsEnabled: true
            ),
            .remove
        )
        XCTAssertEqual(
            HUDInput.keyboardTapRecoveryAction(
                isTrusted: true,
                hasTap: false,
                tapIsValid: false,
                tapIsEnabled: false
            ),
            .install
        )
        XCTAssertEqual(
            HUDInput.keyboardTapRecoveryAction(
                isTrusted: true,
                hasTap: true,
                tapIsValid: false,
                tapIsEnabled: false
            ),
            .reinstall
        )
        XCTAssertEqual(
            HUDInput.keyboardTapRecoveryAction(
                isTrusted: true,
                hasTap: true,
                tapIsValid: true,
                tapIsEnabled: false
            ),
            .reenable
        )
    }
}
