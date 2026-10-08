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

    func testExtendedKeyActionMapsKeysAndRespectsToggleAndModifiers() {
        let cases: [(CGKeyCode, CGEventFlags, Bool, InputAction?)] = [
            (45, [], true, .navigate(direction: .right)), // n
            (35, [], true, .navigate(direction: .left)),  // p
            (3, [], true, .navigateFirst),                // f
            (14, [], true, .navigateLast),                // e
            (15, [], true, .focusRecent),                 // r
            (53, [], true, .closeHUD),                    // esc
            (8, [], true, .closeHUD),                     // c
            (45, [], false, nil),
            (15, [], false, nil),
            (45, .maskCommand, true, nil),
            (45, .maskControl, true, nil),
            (45, .maskAlternate, true, nil),
            (15, .maskCommand, true, nil),
            (15, .maskControl, true, nil),
            (15, .maskAlternate, true, nil),
            (45, .maskShift, true, .navigate(direction: .right)),
            (12, [], true, nil)                            // q
        ]

        for (keyCode, flags, enabled, expected) in cases {
            XCTAssertEqual(
                HUDInput.extendedKeyAction(
                    keyCode: keyCode,
                    flags: flags,
                    useExtendedKeys: enabled
                ),
                expected
            )
        }
    }

    func testHandleHUDKeyDownReturnsExtendedActionsWhenEnabled() {
        let input = HUDInput(panel: nil)
        input.updateConfig(useArrowKeys: false, useVimKeys: false, useExtendedKeys: true)
        func event(_ key: CGKeyCode) -> CGEvent {
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
        }

        XCTAssertEqual(input.handleHUDKeyDown(event(45)), .navigate(direction: .right))
        XCTAssertEqual(input.handleHUDKeyDown(event(35)), .navigate(direction: .left))
        XCTAssertEqual(input.handleHUDKeyDown(event(3)), .navigateFirst)
        XCTAssertEqual(input.handleHUDKeyDown(event(14)), .navigateLast)
        XCTAssertEqual(input.handleHUDKeyDown(event(15)), .focusRecent)
        XCTAssertEqual(input.handleHUDKeyDown(event(53)), .closeHUD)
        XCTAssertEqual(input.handleHUDKeyDown(event(8)), .closeHUD)
    }

    func testNavigateToFirstAndLastMoveAcrossUnifiedGrid() {
        let input = HUDInput(panel: nil)
        var config = GridConfig.default
        config.showMode = .active
        config.maxSpaces = 8
        let spaces = [
            YabaiSpace(id: 1, index: 3, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 5, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 3, index: 8, display: 1, hasFocus: false, isVisible: nil, label: nil)
        ]
        input.currentState = GridState(config: config, spaces: spaces, windows: [], displayBounds: .zero, focusedIndex: 5)
        input.lastFocusedSpaceIndex = 5

        input.navigateToFirst()

        XCTAssertEqual(input.lastFocusedSpaceIndex, 3)

        input.navigateToLast()

        XCTAssertEqual(input.lastFocusedSpaceIndex, 8)
    }

    func testNavigateToFirstAndLastStayWithinFocusedDisplayInSeparateMode() {
        let input = HUDInput(panel: nil)
        var config = GridConfig.default
        config.multiMonitorHUDMode = .separate
        config.maxSpaces = 8
        let spaces = [
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 2, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 3, index: 4, display: 2, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 4, index: 7, display: 2, hasFocus: false, isVisible: nil, label: nil)
        ]
        input.currentState = GridState(config: config, spaces: spaces, windows: [], displayBounds: .zero, focusedIndex: 4)
        input.lastFocusedSpaceIndex = 4

        input.navigateToLast()

        XCTAssertEqual(input.lastFocusedSpaceIndex, 7)

        input.navigateToFirst()

        XCTAssertEqual(input.lastFocusedSpaceIndex, 4)
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
