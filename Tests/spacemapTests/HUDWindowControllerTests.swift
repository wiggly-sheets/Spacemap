import XCTest
@testable import spacemap

final class HUDWindowControllerTests: XCTestCase {

    var hudController: HUDWindowController!
    var mockState: GridState!

    override func setUpWithError() throws {
        hudController = HUDWindowController()

        // Create a mock GridState for testing. Spaces 1, 2, 3, 10, 15 exist.
        // YabaiSpace is Decodable-only, so decode from JSON fixtures.
        let config = GridConfig.default
        let json = """
        [
            {"id": 1, "index": 1, "display": 1, "has-focus": true,  "is-visible": true,  "label": null, "type": "user"},
            {"id": 2, "index": 2, "display": 1, "has-focus": false, "is-visible": true,  "label": null, "type": "user"},
            {"id": 3, "index": 3, "display": 1, "has-focus": false, "is-visible": true,  "label": null, "type": "user"},
            {"id": 10, "index": 10, "display": 1, "has-focus": false, "is-visible": true, "label": null, "type": "user"},
            {"id": 15, "index": 15, "display": 1, "has-focus": false, "is-visible": true, "label": null, "type": "user"}
        ]
        """
        let spaces = try JSONDecoder().decode([YabaiSpace].self, from: Data(json.utf8))
        mockState = GridState(
            config: config,
            spaces: spaces,
            windows: [],
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: 1
        )

        // Ensure the hook is clean between tests
        YabaiClient.focusSpaceAsyncHook = nil
    }

    override func tearDownWithError() throws {
        hudController = nil
        mockState = nil
        YabaiClient.focusSpaceAsyncHook = nil
    }

    // MARK: - numberFromKeyCode tests
    //
    // Like vim/arrow keys, number keys work without modifiers so they can be
    // used for jump-to-space while the HUD is visible (which blocks text input below).

