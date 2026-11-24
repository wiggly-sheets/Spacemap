import XCTest
import CoreGraphics
@testable import spacemap

final class HUDInputNumberJumpTests: HUDInputTestCase {
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

}
