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
        let cases: [(CGKeyCode, HUDCommand)] = [
            (4, .left), (37, .right),
            (40, .up), (38, .down),
            (123, .left), (124, .right),
            (125, .down), (126, .up),
            (3, .first), (14, .last), (15, .recent),
            (53, .close), (8, .close),
            (0, .newSpace), (17, .newSpaceAndFocus), (13, .deleteSpace),
            (11, .layoutBSP), (1, .layoutStack),
            (32, .layoutFloat),
        ]

        for (keyCode, expected) in cases {
            XCTAssertEqual(
                defaults.command(for: keyCode, flags: []),
                expected
            )
        }
        XCTAssertNil(defaults.command(for: 45, flags: [])) // n
        XCTAssertNil(defaults.command(for: 4, flags: .maskCommand))
        XCTAssertNil(defaults.command(for: 4, flags: .maskShift))
        XCTAssertEqual(defaults[.moveSpaceBack], [], "move-space keys start unbound")
        XCTAssertEqual(defaults[.moveSpaceForward], [])
        XCTAssertEqual(defaults[.cycleLayout], [])
    }

    func testCustomHUDKeysReplaceDefaults() throws {
        var bindings = HUDKeyBindings.default
        bindings[.left] = [
            try XCTUnwrap(Hotkey.parseHotkey("x")),
            try XCTUnwrap(Hotkey.parseHotkey("cmd+h")),
        ]

        XCTAssertEqual(
            bindings.command(for: 7, flags: []),
            .left
        )
        XCTAssertEqual(
            bindings.command(for: 4, flags: .maskCommand),
            .left
        )
        XCTAssertNil(bindings.command(for: 4, flags: []))
        XCTAssertNil(bindings.command(for: 123, flags: []))
    }

    func testMoveSpaceAndCycleLayoutBindingsMatchTheirCommands() throws {
        var bindings = HUDKeyBindings()
        bindings[.moveSpaceBack] = [try XCTUnwrap(Hotkey.parseHotkey("ctrl+left"))]
        bindings[.moveSpaceForward] = [try XCTUnwrap(Hotkey.parseHotkey("ctrl+right"))]
        bindings[.cycleLayout] = [try XCTUnwrap(Hotkey.parseHotkey("ctrl+l"))]

        XCTAssertEqual(bindings.command(for: 123, flags: .maskControl), .moveSpaceBack)
        XCTAssertEqual(bindings.command(for: 124, flags: .maskControl), .moveSpaceForward)
        XCTAssertEqual(bindings.command(for: 37, flags: .maskControl), .cycleLayout)
    }

    /// Scalar `[behavior]` keys were checked before `[hudKeys]`, so a legacy
    /// binding for a command beats a table binding for that same command.
    func testLegacyScalarBindingWinsOverTableBindingForTheSameCommand() throws {
        var config = SpacemapConfig.default
        config.hudNewSpaceHotkey = try XCTUnwrap(Hotkey.parseHotkey("x"))
        var keys = HUDKeyBindings.default
        keys[.newSpace] = [try XCTUnwrap(Hotkey.parseHotkey("y"))]
        config.hudKeys = keys

        let bindings = config.hudKeyBindings

        XCTAssertEqual(bindings.command(for: 7, flags: []), .newSpace, "the legacy scalar key stays live")
        XCTAssertEqual(bindings.command(for: 16, flags: []), .newSpace, "the table binding stays live")
        XCTAssertEqual(
            bindings.legacyCommand(for: 7, flags: []),
            .newSpace,
            "the legacy scalar is matched before the table"
        )
    }

    /// A legacy key also beats a table binding on the same key for a different
    /// command, because scalars used to be matched before the whole table.
    func testLegacyScalarKeyBeatsAnyTableBindingOnTheSameKey() throws {
        var config = SpacemapConfig.default
        config.hudDeleteSpaceHotkey = try XCTUnwrap(Hotkey.parseHotkey("x"))
        var keys = HUDKeyBindings.default
        keys[.left] = [try XCTUnwrap(Hotkey.parseHotkey("x"))]
        config.hudKeys = keys

        XCTAssertEqual(config.hudKeyBindings.command(for: 7, flags: []), .deleteSpace)
    }

    /// Settings seeds its key map from this fold, then writes the map back with
    /// the scalar keys unbound, so both bindings must survive the fold.
    func testFoldingLegacyKeepsScalarAndTableBindings() throws {
        var config = SpacemapConfig.default
        config.hudNewSpaceHotkey = try XCTUnwrap(Hotkey.parseHotkey("x"))
        config.hudKeys[.newSpace] = [try XCTUnwrap(Hotkey.parseHotkey("y"))]

        let folded = config.hudKeyBindings.foldingLegacy()

        XCTAssertEqual(folded[.newSpace], [
            try XCTUnwrap(Hotkey.parseHotkey("x")),
            try XCTUnwrap(Hotkey.parseHotkey("y")),
        ])
        XCTAssertEqual(folded.command(for: 7, flags: []), .newSpace)
        XCTAssertEqual(folded.command(for: 16, flags: []), .newSpace)
        XCTAssertNil(folded.legacyCommand(for: 7, flags: []),
                     "the folded map leaves the scalar layer empty")
    }

    /// A scalar that repeats a table binding must fold to one row, or a
    /// settings save writes the same shortcut twice.
    func testFoldingLegacySkipsAScalarThatRepeatsATableBinding() throws {
        var config = SpacemapConfig.default
        let key = try XCTUnwrap(Hotkey.parseHotkey("x"))
        config.hudNewSpaceHotkey = key
        config.hudKeys[.newSpace] = [key]

        let folded = config.hudKeyBindings.foldingLegacy()

        XCTAssertEqual(folded[.newSpace], [key])
    }

    func testSpecificBindingBeatsTheDefaultBindingOfTheSameCommand() throws {
        var config = SpacemapConfig.default
        var keys = HUDKeyBindings.default
        keys[.left] = [try XCTUnwrap(Hotkey.parseHotkey("x"))]
        config.hudKeys = keys

        XCTAssertEqual(config.hudKeyBindings.command(for: 7, flags: []), .left)
        XCTAssertNil(config.hudKeyBindings.command(for: 4, flags: []),
                     "replacing an action's bindings drops the old default")
    }

    func testHandleHUDKeyDownUsesConfiguredHUDKeys() {
        let input = HUDInput(panel: nil)
        input.updateConfig(hudKeys: .default)
        func event(_ key: CGKeyCode, flags: CGEventFlags = []) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
            event.flags = flags
            return event
        }

        XCTAssertEqual(input.handleHUDKeyDown(event(4)), .command(.left))
        XCTAssertEqual(input.handleHUDKeyDown(event(53)), .command(.close))
        XCTAssertEqual(input.handleHUDKeyDown(event(0)), .command(.newSpace))
        XCTAssertEqual(input.handleHUDKeyDown(event(32)), .command(.layoutFloat))
        XCTAssertEqual(input.handleHUDKeyDown(event(45)), HUDKeyPress.none)
        XCTAssertEqual(input.handleHUDKeyDown(event(43, flags: .maskCommand)), .showSettings)
        XCTAssertEqual(input.handleHUDKeyDown(event(43)), HUDKeyPress.none,
                       "settings needs the command modifier")
    }

    func testNumberJumpSitsBetweenLegacyAndTableBindings() {
        let input = HUDInput(panel: nil)
        var keys = HUDKeyBindings.default
        keys[.left] = [HotkeyConfig(key: .keyCode(18), modifiers: [])]
        input.updateConfig(hudKeys: keys, jumpToSpaceEnabled: true)
        func event(_ key: CGKeyCode) -> CGEvent {
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
        }

        XCTAssertEqual(input.handleHUDKeyDown(event(18)), .number(1),
                       "a jumpable digit still wins over a table binding")
    }

    /// The tap checks the legacy scalars before the table, so a scalar key
    /// wins even when a table action for another command lists the same key.
    func testHandleHUDKeyDownMatchesLegacyScalarBeforeTheTable() throws {
        let input = HUDInput(panel: nil)
        var config = SpacemapConfig.default
        config.hudDeleteSpaceHotkey = try XCTUnwrap(Hotkey.parseHotkey("x"))
        var keys = HUDKeyBindings.default
        keys[.left] = [try XCTUnwrap(Hotkey.parseHotkey("x"))]
        config.hudKeys = keys
        input.updateConfig(hudKeys: config.hudKeyBindings)
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 7, keyDown: true))
        event.flags = []

        XCTAssertEqual(input.handleHUDKeyDown(event), .command(.deleteSpace),
                       "swapping the legacy and table layers must fail here")
    }

    /// Order is legacy scalars, then number jumps, then the table.
    func testHandleHUDKeyDownKeepsNumberJumpBetweenBothBindingLayers() throws {
        let input = HUDInput(panel: nil)
        var config = SpacemapConfig.default
        config.hudDeleteSpaceHotkey = try XCTUnwrap(Hotkey.parseHotkey("1"))
        var keys = HUDKeyBindings.default
        keys[.left] = [try XCTUnwrap(Hotkey.parseHotkey("2"))]
        config.hudKeys = keys
        input.updateConfig(hudKeys: config.hudKeyBindings, jumpToSpaceEnabled: true)
        func event(_ key: CGKeyCode) -> CGEvent {
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
        }

        XCTAssertEqual(input.handleHUDKeyDown(event(18)), .command(.deleteSpace),
                       "a legacy scalar on a digit is matched before the jump")
        XCTAssertEqual(input.handleHUDKeyDown(event(19)), .number(2),
                       "the jump still beats a table binding on a digit")
    }

    func testNavigateToFirstAndLastMoveAcrossUnifiedGrid() {
        let input = HUDInput(panel: nil)
        var config = SpacemapConfig.default
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
        var config = SpacemapConfig.default
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

    func testHUDKeyBindingMatchesWhenBindingCarriesNonRelevantFlags() {
        var bindings = HUDKeyBindings.default
        bindings[.left] = [
            HotkeyConfig(key: .keyCode(7), modifiers: [.maskCommand, .maskNumericPad])
        ]

        XCTAssertEqual(
            bindings.command(for: 7, flags: [.maskCommand]),
            .left,
            "a non-relevant flag on the binding must not block the match"
        )
    }

    func testHUDKeyBindingForFunctionKeyMatchesHardwareFnFlag() {
        var bindings = HUDKeyBindings.default
        bindings[.left] = [HotkeyConfig(key: .keyCode(100), modifiers: [])]
        XCTAssertEqual(
            bindings.command(for: 100, flags: [.maskSecondaryFn]),
            .left,
            "hardware fn on a bare F-key binding is the same physical key"
        )

        bindings[.left] = [HotkeyConfig(key: .keyCode(100), modifiers: [.maskControl])]
        XCTAssertEqual(
            bindings.command(for: 100, flags: [.maskControl, .maskSecondaryFn]),
            .left
        )

        bindings[.left] = [HotkeyConfig(key: .keyCode(100), modifiers: [.maskSecondaryFn])]
        XCTAssertNil(
            bindings.command(for: 100, flags: []),
            "an explicit fn binding still requires fn"
        )
        XCTAssertEqual(
            bindings.command(for: 100, flags: [.maskSecondaryFn]),
            .left
        )

        bindings[.left] = [HotkeyConfig(key: .keyCode(0), modifiers: [])]
        XCTAssertNil(
            bindings.command(for: 0, flags: [.maskSecondaryFn]),
            "hardware fn is not normalized away for non-function keys"
        )
    }

    /// One keypress, one command: every command reaches the controller through
    /// the single `perform` entry point exactly once.
    func testEveryCommandIsHandedToTheControllerOnceThroughPerform() throws {
        let input = HUDInput(
            panel: nil,
            tapFactory: { _, _, _, _, _, _ in makeFakeEventTapPort() },
            relaunch: {}
        )
        input.accessibilityTrustProvider = { true }
        input.reconcileSettingsKeyMonitor()
        input.updateVisibility(true)
        let recorder = RecordingHUDInputDelegate()
        input.delegate = recorder

        // Every command takes its own key, outside the ⌘, and digit ranges.
        let commands = HUDCommand.allCases
        let keyCodes = (0..<commands.count).map { CGKeyCode($0) }
        var bindings = HUDKeyBindings()
        for (command, keyCode) in zip(commands, keyCodes) {
            bindings[command] = [HotkeyConfig(key: .keyCode(keyCode), modifiers: [])]
        }
        input.updateConfig(hudKeys: bindings)

        for keyCode in keyCodes {
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
            event.flags = []
            XCTAssertNil(
                input.handleTapEvent(type: .keyDown, event: event),
                "a matched HUD key must be consumed"
            )
        }
        waitUntil("every command dispatched") {
            recorder.commands.count == commands.count
        }

        XCTAssertEqual(recorder.commands, commands, "each keypress runs its command exactly once")
        input.stop()
    }

    /// Scalar `[behavior]` keys reach the controller as the same commands the
    /// table binds, so one path serves both config shapes.
    func testLegacyScalarKeyDispatchesItsCommandThroughPerform() throws {
        let input = HUDInput(
            panel: nil,
            tapFactory: { _, _, _, _, _, _ in makeFakeEventTapPort() },
            relaunch: {}
        )
        input.accessibilityTrustProvider = { true }
        input.reconcileSettingsKeyMonitor()
        input.updateVisibility(true)
        let recorder = RecordingHUDInputDelegate()
        input.delegate = recorder

        var config = SpacemapConfig.default
        config.hudMoveSpaceForwardHotkey = HotkeyConfig(key: .keyCode(102), modifiers: [.maskControl])
        input.updateConfig(hudKeys: config.hudKeyBindings)

        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 102, keyDown: true))
        event.flags = .maskControl
        _ = input.handleTapEvent(type: .keyDown, event: event)
        waitUntil("legacy scalar dispatch") { recorder.commands.count == 1 }

        XCTAssertEqual(recorder.commands, [.moveSpaceForward])
        input.stop()
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

/// A real `CFMachPort` shaped like a tap, so the host install path runs
/// without accessibility permission or a real session event tap.
private func makeFakeEventTapPort() -> CFMachPort? {
    var context = CFMachPortContext(
        version: 0,
        info: nil,
        retain: nil,
        release: nil,
        copyDescription: nil
    )
    return CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, &context, nil)
}

/// Records the commands HUDInput hands to its controller.
private final class RecordingHUDInputDelegate: HUDInputDelegate {
    private(set) var commands: [HUDCommand] = []

    func perform(_ command: HUDCommand) {
        commands.append(command)
    }
}

extension HUDInputTests {
    func waitUntil(
        _ message: String,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(message)", file: file, line: line)
    }
}
