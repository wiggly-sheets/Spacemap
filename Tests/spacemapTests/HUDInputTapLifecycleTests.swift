import XCTest
import CoreGraphics
@testable import spacemap

final class HUDInputTapLifecycleTests: HUDInputTestCase {
    func testAccessibilityRevocationNotifiesOwner() {
        let input = HUDInput(panel: nil)
        var revoked = false
        input.updateVisibility(true)
        input.onAccessibilityRevoked = { revoked = true }

        input.handleAccessibilityState(isTrusted: false)

        XCTAssertTrue(revoked)
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

    func testOnlyConsumesVisibleTrustedKeyDownPressesItActsOn() {
        XCTAssertFalse(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: false,
                isVisible: true,
                isPinned: false,
                type: .keyDown,
                press: .command(.left)
            )
        )
        XCTAssertFalse(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: false,
                isPinned: false,
                type: .keyDown,
                press: .command(.left)
            )
        )
        XCTAssertFalse(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: true,
                isPinned: false,
                type: .keyDown,
                press: .none
            )
        )
        XCTAssertFalse(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: true,
                isPinned: false,
                type: .keyUp,
                press: .command(.left)
            )
        )
        XCTAssertTrue(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: true,
                isPinned: false,
                type: .keyDown,
                press: .command(.left)
            )
        )
        XCTAssertTrue(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: true,
                isPinned: false,
                type: .keyDown,
                press: .number(2)
            )
        )
        XCTAssertTrue(
            HUDInput.shouldConsumeKeyboardEvent(
                isTrusted: true,
                isVisible: true,
                isPinned: false,
                type: .keyDown,
                press: .letter("d")
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

    func testDeinitStopsTimers() {
        var input: HUDInput? = HUDInput(panel: nil)
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

    func testKeyboardTapUsesInjectedFactory() throws {
        var creations: [(CGEventTapPlacement, CGEventTapOptions, CGEventMask)] = []
        let input = HUDInput(
            panel: nil,
            tapFactory: { _, place, options, mask, _, _ in
                creations.append((place, options, mask))
                return makeFakeEventTapPort()
            }
        )
        input.accessibilityTrustProvider = { true }

        input.reconcileSettingsKeyMonitor()

        XCTAssertEqual(creations.count, 1)
        let creation = try XCTUnwrap(creations.first)
        XCTAssertEqual(creation.0, .tailAppendEventTap)
        XCTAssertEqual(creation.1, .defaultTap)
        XCTAssertEqual(creation.2, HUDInput.keyboardEventTapMask)
        XCTAssertEqual(input.tapCreationAttempts, 1)
        XCTAssertTrue(input.isKeyboardTapInstalled)

        input.stop()
        XCTAssertFalse(input.isKeyboardTapInstalled)
    }

    func testReleasedInputIsNotRetainedByTheInstalledTap() {
        var input: HUDInput? = HUDInput(
            panel: nil,
            tapFactory: { _, _, _, _, _, _ in makeFakeEventTapPort() },
            relaunch: {}
        )
        weak var weakInput = input
        input?.accessibilityTrustProvider = { true }
        input?.reconcileSettingsKeyMonitor()
        XCTAssertTrue(input?.isKeyboardTapInstalled == true)

        input?.handleAccessibilityState(isTrusted: false)
        XCTAssertFalse(input?.isKeyboardTapInstalled ?? true, "revocation must release the tap")
        input = nil

        XCTAssertNil(weakInput, "a torn-down tap must not keep HUDInput alive")
    }

    func testAccessibilityRevocationUsesInjectedRelaunchHook() {
        let relaunched = expectation(description: "injected relaunch hook runs")
        let input = HUDInput(
            panel: nil,
            tapFactory: { _, _, _, _, _, _ in makeFakeEventTapPort() },
            relaunch: { relaunched.fulfill() }
        )
        input.accessibilityTrustProvider = { true }
        input.reconcileSettingsKeyMonitor()
        XCTAssertTrue(input.isKeyboardTapInstalled)

        input.handleAccessibilityState(isTrusted: false)

        XCTAssertFalse(input.isKeyboardTapInstalled, "revocation must release the tap")
        wait(for: [relaunched], timeout: 1)
        input.stop()
    }
}
