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
            (35, .previousSpace), (45, .nextSpace),
        ]

        for (keyCode, expected) in cases {
            XCTAssertEqual(
                defaults.command(for: keyCode, flags: []),
                expected
            )
        }
        XCTAssertNil(defaults.command(for: 12, flags: [])) // q
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
        XCTAssertEqual(input.handleHUDKeyDown(event(45)), .command(.nextSpace))
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

    func testTypedLettersJumpOnlyWhenNoBindingConsumedTheKey() {
        let input = HUDInput(panel: nil)
        func event(_ key: CGKeyCode) -> CGEvent {
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
        }
        input.updateConfig(hudKeys: .default, jumpToSpaceEnabled: true)

        XCTAssertEqual(input.handleHUDKeyDown(event(4)), .command(.left),
                       "a bound letter still runs its HUD command")
        XCTAssertEqual(input.handleHUDKeyDown(event(2)), .letter("d"),
                       "an unbound letter starts a typed jump")
        XCTAssertEqual(input.handleHUDKeyDown(event(18)), .number(1),
                       "a digit still classifies as a number")

        input.updateConfig(hudKeys: .default, jumpToSpaceEnabled: false)

        XCTAssertEqual(input.handleHUDKeyDown(event(2)), .letter("d"),
                       "name jumps do not need the number jump")
        XCTAssertEqual(input.handleHUDKeyDown(event(18)), HUDKeyPress.none,
                       "with the number jump off a digit reaches the focused app")
    }

    func testTypedLettersPassThroughWhenNameJumpIsOff() {
        let input = HUDInput(panel: nil)
        func event(_ key: CGKeyCode) -> CGEvent {
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
        }
        input.updateConfig(
            hudKeys: .default,
            jumpToSpaceEnabled: true,
            fuzzySpaceJumpEnabled: false
        )

        XCTAssertEqual(input.handleHUDKeyDown(event(2)), HUDKeyPress.none,
                       "an unbound letter reaches the focused app when name jumps are off")
        XCTAssertEqual(input.handleHUDKeyDown(event(18)), .number(1),
                       "number jumps still work on their own toggle")
    }

    /// The tap-level guard is what keeps a letter from being swallowed when the
    /// jump is off; classification alone is not enough.
    func testTapPassesLettersThroughWhenTheJumpIsDisabled() throws {
        let input = makeTypingInput(
            names: [1: "Web"],
            jumpToSpaceEnabled: true,
            fuzzySpaceJumpEnabled: false
        )
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 2, keyDown: true))
        event.flags = []

        let returned = try XCTUnwrap(input.handleTapEvent(type: .keyDown, event: event))

        XCTAssertTrue(returned.takeUnretainedValue() === event,
                      "a disabled jump must not consume the letter")
        input.stop()
    }

    /// Shift is a typing modifier for the letter path, so a binding on the bare
    /// key still owns a shift chord.
    func testShiftLettersRunTheBareBindingInsteadOfStartingAPrefix() {
        let input = makeTypingInput(names: [1: "Web"])
        input.updateConfig(hudKeys: .default, jumpToSpaceEnabled: true)
        let recorder = RecordingHUDInputDelegate()
        input.delegate = recorder
        var typed: [String?] = []
        input.onTypedText = { typed.append($0?.text) }

        press(input, 13, flags: .maskShift) // Shift+W: default binds w to deleteSpace

        waitUntil("the default w binding runs") { recorder.commands == [.deleteSpace] }
        XCTAssertEqual(typed.compactMap { $0 }, [], "a bound shift chord must not start a prefix")
        input.stop()
    }

    func testEscapeStillClosesWhenItIsBound() {
        let input = HUDInput(panel: nil)
        let escape = CGEvent(keyboardEventSource: nil, virtualKey: HUDInput.escapeKeyCode, keyDown: true)!

        input.updateConfig(hudKeys: .default, jumpToSpaceEnabled: true)

        XCTAssertEqual(input.handleHUDKeyDown(escape), .command(.close),
                       "the binding table runs before typed-prefix editing")
    }

    func testNameMatchOutcomeRanksExactPrefixBeforeSubsequence() {
        // 2 is a prefix match, 1 only a subsequence: the prefix wins.
        let ranked = HUDInput.nameMatchOutcome(prefix: "wb", names: [1: "Wobble", 2: "Wb"])
        XCTAssertEqual(ranked.matches, [2, 1])
        XCTAssertFalse(ranked.mustWait, "one exact prefix decides the space")

        let tied = HUDInput.nameMatchOutcome(prefix: "w", names: [5: "Web", 2: "Wobble", 9: "   "])
        XCTAssertEqual(tied.matches, [2, 5], "prefix matches ascend by index; blank names never match")
        XCTAssertTrue(tied.mustWait, "two prefix matches leave room for a longer prefix")

        XCTAssertEqual(HUDInput.nameMatchOutcome(prefix: "Web", names: [3: " web "]).matches, [3],
                       "matching trims and ignores case")
        XCTAssertEqual(HUDInput.nameMatchOutcome(prefix: "zz", names: [1: "Web"]).matches, [])
    }

    func testUniqueNameMatchJumpsImmediately() {
        let input = makeTypingInput(names: [2: "Design", 3: "Web"])
        var jumped: [Int] = []
        var typed: [String] = []
        input.onFocusSpaceChanged = { jumped.append($0) }
        input.onTypedText = { if let text = $0?.text { typed.append(text) } }

        press(input, 2) // d

        waitUntil("unique match jumps") { jumped == [2] }
        XCTAssertEqual(typed.first, "d → Design", "feedback shows the matched name")
        input.stop()
    }

    /// A held key repeats keyDown. A repeat must neither extend the prefix nor
    /// re-run the jump the first press already made.
    func testRepeatedLetterKeyDownAddsNoLetterAndNoSecondJump() {
        let input = makeTypingInput(names: [1: "Design", 2: "Web"])
        var typed: [String?] = []
        var jumped: [Int] = []
        input.onFocusSpaceChanged = { jumped.append($0) }
        input.onTypedText = { typed.append($0?.text) }

        press(input, 2) // d: unique, jumps and clears the prefix
        waitUntil("the unique match jumps") { jumped == [1] }
        let repeatResult = press(input, 2, autorepeat: true)

        XCTAssertTrue(repeatResult == nil, "a repeated letter is consumed as a no-op")
        press(input, 14) // e: a fresh prefix, not a continuation of "d"
        waitUntil("the next letter starts a fresh prefix") { typed.last == "e" }
        XCTAssertEqual(jumped, [1], "a held key never re-fires the jump")
        input.stop()
    }

    func testAmbiguousPrefixCollectsUntilOneNameMatches() {
        let input = makeTypingInput(names: [1: "Wrench", 2: "Web"])
        var jumped: [Int] = []
        var typed: [String] = []
        input.onFocusSpaceChanged = { jumped.append($0) }
        input.onTypedText = { if let text = $0?.text { typed.append(text) } }

        press(input, 13) // w: shared by both names
        press(input, 14) // e: only Web is left

        waitUntil("the second letter resolves the prefix") { jumped == [2] }
        XCTAssertEqual(typed, ["w", "we → Web"])
        input.stop()
    }

    /// A bound command owns its keystroke, so a prefix that was still waiting
    /// for the ambiguity timer must not survive it.
    func testABoundCommandCancelsAPendingLetterPrefix() {
        let input = makeTypingInput(names: [1: "Xcode", 2: "Xylophone"])
        input.updateConfig(hudKeys: .default, jumpToSpaceEnabled: true)
        let recorder = RecordingHUDInputDelegate()
        input.delegate = recorder
        var typed: [String?] = []
        var jumped: [Int] = []
        input.onTypedText = { typed.append($0?.text) }
        input.onFocusSpaceChanged = { jumped.append($0) }

        press(input, 7) // x: ambiguous, waits 0.3s
        waitUntil("prefix shown") { typed == ["x"] }
        press(input, 37) // l: default binds it to right

        waitUntil("the command ran") { recorder.commands == [.right] }
        XCTAssertEqual(typed, ["x", nil], "the command clears the pending prefix at once")
        press(input, 12) // q: must start a fresh prefix, not continue "x"
        waitUntil("the next letter starts a fresh prefix") { typed.last == "q" }
        XCTAssertEqual(typed, ["x", nil, "q"])
        XCTAssertEqual(jumped, [], "the pending prefix must not jump after the command")
        input.stop()
    }

    func testSubsequenceMatchJumps() {
        let input = makeTypingInput(names: [1: "Web Browser", 2: "Wrench"])
        var jumped: [Int] = []
        input.onFocusSpaceChanged = { jumped.append($0) }

        press(input, 13) // w
        press(input, 11) // b: in order inside "Web Browser", absent from "Wrench"

        waitUntil("subsequence match jumps") { jumped == [1] }
        input.stop()
    }

    func testNoNameMatchKeepsCollectingWithoutJumping() {
        let input = makeTypingInput(names: [1: "Web"])
        var jumped: [Int] = []
        var typed: [HUDTypedFeedback] = []
        input.onFocusSpaceChanged = { jumped.append($0) }
        input.onTypedText = { if let feedback = $0 { typed.append(feedback) } }

        press(input, 6) // z: no space name contains it
        press(input, 13) // w

        waitUntil("both letters reached the overlay") { typed.last?.text == "zw" }
        XCTAssertEqual(typed.last?.matches, false, "a prefix with no candidate is marked as a miss")
        XCTAssertEqual(jumped, [], "a prefix that matches nothing never jumps")
        input.stop()
    }

    /// A name outlives its space in config, so the current topology decides
    /// what may match.
    func testNameForADeletedSpaceNeverMatches() {
        let input = makeTypingInput(names: [2: "Design"])
        var config = SpacemapConfig.default
        config.spaceNames = [2: "Design"]
        // Space 2 is gone; only its name is left in config.
        input.currentState = GridState(
            config: config,
            spaces: [],
            windows: [],
            displayBounds: .zero,
            focusedIndex: nil
        )
        var typed: [HUDTypedFeedback] = []
        var jumped: [Int] = []
        input.onTypedText = { if let feedback = $0 { typed.append(feedback) } }
        input.onFocusSpaceChanged = { jumped.append($0) }

        press(input, 2) // d: would uniquely match the stale name

        waitUntil("the stale name shows no match") { typed.last?.text == "d" }
        XCTAssertEqual(typed.last?.matches, false, "a stale name is a miss")
        XCTAssertEqual(jumped, [], "a stale name must not jump")
        input.stop()
    }

    /// Auto naming feeds the same fuzzy candidates as typed names, using each
    /// space's leftmost window app.
    func testAutoNamingModeMatchesTheLeftmostWindowApp() {
        var safari = YabaiWindow(
            id: 1, app: "Safari", space: 1,
            frame: .init(x: 0, y: 0, w: 10, h: 10),
            isHidden: false, isMinimized: false, subLayer: "normal"
        )
        safari.role = "AXWindow"
        safari.subrole = "AXStandardWindow"
        safari.isRootWindow = true
        let input = makeTypingInput(
            names: [1: "Typed"],
            windows: [safari],
            namingMode: .auto
        )
        var jumped: [Int] = []
        input.onFocusSpaceChanged = { jumped.append($0) }

        press(input, 1) // s: matches the derived "Safari", not the typed name

        waitUntil("the derived app name jumps") { jumped == [1] }
        input.stop()
    }

    /// Entry state is applied one main-queue turn after classification, so a
    /// fast backspace must be judged against a synchronous count; otherwise it
    /// classifies as unhandled and leaks into the focused app.
    func testFastBackspaceIsCapturedBeforeThePrefixIsApplied() {
        let input = makeTypingInput(names: [1: "Notes", 2: "Nexus"])
        var typed: [String?] = []
        input.onTypedText = { typed.append($0?.text) }

        let letterConsumed = press(input, 45) == nil // n: applied on a later main-queue turn
        let backspaceConsumed = press(input, HUDInput.backspaceKeyCode) == nil

        XCTAssertTrue(letterConsumed, "the letter is captured")
        XCTAssertTrue(backspaceConsumed, "the backspace after it is captured too")
        waitUntil("the prefix is applied then deleted") { typed == ["n", nil] }
        input.stop()
    }

    func testBackspaceDeletesTheLastTypedLetter() {
        let input = makeTypingInput(names: [1: "Web A", 2: "Web B"])
        var jumped: [Int] = []
        var typed: [String] = []
        input.onFocusSpaceChanged = { jumped.append($0) }
        input.onTypedText = { if let text = $0?.text { typed.append(text) } }

        press(input, 13) // w
        press(input, 14) // e
        waitUntil("both letters reached the overlay") { typed == ["w", "we"] }
        press(input, HUDInput.backspaceKeyCode)

        waitUntil("backspace repaints the shorter prefix") { typed == ["w", "we", "w"] }
        XCTAssertEqual(jumped, [])
        input.stop()
    }

    func testUnboundEscapeCancelsTheTypedPrefix() {
        let input = makeTypingInput(names: [1: "Wrench", 2: "Web"])
        var typed: [String?] = []
        input.onTypedText = { typed.append($0?.text) }

        press(input, 13) // w
        waitUntil("prefix shown") { typed == ["w"] }
        press(input, HUDInput.escapeKeyCode)

        waitUntil("prefix cleared") { typed.last == .some(nil) }
        input.stop()
    }

    func testStopClearsTheTypedPrefix() {
        let input = makeTypingInput(names: [1: "Wrench", 2: "Web"])
        var typed: [String?] = []
        input.onTypedText = { typed.append($0?.text) }

        press(input, 13)
        waitUntil("prefix shown") { typed == ["w"] }
        input.stop()

        XCTAssertEqual(typed.last, .some(nil), "a hide must leave no prefix behind")
    }

    func testDigitEndsAnActiveLetterPrefix() {
        let input = makeTypingInput(names: [1: "Wrench", 2: "Web"])
        var typed: [String?] = []
        var numbers: [Int] = []
        input.onTypedText = { typed.append($0?.text) }
        input.onNumberEntry = { if let feedback = $0 { numbers.append(feedback.number) } }

        press(input, 13) // w: two names still match
        waitUntil("prefix shown") { typed == ["w"] }
        press(input, 18) // 1

        waitUntil("digit entry replaces the typed readout") { numbers.last == 1 }
        XCTAssertEqual(typed.last, .some(nil), "the letter prefix must not survive a digit")
        input.stop()
    }

    /// The reverse channel: a letter ends a number that is still waiting for a
    /// longer space number.
    func testLetterTypedWhileANumberIsPendingEndsTheNumber() {
        let input = makeTypingInput(names: [1: "Web", 10: "Wrench"])
        var typed: [String?] = []
        var numbers: [HUDNumberFeedback?] = []
        input.onTypedText = { typed.append($0?.text) }
        input.onNumberEntry = { numbers.append($0) }

        press(input, 18) // 1: could still become 10
        waitUntil("number shown") { numbers.last == HUDNumberFeedback(number: 1, exists: true) }
        press(input, 13) // w

        waitUntil("the letter replaces the number readout") { typed.last == "w" }
        XCTAssertEqual(numbers.last, .some(nil), "the pending number must not survive a letter")
        input.stop()
    }

    /// The two typed readouts share one overlay, so the second one must clear
    /// the first even while it is still inside its hold window.
    func testATypedReadoutReplacesTheOtherEvenDuringAHold() {
        let state = HUDNumberState()

        state.updateTypedText(HUDTypedFeedback(text: "w → Web", matches: true))
        state.update(HUDNumberFeedback(number: 1, exists: true))

        XCTAssertNil(state.typedText, "a digit ends a held letter readout")
        XCTAssertEqual(state.feedback?.number, 1)

        state.updateTypedText(HUDTypedFeedback(text: "w", matches: true))

        XCTAssertNil(state.feedback, "a letter ends a held digit readout")
        XCTAssertEqual(state.typedText, HUDTypedFeedback(text: "w", matches: true))
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

    func testNextAndPreviousSpaceStepAndWrap() {
        let input = HUDInput(panel: nil)
        var config = SpacemapConfig.default
        // `.all` pads the grid to maxSpaces with cells for spaces that do not
        // exist; stepping must stay on real spaces.
        config.showMode = .all
        config.maxSpaces = 8
        let spaces = [
            YabaiSpace(id: 1, index: 3, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 2, index: 5, display: 1, hasFocus: false, isVisible: nil, label: nil),
            YabaiSpace(id: 3, index: 8, display: 1, hasFocus: false, isVisible: nil, label: nil)
        ]
        input.currentState = GridState(config: config, spaces: spaces, windows: [], displayBounds: .zero, focusedIndex: 5)
        input.lastFocusedSpaceIndex = 5

        input.navigateToNextSpace()
        XCTAssertEqual(input.lastFocusedSpaceIndex, 8)

        input.navigateToNextSpace()
        XCTAssertEqual(input.lastFocusedSpaceIndex, 3, "next past the last space wraps to the first")

        input.navigateToPreviousSpace()
        XCTAssertEqual(input.lastFocusedSpaceIndex, 8, "previous before the first space wraps to the last")
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

        input.navigateToNextSpace()
        XCTAssertEqual(input.lastFocusedSpaceIndex, 7, "next stays within the focused display")

        input.navigateToNextSpace()
        XCTAssertEqual(input.lastFocusedSpaceIndex, 4, "next wraps within the focused display")
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
    /// A visible HUD whose key map is empty, so every letter reaches the
    /// typed-jump path instead of a binding.
    func makeTypingInput(
        names: [Int: String],
        windows: [YabaiWindow] = [],
        namingMode: SpaceNamingMode = .custom,
        jumpToSpaceEnabled: Bool = true,
        fuzzySpaceJumpEnabled: Bool = true
    ) -> HUDInput {
        let input = HUDInput(
            panel: nil,
            tapFactory: { _, _, _, _, _, _ in makeFakeEventTapPort() },
            relaunch: {}
        )
        input.accessibilityTrustProvider = { true }
        input.reconcileSettingsKeyMonitor()
        input.updateVisibility(true)
        input.updateConfig(
            hudKeys: HUDKeyBindings(),
            jumpToSpaceEnabled: jumpToSpaceEnabled,
            fuzzySpaceJumpEnabled: fuzzySpaceJumpEnabled
        )
        var config = SpacemapConfig.default
        config.spaceNames = names
        config.namingMode = namingMode
        let indices = Set(names.keys).union(windows.map(\.space)).sorted()
        let spaces = indices.map {
            YabaiSpace(id: $0, index: $0, display: 1, hasFocus: false, isVisible: nil, label: nil)
        }
        input.currentState = GridState(
            config: config,
            spaces: spaces,
            windows: windows,
            displayBounds: .zero,
            focusedIndex: spaces.first?.index
        )
        return input
    }

    func press(
        _ input: HUDInput,
        _ keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        autorepeat: Bool = false
    ) -> Unmanaged<CGEvent>? {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            XCTFail("could not build a key event")
            return nil
        }
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: autorepeat ? 1 : 0)
        return input.handleTapEvent(type: .keyDown, event: event)
    }

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
