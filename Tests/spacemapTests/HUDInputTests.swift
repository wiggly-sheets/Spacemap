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

    func testRepeatedDigitReplacesInsteadOfAppending() {
        let indices = [1, 2, 4, 10]
        XCTAssertEqual(HUDInput.appendedNumber("4", to: "", indices: indices), "4")
        XCTAssertEqual(HUDInput.appendedNumber("4", to: "4", indices: indices), "4")
        XCTAssertEqual(HUDInput.appendedNumber("0", to: "1", indices: indices), "10")
        // 3 is neither a space nor a prefix, so it starts a fresh entry.
        XCTAssertEqual(HUDInput.appendedNumber("3", to: "1", indices: indices), "3")
    }

    func testNumberOutcomeWaitsOnlyWhileALongerSpaceCouldMatch() {
        // Spaces 1...9: a single digit resolves at once.
        XCTAssertEqual(HUDInput.numberOutcome(pending: "3", indices: Array(1...9))?.mustWait, false)
        // Space 10 exists, so "1" must wait for a possible "10".
        XCTAssertEqual(
            HUDInput.numberOutcome(pending: "1", indices: Array(1...12))?.mustWait,
            true
        )
        XCTAssertEqual(
            HUDInput.numberOutcome(pending: "10", indices: Array(1...12))?.number,
            10
        )
        XCTAssertEqual(
            HUDInput.numberOutcome(pending: "10", indices: Array(1...12))?.exists,
            true
        )
        XCTAssertEqual(
            HUDInput.numberOutcome(pending: "42", indices: Array(1...12))?.exists,
            false
        )
        XCTAssertNil(HUDInput.numberOutcome(pending: "x", indices: Array(1...12)))
    }

    func testSettingsShortcutRequiresCommandSlash() {
        XCTAssertTrue(HUDInput.isSettingsShortcut(keyCode: 43, flags: .maskCommand))
        XCTAssertFalse(HUDInput.isSettingsShortcut(keyCode: 43, flags: []))
        XCTAssertFalse(HUDInput.isSettingsShortcut(keyCode: 0, flags: .maskCommand))
    }

    func testDefaultHUDKeysRouteVimArrowsAndActions() {
        let defaults = HUDKeyBindings.default
        let cases: [(CGKeyCode, InputAction)] = [
            (4, .navigate(direction: .left)), (37, .navigate(direction: .right)),
            (40, .navigate(direction: .up)), (38, .navigate(direction: .down)),
            (123, .navigate(direction: .left)), (124, .navigate(direction: .right)),
            (125, .navigate(direction: .down)), (126, .navigate(direction: .up)),
            (3, .navigateFirst), (14, .navigateLast), (15, .focusRecent),
            (53, .closeHUD), (8, .closeHUD),
            (0, .createSpace), (17, .createAndFocusNewestSpace), (13, .destroyCurrentSpace),
            (11, .setSpaceLayout(.bsp)), (1, .setSpaceLayout(.stack)),
            (32, .setSpaceLayout(.float)),
        ]

        for (keyCode, expected) in cases {
            XCTAssertEqual(
                HUDInput.hudKeyAction(keyCode: keyCode, flags: [], bindings: defaults),
                expected
            )
        }
        XCTAssertNil(HUDInput.hudKeyAction(keyCode: 45, flags: [], bindings: defaults)) // n
        XCTAssertNil(HUDInput.hudKeyAction(keyCode: 4, flags: .maskCommand, bindings: defaults))
        XCTAssertNil(HUDInput.hudKeyAction(keyCode: 4, flags: .maskShift, bindings: defaults))
    }

    func testCustomHUDKeysReplaceDefaults() throws {
        var bindings = HUDKeyBindings.default
        bindings[.left] = [
            try XCTUnwrap(Hotkey.parseHotkey("x")),
            try XCTUnwrap(Hotkey.parseHotkey("cmd+h")),
        ]

        XCTAssertEqual(
            HUDInput.hudKeyAction(keyCode: 7, flags: [], bindings: bindings),
            .navigate(direction: .left)
        )
        XCTAssertEqual(
            HUDInput.hudKeyAction(keyCode: 4, flags: .maskCommand, bindings: bindings),
            .navigate(direction: .left)
        )
        XCTAssertNil(HUDInput.hudKeyAction(keyCode: 4, flags: [], bindings: bindings))
        XCTAssertNil(HUDInput.hudKeyAction(keyCode: 123, flags: [], bindings: bindings))
    }

    func testHandleHUDKeyDownUsesConfiguredHUDKeys() {
        let input = HUDInput(panel: nil)
        input.updateConfig(hudKeys: .default)
        func event(_ key: CGKeyCode) -> CGEvent {
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
        }

        XCTAssertEqual(input.handleHUDKeyDown(event(4)), .navigate(direction: .left))
        XCTAssertEqual(input.handleHUDKeyDown(event(53)), .closeHUD)
        XCTAssertEqual(input.handleHUDKeyDown(event(0)), .createSpace)
        XCTAssertEqual(input.handleHUDKeyDown(event(32)), .setSpaceLayout(.float))
        XCTAssertEqual(input.handleHUDKeyDown(event(45)), .none)
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

    func testOnlyConsumesVisibleTrustedKeyDownActionsItActsOn() {
        XCTAssertFalse(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: false,
                isVisible: true,
                isPinned: false,
                type: .keyDown,
                action: .navigate(direction: .left)
            )
        )
        XCTAssertFalse(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: false,
                isPinned: false,
                type: .keyDown,
                action: .navigate(direction: .left)
            )
        )
        XCTAssertFalse(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: true,
                isPinned: false,
                type: .keyDown,
                action: .none
            )
        )
        XCTAssertFalse(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: true,
                isPinned: false,
                type: .keyUp,
                action: .navigate(direction: .left)
            )
        )
        XCTAssertTrue(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: true,
                isPinned: false,
                type: .keyDown,
                action: .navigate(direction: .left)
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

    func testAutoHideSuppressionCancelsAndRestoresTheTimer() {
        let input = HUDInput(panel: nil)
        input.autoHideTimeout = 30
        input.resetAutoHideTimer()
        XCTAssertTrue(input.isAutoHideScheduled)

        input.setAutoHideSuppressed(true)
        XCTAssertFalse(input.isAutoHideScheduled,
            "a window drag must invalidate the pending auto-hide")

        input.setAutoHideSuppressed(false)
        XCTAssertTrue(input.isAutoHideScheduled)
        input.stop()
        XCTAssertFalse(input.isAutoHideScheduled)
    }

    func testPanelDragDisarmsAndRearmsAutoHide() {
        let input = HUDInput(panel: nil)
        input.autoHideTimeout = 30
        input.resetAutoHideTimer()
        XCTAssertTrue(input.isAutoHideScheduled)

        input.beginPanelDrag(start: .zero, panelOrigin: .zero)
        XCTAssertTrue(input.panelDragActive)
        XCTAssertFalse(input.isAutoHideScheduled,
            "an armed auto-hide timer must be invalidated on mouse down")

        XCTAssertFalse(input.endPanelDrag())
        XCTAssertFalse(input.panelDragActive)
        XCTAssertTrue(input.isAutoHideScheduled,
            "auto-hide re-arms once the panel drag ends")
        input.stop()
    }

    func testDeinitStopsTimers() {
        var input: HUDInput? = HUDInput(panel: nil)
        input?.autoHideTimeout = 30
        input?.resetAutoHideTimer()
        input?.startPollTimer()
        let stopped = expectation(description: "deinit reached stop()")
        input?.onStopForTesting = { timersCleared in
            XCTAssertTrue(timersCleared, "deinit must leave no scheduled timers")
            stopped.fulfill()
        }

        input = nil

        wait(for: [stopped], timeout: 1)
    }

    func testPermissionProbeReportsAStallInsteadOfBlockingTheCaller() {
        let probe = PermissionProbe()
        let providerEntered = expectation(description: "provider is running")
        let release = DispatchSemaphore(value: 0)
        let first = expectation(description: "hung provider eventually answers")
        // A negative timeout forces the in-flight branch without sleeping.
        probe.check(timeout: -1, provider: {
            providerEntered.fulfill()
            _ = release.wait(timeout: .now() + 2)
            return true
        }) { trusted in
            XCTAssertTrue(trusted)
            first.fulfill()
        }
        wait(for: [providerEntered], timeout: 1)

        let stalled = expectation(description: "second call reports no permission")
        probe.check(timeout: -1, provider: {
            XCTFail("a stalled probe must not start another provider")
            return true
        }) { trusted in
            XCTAssertFalse(trusted)
            XCTAssertTrue(probe.isStalled)
            stalled.fulfill()
        }
        wait(for: [stalled], timeout: 1)

        release.signal()
        wait(for: [first], timeout: 2)
        XCTAssertFalse(probe.isStalled, "the answered probe must clear the stall flag")
    }

    func testDisabledKeyboardTapRechecksTrustAndNotifiesRevocation() {
        let input = HUDInput(panel: nil)
        input.updateVisibility(true)
        input.accessibilityTrustProvider = { false }
        let revoked = expectation(description: "accessibility revocation reported")
        input.onAccessibilityRevoked = { revoked.fulfill() }

        input.handleDisabledKeyboardTap()

        wait(for: [revoked], timeout: 1)
        XCTAssertFalse(input.cachedAccessibilityTrusted,
            "the tap-disabled path must refresh the cached trust value")
    }
}
