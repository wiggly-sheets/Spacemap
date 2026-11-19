import CoreGraphics
import XCTest
@testable import spacemap

final class HUDSpaceCommandsTests: XCTestCase {
    private func space(_ index: Int) -> YabaiSpace {
        YabaiSpace(id: index, index: index, display: 1, hasFocus: false, isVisible: nil, label: nil)
    }

    func testCreateReportsTheNewestSpaceOnceItAppears() {
        let yabai = MockYabaiService()
        yabai.querySpacesResult = [space(1)]
        let commands = HUDSpaceCommands(yabaiService: yabai)
        var created: Int?

        commands.createSpace { created = $0 }

        XCTAssertEqual(yabai.createSpaceCallCount, 1)
        XCTAssertNil(created, "a space is only reported once yabai lists it")

        yabai.querySpacesResult = [space(1), space(2)]

        waitUntil("new space appears") { created == 2 }
        XCTAssertEqual(yabai.focusSpaceAsyncCallCount, 0, "plain create never steals focus")
    }

    func testCreateAndFocusFocusesTheNewestSpace() {
        let yabai = MockYabaiService()
        yabai.querySpacesResult = [space(1)]
        let commands = HUDSpaceCommands(yabaiService: yabai)
        var created: Int?

        commands.createAndFocusNewestSpace { created = $0 }
        yabai.querySpacesResult = [space(1), space(2)]

        waitUntil("new space appears") { created == 2 }
        XCTAssertEqual(yabai.focusSpaceAsyncCallCount, 1)
    }

    func testDestroyWaitsForTheSpaceToDisappearThenRestoresFocus() {
        let yabai = MockYabaiService()
        yabai.querySpacesResult = [space(1), space(2), space(3)]
        let commands = HUDSpaceCommands(yabaiService: yabai)
        var settled = false

        commands.destroySpace(3, previous: 2) { settled = true }

        XCTAssertEqual(yabai.destroySpaceCallCount, 1)
        XCTAssertEqual(yabai.lastDestroySpaceIndex, 3)
        XCTAssertFalse(settled, "the destroy is not settled while yabai still lists the space")
        XCTAssertEqual(yabai.focusSpaceAsyncCallCount, 0)

        yabai.querySpacesResult = [space(1), space(2)]

        waitUntil("destroy settles") { settled }
        XCTAssertEqual(yabai.focusSpaceAsyncCallCount, 1,
            "the space before the destroyed one takes focus")
    }

    func testCreatePollStopsFocusingOnceThePresentationEnds() {
        let yabai = MockYabaiService()
        yabai.querySpacesResult = [space(1)]
        var continuePolling = true
        let commands = HUDSpaceCommands(yabaiService: yabai) { { continuePolling } }
        var created: Int?

        commands.createAndFocusNewestSpace { created = $0 }
        yabai.querySpacesResult = [space(1), space(2)]
        continuePolling = false

        runLoop(for: 0.3)

        XCTAssertNil(created, "a closed presentation must not receive the result")
        XCTAssertEqual(yabai.focusSpaceAsyncCallCount, 0,
            "a settle poll from a closed presentation must not steal focus")
    }

    func testDestroyPollStopsRestoringFocusOnceThePresentationEnds() {
        let yabai = MockYabaiService()
        yabai.querySpacesResult = [space(1), space(2), space(3)]
        var continuePolling = true
        let commands = HUDSpaceCommands(yabaiService: yabai) { { continuePolling } }
        var settled = false

        commands.destroySpace(3, previous: 2) { settled = true }
        yabai.querySpacesResult = [space(1), space(2)]
        continuePolling = false

        runLoop(for: 0.3)

        XCTAssertFalse(settled, "a closed presentation must not be told the destroy settled")
        XCTAssertEqual(yabai.focusSpaceAsyncCallCount, 0,
            "a closed presentation must not have its focus restored by the poll")
    }

    func testSetLayoutAppliesTheRequestedLayout() {
        let yabai = MockYabaiService()
        let commands = HUDSpaceCommands(yabaiService: yabai)

        commands.setLayout(.float)

        XCTAssertEqual(yabai.setSpaceLayoutCallCount, 1)
        XCTAssertEqual(yabai.lastSpaceLayout, .float)
    }

    func testCycleLayoutAdvancesThroughTheCycle() {
        let commands = HUDSpaceCommands(yabaiService: MockYabaiService())

        XCTAssertEqual(commands.cycleLayout(from: "bsp"), .stack)
        XCTAssertEqual(commands.cycleLayout(from: "stack"), .float)
        XCTAssertEqual(commands.cycleLayout(from: "float"), .bsp)
        XCTAssertEqual(commands.cycleLayout(from: "unknown"), .stack)
    }

    func testMoveSpaceSwapsWithTheNeighbourAndStopsAtTheEnd() {
        let yabai = MockYabaiService()
        let commands = HUDSpaceCommands(yabaiService: yabai)

        XCTAssertEqual(
            commands.moveSpace(focusedIndex: 2, indices: [1, 2, 3], direction: .right, mode: .content),
            2
        )
        XCTAssertEqual(yabai.lastSwapSourceIndex, 2)
        XCTAssertEqual(yabai.lastSwapTargetIndex, 3)

        XCTAssertEqual(
            commands.moveSpace(focusedIndex: 2, indices: [1, 2, 3], direction: .left, mode: .content),
            2
        )
        XCTAssertEqual(yabai.lastSwapTargetIndex, 1)

        XCTAssertNil(commands.moveSpace(focusedIndex: 3, indices: [1, 2, 3], direction: .right, mode: .content))
        XCTAssertNil(commands.moveSpace(focusedIndex: nil, indices: [1, 2, 3], direction: .left, mode: .content))
        XCTAssertEqual(yabai.swapSpacesCallCount, 2)
    }

    private func runLoop(for duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func waitUntil(
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
