import Foundation
import AppKit

extension YabaiClientImpl {
    /// Refuse to execute the yabai binary when the trust check fails.
    /// Set from SpacemapConfig.refuseUntrustedYabai at launch; default false
    /// (warn-only) so legit installs never brick.
    static let refuseLock = NSLock()
    static var _refuseUntrustedBinaries = false
    static var refuseUntrustedBinaries: Bool {
        get {
            refuseLock.lock()
            defer { refuseLock.unlock() }
            return _refuseUntrustedBinaries
        }
        set {
            refuseLock.lock()
            defer { refuseLock.unlock() }
            _refuseUntrustedBinaries = newValue
        }
    }

    static let trustLock = NSLock()
    static var trustCache: (path: String, issue: String?, checkedAt: TimeInterval)?
    static let trustCacheTTL: TimeInterval = 30

    /// Cached trust check: codesign per shell() is a process spawn per query.
    static func cachedTrustIssue(path: String) -> String? {
        trustLock.lock()
        let cached = trustCache
        trustLock.unlock()
        let now = ProcessInfo.processInfo.systemUptime
        if let cached, cached.path == path, now - cached.checkedAt < trustCacheTTL {
            return cached.issue
        }
        let issue = trustIssue(path: path)
        trustLock.lock()
        trustCache = (path, issue, ProcessInfo.processInfo.systemUptime)
        trustLock.unlock()
        return issue
    }

    func yabaiTrustIssue() -> String? {
        Self.trustIssue(path: yabaiPath)
    }

    /// Pure trust check: owner is root/self plus a valid codesign. Nil when
    /// trusted, human-readable detail otherwise. warnIfYabaiUntrusted logs it;
    /// the lifecycle surfaces it in the yabai alert UI. Bounded: a wedged
    /// codesign cannot block the trust path forever.
    static func trustIssue(path: String) -> String? {
        var statBuf = stat()
        if stat(path, &statBuf) == 0 {
            let ownerOK = statBuf.st_uid == 0 || statBuf.st_uid == getuid()
            if !ownerOK {
                return "untrusted owner (uid \(statBuf.st_uid)) on \(path) — expected root or self"
            }
        }
        do {
            _ = try ProcessRunner.run(
                executable: "/usr/bin/codesign",
                arguments: ["-v", "--strict", path],
                timeout: Self.commandTimeout
            )
        } catch ProcessRunner.Failure.failed {
            return "codesign verify failed for \(path) — check your install source"
        } catch {
            return "could not verify signature for \(path): \(error)"
        }
        return nil
    }

    /// Warn-only trust check: yabai runs with elevated scripting privileges,
    /// so a binary owned by someone else (or with a broken signature) is
    /// worth shouting about. Refusing would brick legit installs.
    static func warnIfYabaiUntrusted(path: String) {
        if let issue = trustIssue(path: path) {
            NSLog("spacemap/yabai: \(issue)")
        }
    }


}
