import Foundation
import AppKit

extension YabaiClientImpl {
    func runOnYabaiQueue(_ block: @escaping () -> Void) {
        yabaiQueue.async(execute: block)
    }

    func runOnYabaiQueue(_ workItem: DispatchWorkItem) {
        yabaiQueue.async(execute: workItem)
    }


    func defaultYabaiProcessCheck() -> Bool {
        let output = (try? shell("/usr/bin/pgrep", "yabai")) ?? ""
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func isYabaiRunning(forceRefresh: Bool = false) -> Bool {
        cacheLock.lock()
        let now = currentUptime
        if !forceRefresh,
           let cached = _yabaiRunningCache,
           now - cached.checkedAt < yabaiCacheTTL {
            let result = cached.result
            cacheLock.unlock()
            return result
        }
        cacheLock.unlock()
        let check = yabaiProcessCheck
        // pgrep outside lock: never hold cacheLock across process spawn.
        let result = check()
        cacheLock.lock()
        _yabaiRunningCache = (result, currentUptime)
        cacheLock.unlock()
        return result
    }

    func resetYabaiRunningCache() {
        cacheLock.lock()
        _yabaiRunningCache = nil
        cacheLock.unlock()
    }

    func resetYabaiProcessCheck() {
        yabaiProcessCheck = { [weak self] in guard let self else { return false }; return self.defaultYabaiProcessCheck() }
        resetYabaiRunningCache()
    }


    /// Fire-and-forget yabai command. The result is discarded, but a failure is
    /// logged rather than swallowed: these are driven by menu-bar clicks, so a
    /// silent no-op is indistinguishable from a broken action otherwise.
    func runIgnoringFailure(_ arguments: [String], _ label: String) {
        defer { invalidateSnapshotCaches() }
        do {
            _ = try shell([yabaiPath] + arguments)
        } catch {
            NSLog("spacemap/yabai: \(label) failed — \(error.localizedDescription)")
        }
    }

    func shell(_ args: String...) throws -> String {
        try shell(args)
    }

    /// Array form. `shell(path, args...)` cannot be spelled — a trailing `...`
    /// after an identifier parses as a postfix range, not a variadic spread — so
    /// callers that build their argument list dynamically use this instead.
    func shell(_ args: [String], timeout: TimeInterval? = nil) throws -> String {
        guard let executable = args.first else { throw YabaiError.commandFailed(arguments: [], status: -1, message: "empty command") }
        if executable == yabaiPath, Self.refuseUntrustedBinaries, let issue = Self.cachedTrustIssue(path: yabaiPath) {
            throw YabaiError.commandFailed(arguments: Array(args.dropFirst()), status: -1, message: "refusing untrusted yabai binary: \(issue)")
        }
        let effectiveTimeout = timeout ?? Self.commandTimeout
        do {
            if let runner = commandRunnerOverride {
                return try runner(executable, Array(args.dropFirst()), effectiveTimeout)
            }
            return try ProcessRunner.run(
                executable: executable,
                arguments: Array(args.dropFirst()),
                timeout: effectiveTimeout
            )
        } catch ProcessRunner.Failure.failed(let status, let message) {
            throw YabaiError.commandFailed(arguments: Array(args.dropFirst()), status: status, message: message)
        } catch ProcessRunner.Failure.timedOut(let timedOut) {
            throw YabaiError.commandTimedOut(arguments: Array(args.dropFirst()), timeout: timedOut)
        } catch ProcessRunner.Failure.drainTimedOut(let timedOut) {
            throw YabaiError.outputDrainTimedOut(arguments: Array(args.dropFirst()), timeout: timedOut)
        } catch {
            // A spawn-time error (EACCES, quarantine, binary gone) must reach the
            // user as a yabai failure, not raw Cocoa/POSIX text.
            throw YabaiError.commandFailed(arguments: Array(args.dropFirst()), status: -1, message: error.localizedDescription)
        }
    }
}