    func testNumberFromKeyCode_mainKeyboard_withoutModifier() {
        // Like vim/arrow keys, number keys work without modifiers
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 18, flags: []), 1)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 19, flags: []), 2)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 20, flags: []), 3)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 21, flags: []), 4)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 22, flags: []), 5)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 23, flags: []), 6)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 24, flags: []), 7)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 25, flags: []), 8)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 26, flags: []), 9)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 27, flags: []), 0)
    }

    func testNumberFromKeyCode_numpad_withoutModifier() {
        // Numpad numbers work without modifiers like main keyboard
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 82, flags: []), 0)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 83, flags: []), 1)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 84, flags: []), 2)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 85, flags: []), 3)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 86, flags: []), 4)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 87, flags: []), 5)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 88, flags: []), 6)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 89, flags: []), 7)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 91, flags: []), 8)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 92, flags: []), 9)
    }

    func testNumberFromKeyCode_controlModifier_returnsNil() {
        // Control modifier is reserved for navigation, so number keys return nil
        XCTAssertNil(HUDWindowController.numberFromKeyCode(keyCode: 18, flags: .maskControl))
        XCTAssertNil(HUDWindowController.numberFromKeyCode(keyCode: 23, flags: .maskControl))
        XCTAssertNil(HUDWindowController.numberFromKeyCode(keyCode: 27, flags: .maskControl))
    }

    func testNumberWithShiftModifier_returnsValue() {
        // Shift modifier doesn't interfere with number entry (unlike Cmd/Ctrl/Opt)
        XCTAssertEqual(HUDWindowController.numberFromKeyCode(keyCode: 18, flags: .maskShift), 1)
    }

    func testNumberFromKeyCode_invalidKeyCode_returnsNil() {
        XCTAssertNil(HUDWindowController.numberFromKeyCode(keyCode: 0, flags: .maskCommand))
        XCTAssertNil(HUDWindowController.numberFromKeyCode(keyCode: 99, flags: .maskCommand))
        XCTAssertNil(HUDWindowController.numberFromKeyCode(keyCode: 30, flags: .maskCommand)) // A non-digit key
    }

    // MARK: - handleNumberEntry builds the accumulated string

    func testHandleNumberEntry_buildsNumber() {
        hudController.handleNumberEntry(1)
        XCTAssertEqual(hudController.pendingNumber, "1")

        hudController.handleNumberEntry(2)
        XCTAssertEqual(hudController.pendingNumber, "12")

        hudController.handleNumberEntry(0)
        XCTAssertEqual(hudController.pendingNumber, "120")
    }

    // MARK: - processPendingNumber validates the target space

    func testProcessPendingNumber_jumpsToValidSpace() {
        hudController.pendingNumber = "15"
        hudController.currentState = mockState

        let focusExpectation = expectation(description: "focusSpaceAsyncHook called with 15")
        YabaiClient.focusSpaceAsyncHook = { index in
            XCTAssertEqual(index, 15)
            focusExpectation.fulfill()
        }

        hudController.processPendingNumber()

        // Pending number is cleared after processing
        XCTAssertEqual(hudController.pendingNumber, "")
        // Pending focus state is set optimistically
        XCTAssertEqual(hudController.pendingFocusedSpaceIndex, 15)
        XCTAssertNotNil(hudController.pendingFocusDeadline)
        // lastFocusedSpaceIndex reflects the jump immediately
        XCTAssertEqual(hudController.lastFocusedSpaceIndex, 15)

        waitForExpectations(timeout: 1.0)
    }

    func testProcessPendingNumber_invalidNumberDoesNotJump() {
        // Space 99 does not exist in mockState
        hudController.pendingNumber = "99"
        hudController.currentState = mockState
        let previousFocused = hudController.lastFocusedSpaceIndex

        let focusExpectation = expectation(description: "focusSpaceAsyncHook should not be called")
        focusExpectation.isInverted = true
        YabaiClient.focusSpaceAsyncHook = { _ in
            focusExpectation.fulfill()
        }

        hudController.processPendingNumber()

        // Pending number is cleared even for invalid input
        XCTAssertEqual(hudController.pendingNumber, "")
        // No pending focus state set
        XCTAssertNil(hudController.pendingFocusedSpaceIndex)
        XCTAssertNil(hudController.pendingFocusDeadline)
        // lastFocusedSpaceIndex unchanged
        XCTAssertEqual(hudController.lastFocusedSpaceIndex, previousFocused)

        waitForExpectations(timeout: 1.0)
    }

    func testProcessPendingNumber_emptyStringDoesNotJump() {
        hudController.pendingNumber = ""
        hudController.currentState = mockState
        let previousFocused = hudController.lastFocusedSpaceIndex

        let focusExpectation = expectation(description: "focusSpaceAsyncHook should not be called")
        focusExpectation.isInverted = true
        YabaiClient.focusSpaceAsyncHook = { _ in
            focusExpectation.fulfill()
        }

        hudController.processPendingNumber()

        XCTAssertEqual(hudController.pendingNumber, "")
        XCTAssertNil(hudController.pendingFocusedSpaceIndex)
        XCTAssertEqual(hudController.lastFocusedSpaceIndex, previousFocused)

        waitForExpectations(timeout: 1.0)
    }

    func testProcessPendingNumber_noCurrentStateDoesNotJump() {
        hudController.pendingNumber = "5"
        hudController.currentState = nil

        let focusExpectation = expectation(description: "focusSpaceAsyncHook should not be called")
        focusExpectation.isInverted = true
        YabaiClient.focusSpaceAsyncHook = { _ in
            focusExpectation.fulfill()
        }

        hudController.processPendingNumber()

        // Pending number is cleared even without state
        XCTAssertEqual(hudController.pendingNumber, "")
        XCTAssertNil(hudController.pendingFocusedSpaceIndex)

        waitForExpectations(timeout: 1.0)
    }

    func testProcessPendingNumber_acceptsSingleDigit() {
        hudController.pendingNumber = "3"
        hudController.currentState = mockState

        let focusExpectation = expectation(description: "focusSpaceAsyncHook called with 3")
        YabaiClient.focusSpaceAsyncHook = { index in
            XCTAssertEqual(index, 3)
            focusExpectation.fulfill()
        }

        hudController.processPendingNumber()

        XCTAssertEqual(hudController.pendingNumber, "")
        XCTAssertEqual(hudController.pendingFocusedSpaceIndex, 3)
        XCTAssertEqual(hudController.lastFocusedSpaceIndex, 3)

        waitForExpectations(timeout: 1.0)
    }

    func testProcessPendingNumber_multiDigitJumpsToCorrectSpace() {
        // Two-digit number targeting an existing space (10)
        hudController.pendingNumber = "10"
        hudController.currentState = mockState

        let focusExpectation = expectation(description: "focusSpaceAsyncHook called with 10")
        YabaiClient.focusSpaceAsyncHook = { index in
            XCTAssertEqual(index, 10)
            focusExpectation.fulfill()
        }

        hudController.processPendingNumber()

        XCTAssertEqual(hudController.pendingNumber, "")
        XCTAssertEqual(hudController.pendingFocusedSpaceIndex, 10)

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - jumpToSpace

    func testJumpToSpace_setsPendingFocusAndIssuesCommand() {
        hudController.currentState = mockState

        let focusExpectation = expectation(description: "focusSpaceAsyncHook called with 10")
        YabaiClient.focusSpaceAsyncHook = { index in
            XCTAssertEqual(index, 10)
            focusExpectation.fulfill()
        }

        hudController.jumpToSpace(index: 10, in: mockState)

        XCTAssertEqual(hudController.pendingFocusedSpaceIndex, 10)
        XCTAssertNotNil(hudController.pendingFocusDeadline)
        XCTAssertEqual(hudController.lastFocusedSpaceIndex, 10)

        waitForExpectations(timeout: 1.0)
    }

    func testJumpToSpace_updatesCurrentStateRendered() {
        // After a jump, renderPendingFocus mutates the HUD so the newly
        // focused space is highlighted optimistically; here we only check
        // that the focus bookkeeping fields are consistent.
        hudController.currentState = mockState

        YabaiClient.focusSpaceAsyncHook = { _ in }

        hudController.jumpToSpace(index: 2, in: mockState)

        XCTAssertEqual(hudController.pendingFocusedSpaceIndex, 2)
        XCTAssertNotNil(hudController.pendingFocusDeadline)
        XCTAssertEqual(hudController.lastFocusedSpaceIndex, 2)
    }
}
