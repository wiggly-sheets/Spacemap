import Foundation

/// Runs one child process with drained pipes and a hard time budget.
///
/// One kill policy for every spawn in the app: SIGTERM at `timeout`, SIGKILL
/// `killGrace` later, then a bounded wait for the pipe readers. A wedged child,
/// or a grandchild still holding stdout/stderr open, can never block the caller
/// past that.
enum ProcessRunner {
    /// Grace between SIGTERM and SIGKILL.
    static let killGrace: TimeInterval = 1
    /// Bounded wait for the stdout/stderr readers once the child is dead.
    static let drainTimeout: TimeInterval = 1

    enum Failure: LocalizedError, Equatable {
        case failed(status: Int32, message: String)
        case timedOut(timeout: TimeInterval)
        case drainTimedOut(timeout: TimeInterval)

        var errorDescription: String? {
            switch self {
            case .failed(let status, let message):
                let detail = message.isEmpty ? "no error output" : message
                return "command failed with status \(status): \(detail)"
            case .timedOut(let timeout):
                return "command timed out after \(timeout) seconds"
            case .drainTimedOut(let timeout):
                return "command output drain timed out after \(timeout) seconds; a child process is still holding stdout/stderr"
            }
        }
    }

    /// Blocks until the child exits, `timeout` expires, or the pipes are
    /// abandoned. Returns stdout on a zero exit; throws on timeout, drain
    /// timeout, or a non-zero exit (stderr in the message).
    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in termination.signal() }
        do {
            try process.run()
        } catch {
            // No readers were dispatched: let the pipes deallocate and close
            // their fds rather than closing them from this thread.
            throw error
        }
        outputPipe.fileHandleForWriting.closeFile()
        errorPipe.fileHandleForWriting.closeFile()

        // Drain both pipes on dedicated threads while the process runs so a large
        // output cannot fill the pipe and deadlock the child. Each reader owns its
        // read handle and closes it only after the blocking read returns, so the
        // waiting thread never closes an fd another thread is reading.
        let readers = DispatchGroup()
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        let outputLock = NSLock()
        let errorLock = NSLock()
        var outputData = Data()
        var errorData = Data()
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = outputHandle.readDataToEndOfFile()
            outputLock.lock()
            outputData = data
            outputLock.unlock()
            outputHandle.closeFile()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = errorHandle.readDataToEndOfFile()
            errorLock.lock()
            errorData = data
            errorLock.unlock()
            errorHandle.closeFile()
            readers.leave()
        }

        if termination.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if termination.wait(timeout: .now() + killGrace) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                // Best effort: a child that survives SIGKILL outlives this call.
                _ = termination.wait(timeout: .now() + killGrace)
            }
            // A grandchild can keep the pipe open after the child dies: never
            // wait unbounded or the caller's queue wedges forever. Do not
            // close here: the blocked reader owns the handle and will close it.
            // Giving up leaks that reader thread and its read fd until the pipe
            // reaches EOF, so a grandchild that never exits holds both for the
            // process lifetime. Caller-bounded by design; no production child
            // outlives its own yabai/mdfind/codesign call to trigger this.
            if readers.wait(timeout: .now() + drainTimeout) == .timedOut {
                NSLog("spacemap/process: abandoning blocked output readers after timeout")
            }
            throw Failure.timedOut(timeout: timeout)
        }
        // The child is dead, so pipes normally hit EOF; a leftover grandchild
        // holding the write end must still not block the caller forever.
        guard readers.wait(timeout: .now() + drainTimeout) == .success else {
            NSLog("spacemap/process: abandoning blocked output readers held open by a child process")
            throw Failure.drainTimedOut(timeout: drainTimeout)
        }
        guard process.terminationStatus == 0 else {
            errorLock.lock()
            let data = errorData
            errorLock.unlock()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw Failure.failed(status: process.terminationStatus, message: message)
        }
        outputLock.lock()
        let data = outputData
        outputLock.unlock()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
