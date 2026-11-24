import XCTest
@testable import spacemap

final class YabaiClientSignalTests: YabaiClientImplTestCase {
    func testRegisterSignalsRegistersSignals() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }
        client.registerSignals(socketPath: "/tmp/spacemap_test.socket")
    }

    func testRefreshSignalActionPreservesNonceWhenPresent() throws {
        let socketPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("smn_\(UUID().uuidString.prefix(8)).sock")
        let noncePath = SpacemapCommand.noncePath(for: socketPath)
        try Data(repeating: 0xab, count: 32).write(to: URL(fileURLWithPath: noncePath), options: .atomic)
        defer { try? FileManager.default.removeItem(atPath: noncePath) }

        let hex = String(repeating: "ab", count: 32)
        XCTAssertEqual(SpacemapCommand.currentNonceHex(for: socketPath), hex)

        let action = client.refreshSignalAction(socketPath: socketPath)

        XCTAssertTrue(action.contains(":\(hex)'"), "nonce must be preserved in the action: \(action)")
        XCTAssertFalse(action.contains("/usr/bin/false"))
    }

    func testRegisterSignalsFailsClosedWhenNonceIsMissing() {
        let socketPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("smnn_\(UUID().uuidString.prefix(8)).sock")
        let noncePath = SpacemapCommand.noncePath(for: socketPath)
        try? FileManager.default.removeItem(atPath: noncePath)
        XCTAssertNotNil(SpacemapCommand.shellQuoted(socketPath),
                        "fixture path must be valid so only the missing nonce is under test")
        XCTAssertNil(SpacemapCommand.currentNonceHex(for: socketPath))

        // Direct callers still get a fail-closed action from the builders.
        XCTAssertEqual(client.refreshSignalAction(socketPath: socketPath), "/usr/bin/false")
        XCTAssertEqual(
            client.spaceChangedSignalAction(socketPath: socketPath, showHUDOnSpaceChange: false),
            "/usr/bin/false"
        )

        client.yabaiProcessCheck = { true }
        client.yabaiExecutableOverride = true
        let commandLock = NSLock()
        var commands: [[String]] = []
        client.commandRunnerOverride = { _, arguments, _ in
            commandLock.lock()
            commands.append(arguments)
            commandLock.unlock()
            return ""
        }

        client.registerSignals(
            socketPath: socketPath,
            showHUDOnSpaceChange: false,
            refreshWorkspacePreviews: true,
            refreshWindowGeometry: true
        )

        commandLock.lock()
        let issued = commands
        commandLock.unlock()
        XCTAssertTrue(issued.isEmpty,
                      "nonce-less registration must not remove or add signals: \(issued)")
    }

    func testRegisterSignalsRegistersNonceActionsWhenPresent() throws {
        let socketPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("smn_\(UUID().uuidString.prefix(8)).sock")
        let noncePath = SpacemapCommand.noncePath(for: socketPath)
        try Data(repeating: 0xcd, count: 32).write(to: URL(fileURLWithPath: noncePath), options: .atomic)
        defer { try? FileManager.default.removeItem(atPath: noncePath) }

        let hex = String(repeating: "cd", count: 32)
        XCTAssertEqual(SpacemapCommand.currentNonceHex(for: socketPath), hex)

        client.yabaiProcessCheck = { true }
        client.yabaiExecutableOverride = true
        let listing = signalListing(label: "spacemap_space_changed", nonce: hex)
        let actionLock = NSLock()
        var actions: [String] = []
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--list") {
                return listing
            }
            if arguments.contains("--add"),
               let action = arguments.first(where: { $0.hasPrefix("action=") }) {
                actionLock.lock()
                actions.append(action)
                actionLock.unlock()
            }
            return ""
        }

        client.registerSignals(
            socketPath: socketPath,
            showHUDOnSpaceChange: false,
            refreshWorkspacePreviews: true,
            refreshWindowGeometry: true
        )

        actionLock.lock()
        let registered = actions
        actionLock.unlock()
        XCTAssertFalse(registered.isEmpty)
        for action in registered {
            XCTAssertTrue(action.contains(":\(hex)'"),
                          "registered action must carry the nonce: \(action)")
            XCTAssertFalse(action.contains("/usr/bin/false"))
        }
    }

    /// Socket path with a written nonce file: registration refuses to run
    /// without one, and the file is removed at teardown.
    func testRegisterSignalsRetriesUntilTheDaemonAcceptsTheSignal() throws {
        let socketPath = try makeNonceSocket()
        client.yabaiProcessCheck = { true }
        client.yabaiExecutableOverride = true
        // Run the backoff inline, but record it: the delays are the only thing
        // keeping the attempts apart in production.
        var delays: [TimeInterval] = []
        client.signalRetryScheduler = { delay, pass in
            delays.append(delay)
            pass()
        }

        let listing = signalListing(label: "spacemap_space_changed", nonce: fixtureNonceHex)
        // A just-restarted daemon accepts the add but keeps no signal until the
        // last bounded attempt; all five backoff delays must be observed.
        var listCalls = 0
        var addCalls = 0
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--list") {
                listCalls += 1
                return listCalls <= 5 ? "" : listing
            }
            if arguments.contains("--add") { addCalls += 1 }
            return ""
        }

        client.registerSignals(socketPath: socketPath)

        XCTAssertEqual(listCalls, 6, "verification must retry until the table holds the signal")
        XCTAssertEqual(addCalls, 6, "each failed pass re-adds the signal once")
        XCTAssertEqual(delays, [1, 2, 4, 8, 16], "backoff must grow between passes")
    }

    func testRegisterSignalsGivesUpAfterTheBoundedRetries() throws {
        let socketPath = try makeNonceSocket()
        client.yabaiProcessCheck = { true }
        client.yabaiExecutableOverride = true
        client.signalRetryScheduler = { _, pass in pass() }

        var listCalls = 0
        var addCalls = 0
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--list") { listCalls += 1 }
            if arguments.contains("--add") { addCalls += 1 }
            return ""
        }

        client.registerSignals(socketPath: socketPath)

        // One immediate pass plus one per retry delay.
        let attempts = YabaiClientImpl.signalRegistrationRetryDelays.count + 1
        XCTAssertEqual(listCalls, attempts, "retries must stop at the bounded attempt count")
        XCTAssertEqual(addCalls, attempts)
    }

    func testRegisterSignalsSchedulesNoRetryAfterASuccessfulFirstPass() throws {
        let socketPath = try makeNonceSocket()
        client.yabaiProcessCheck = { true }
        client.yabaiExecutableOverride = true
        var scheduled = 0
        client.signalRetryScheduler = { _, pass in
            scheduled += 1
            pass()
        }

        let listing = signalListing(label: "spacemap_space_changed", nonce: fixtureNonceHex)
        var listCalls = 0
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--list") {
                listCalls += 1
                return listing
            }
            return ""
        }

        client.registerSignals(socketPath: socketPath)

        XCTAssertEqual(listCalls, 1)
        XCTAssertEqual(scheduled, 0, "a successful first pass must not schedule a retry")
    }

    func testRegisterSignalsRetriesWhenTheListingThrows() throws {
        let socketPath = try makeNonceSocket()
        client.yabaiProcessCheck = { true }
        client.yabaiExecutableOverride = true
        var delays: [TimeInterval] = []
        client.signalRetryScheduler = { delay, pass in
            delays.append(delay)
            pass()
        }

        let listing = signalListing(label: "spacemap_space_changed", nonce: fixtureNonceHex)
        // A daemon that is not ready yet refuses the list query outright.
        var listCalls = 0
        var addCalls = 0
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--list") {
                listCalls += 1
                guard listCalls > 1 else {
                    throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "not ready"])
                }
                return listing
            }
            if arguments.contains("--add") { addCalls += 1 }
            return ""
        }

        client.registerSignals(socketPath: socketPath)

        XCTAssertEqual(listCalls, 2, "a throwing listing must retry instead of giving up")
        XCTAssertEqual(addCalls, 2)
        XCTAssertEqual(delays, [1], "the retry used the first backoff delay")
    }

    func testRegisterSignalsRejectsASignalCarryingAStaleNonce() throws {
        let socketPath = try makeNonceSocket()
        client.yabaiProcessCheck = { true }
        client.yabaiExecutableOverride = true
        var delays: [TimeInterval] = []
        client.signalRetryScheduler = { delay, pass in
            delays.append(delay)
            pass()
        }

        let stale = signalListing(label: "spacemap_space_changed",
                                  nonce: String(repeating: "ab", count: 32))
        let live = signalListing(label: "spacemap_space_changed", nonce: fixtureNonceHex)
        // A stale signal from before a nonce rotation survives the remove (or
        // the remove failed), so the first listing still shows the label.
        var listCalls = 0
        client.commandRunnerOverride = { _, arguments, _ in
            if arguments.contains("--list") {
                listCalls += 1
                return listCalls == 1 ? stale : live
            }
            return ""
        }

        client.registerSignals(socketPath: socketPath)

        XCTAssertEqual(listCalls, 2, "an old nonce in the action must not count as registered")
        XCTAssertEqual(delays, [1], "the retry stops once the live signal is listed")
    }

    func testNewRegistrationSupersedesAPendingRetryChain() throws {
        let socketPath = try makeNonceSocket()
        client.yabaiProcessCheck = { true }
        client.yabaiExecutableOverride = true
        var pending: [() -> Void] = []
        client.signalRetryScheduler = { _, pass in pending.append(pass) }

        // Count every runner call, not only listings: a stale pass that
        // removed signals then stopped before listing must also fail this test.
        var runnerCalls = 0
        client.commandRunnerOverride = { _, _, _ in
            runnerCalls += 1
            return ""
        }

        client.registerSignals(socketPath: socketPath)
        XCTAssertEqual(pending.count, 1, "a failed pass leaves one retry pending")
        client.registerSignals(socketPath: socketPath)
        XCTAssertEqual(pending.count, 2)

        let callsBeforeStaleRun = runnerCalls
        pending[0]()
        XCTAssertEqual(runnerCalls, callsBeforeStaleRun,
                       "a superseded retry chain must stop instead of running yabai")
        pending[1]()
        XCTAssertGreaterThan(runnerCalls, callsBeforeStaleRun,
                             "the newest chain still retries")
    }

    func testRemoveSignalsRemovesSignals() throws {
        guard isYabaiAvailable else {
            throw XCTSkip("yabai not available")
        }
        client.yabaiProcessCheck = { true }
        client.removeSignals()
    }


}
