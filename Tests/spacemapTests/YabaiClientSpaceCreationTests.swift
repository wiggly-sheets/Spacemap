import XCTest
@testable import spacemap

final class YabaiClientSpaceCreationTests: YabaiClientImplTestCase {
    func testMoveWindowCreatingSpacesBailsWhenBudgetExpires() {
        client = YabaiClientImpl(spaceCreationBudget: 0)
        client.yabaiExecutableOverride = true
        let commandLock = NSLock()
        var commands: [String] = []
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") { return "[]" }
            commandLock.lock()
            commands.append(arguments.joined(separator: " "))
            commandLock.unlock()
            return ""
        }

        let done = expectation(description: "create loop times out")
        client.moveWindowCreatingSpacesIfNeeded(42, toSpace: 2, focusDestination: false) { result in
            switch result {
            case .failure(let error):
                XCTAssertTrue(error.localizedDescription.contains("within 0"),
                              "unexpected error: \(error.localizedDescription)")
            case .success:
                XCTFail("create loop should fail when the budget is exhausted")
            }
            done.fulfill()
        }

        waitForExpectations(timeout: 2)
        commandLock.lock()
        let issued = commands
        commandLock.unlock()
        XCTAssertTrue(issued.isEmpty, "no create/move command should run after the deadline: \(issued)")
    }

    func testMoveWindowCreatingSpacesCreatesThenMovesUsingFakeRunner() {
        client = YabaiClientImpl(spaceCreationBudget: 5)
        client.yabaiExecutableOverride = true
        let commandLock = NSLock()
        var commands: [String] = []
        var spaceQueries = 0
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") {
                spaceQueries += 1
                return spaceQueries == 1
                    ? self.spacesJSON([1], focused: 1)
                    : self.spacesJSON([1, 2], focused: 1)
            }
            commandLock.lock()
            commands.append(arguments.joined(separator: " "))
            commandLock.unlock()
            return ""
        }

        let done = expectation(description: "create loop succeeds")
        client.moveWindowCreatingSpacesIfNeeded(42, toSpace: 2, focusDestination: true) { result in
            if case .failure(let error) = result {
                XCTFail("unexpected failure: \(error.localizedDescription)")
            }
            done.fulfill()
        }

        waitForExpectations(timeout: 2)
        commandLock.lock()
        let issued = commands
        commandLock.unlock()
        XCTAssertTrue(issued.contains { $0.contains("space --create") }, "issued: \(issued)")
        XCTAssertTrue(issued.contains { $0.contains("window 42 --space 2") }, "issued: \(issued)")
        XCTAssertTrue(issued.contains { $0.contains("space --focus 2") }, "issued: \(issued)")
    }

    func testMoveWindowCreatingSpacesExpiresBudgetMidLoop() {
        client = YabaiClientImpl(spaceCreationBudget: 5)
        var now: TimeInterval = 7_000
        client.uptimeOverride = { now }
        client.yabaiExecutableOverride = true
        let commandLock = NSLock()
        var commands: [String] = []
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--spaces") { return self.spacesJSON([1]) }
            commandLock.lock()
            commands.append(arguments.joined(separator: " "))
            commandLock.unlock()
            if arguments.contains("--create") {
                now += 10
            }
            return ""
        }

        let done = expectation(description: "create loop times out mid-loop")
        client.moveWindowCreatingSpacesIfNeeded(42, toSpace: 2, focusDestination: false) { result in
            switch result {
            case .failure(let error):
                XCTAssertTrue(error.localizedDescription.contains("within 5"),
                              "unexpected error: \(error.localizedDescription)")
            case .success:
                XCTFail("create loop should fail after the budget elapses")
            }
            done.fulfill()
        }

        waitForExpectations(timeout: 2)
        commandLock.lock()
        let issued = commands
        commandLock.unlock()
        XCTAssertTrue(issued.contains { $0.contains("space --create") },
                      "at least one create should have run before the deadline: \(issued)")
        XCTAssertFalse(issued.contains { $0.contains("window 42 --space 2") },
                       "move must not run after the budget expires: \(issued)")
    }


    // MARK: - Fixtures

}
