import XCTest
import CoreGraphics
@testable import spacemap

final class HUDInputNameJumpTests: HUDInputTestCase {
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

}
