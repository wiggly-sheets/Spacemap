import XCTest
@testable import spacemap

final class ProcessRunnerTests: XCTestCase {

    func testDrainsLargeOutputBeforeWaitingForExit() throws {
        let output = try ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "/usr/bin/yes x | /usr/bin/head -c 1048576"],
            timeout: 5
        )

        XCTAssertEqual(output.utf8.count, 1_048_576)
    }

    func testTerminatesCommandsThatExceedTimeout() {
        let started = Date()

        XCTAssertThrowsError(try ProcessRunner.run(
            executable: "/bin/sleep",
            arguments: ["5"],
            timeout: 0.05
        )) { error in
            XCTAssertEqual(error as? ProcessRunner.Failure, .timedOut(timeout: 0.05))
            XCTAssertTrue(error.localizedDescription.contains("timed out"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    /// The wedged-child bug class: a child that ignores SIGTERM must still be
    /// gone by the time `run` returns, and it must not outlive its budget.
    func testEscalatesToSIGKILLWhenTheChildIgnoresSIGTERM() throws {
        let pidFile = NSTemporaryDirectory() + "spacemap-process-runner-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: pidFile) }
        let started = Date()

        XCTAssertThrowsError(try ProcessRunner.run(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "trap '' TERM; echo $$ > '\(pidFile)'; while :; do sleep 0.05; done",
            ],
            timeout: 1.0
        )) { error in
            XCTAssertEqual(error as? ProcessRunner.Failure, .timedOut(timeout: 1.0))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3,
                          "timeout plus kill grace must bound the call")

        let pidText = try String(contentsOfFile: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try XCTUnwrap(Int32(pidText))
        let status = kill(pid, 0)
        let killErrno = errno
        XCTAssertEqual(status, -1, "SIGKILL must leave no child behind")
        XCTAssertEqual(killErrno, ESRCH)
    }

    func testCapturesOutputProducedAfterDelay() throws {
        let output = try ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 0.3; printf 'late output'"],
            timeout: 5
        )

        XCTAssertEqual(output, "late output")
    }

    func testCapturesStderrAndStatusInFailure() {
        XCTAssertThrowsError(try ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf 'boom' >&2; exit 3"],
            timeout: 5
        )) { error in
            XCTAssertEqual(error as? ProcessRunner.Failure, .failed(status: 3, message: "boom"))
            XCTAssertTrue(error.localizedDescription.contains("boom"))
        }
    }

    func testAbandonsGrandchildHoldingPipeWithoutHangingOrCrashing() {
        let started = Date()

        XCTAssertThrowsError(try ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 5 & printf 'started'"],
            timeout: 5
        )) { error in
            if case .drainTimedOut? = error as? ProcessRunner.Failure {
                // expected
            } else {
                XCTFail("unexpected error: \(error.localizedDescription)")
            }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3,
                          "a grandchild holding the pipe must not block the caller")
    }
}
