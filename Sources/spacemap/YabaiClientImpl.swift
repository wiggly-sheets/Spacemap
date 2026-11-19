import Foundation
import AppKit

class YabaiClientImpl: YabaiService {
    /// Skips one bad array entry instead of failing the whole query.
    /// One malformed space/window (version skew) must not blank the HUD.
    private struct Failable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            value = try? container.decode(T.self)
        }
    }

    /// Last dropped count per label: persistent skew logs once per count,
    /// not once per refresh.
    private static var lastDropCounts: [String: Int] = [:]
    private static let dropLock = NSLock()

    func decodeTolerant<T: Decodable>(_ type: T.Type, from output: String, label: String) throws -> [T] {
        let decoded = try JSONDecoder().decode([Failable<T>].self, from: Data(output.utf8))
        let dropped = decoded.filter { $0.value == nil }.count
        if dropped > 0 {
            Self.dropLock.lock()
            defer { Self.dropLock.unlock() }
            let last = Self.lastDropCounts[label]
            Self.lastDropCounts[label] = dropped
            if last != dropped { NSLog("spacemap/yabai: dropped %d malformed %@ entries", dropped, label) }
        }
        return decoded.compactMap(\.value)
    }

    private enum YabaiError: LocalizedError {
        case commandFailed(arguments: [String], status: Int32, message: String)
        case commandTimedOut(arguments: [String], timeout: TimeInterval)
        case outputDrainTimedOut(arguments: [String], timeout: TimeInterval)
        case spaceCreationMadeNoProgress(target: Int)
        case spaceCreationTimedOut(target: Int, budget: TimeInterval)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let arguments, let status, let message):
                let detail = message.isEmpty ? "no error output" : message
                return "yabai \(arguments.joined(separator: " ")) failed with status \(status): \(detail)"
            case .commandTimedOut(let arguments, let timeout):
                return "yabai \(arguments.joined(separator: " ")) timed out after \(timeout) seconds"
            case .outputDrainTimedOut(let arguments, let timeout):
                return "yabai \(arguments.joined(separator: " ")) output drain timed out after \(timeout) seconds; a child process is still holding stdout/stderr"
            case .spaceCreationMadeNoProgress(let target):
                return "yabai did not create the space needed for target index \(target)"
            case .spaceCreationTimedOut(let target, let budget):
                return "yabai did not create the space needed for target index \(target) within \(budget) seconds"
            }
        }
    }

    private static let commandTimeout: TimeInterval = 10

    /// Total monotonic-time budget for the create-loop, so 16 attempts cannot
    /// occupy the serial yabai queue for minutes.
    let spaceCreationBudget: TimeInterval

    private let yabaiQueue = DispatchQueue(label: "com.spacemap.yabai", qos: .userInitiated)
    // Keep interactive focus changes ahead of state refreshes.
    private let focusQueue = DispatchQueue(label: "com.spacemap.yabai.focus", qos: .userInteractive)

    private let yabaiPath: String = {
        let arm = "/opt/homebrew/bin/yabai"
        let intel = "/usr/local/bin/yabai"
        if FileManager.default.isExecutableFile(atPath: arm) { return arm }
        if FileManager.default.isExecutableFile(atPath: intel) { return intel }
        return arm
    }()

    private var yabaiIsExecutable: Bool {
#if DEBUG
        if let override = yabaiExecutableOverride { return override }
#endif
        return FileManager.default.isExecutableFile(atPath: yabaiPath)
    }

    private var _yabaiRunningCache: (result: Bool, checkedAt: TimeInterval)?
    private let yabaiCacheTTL: TimeInterval = 5.0
    // NSCondition so snapshot single-flight can wake waiters without polling.
    private let cacheLock = NSCondition()

    private var currentUptime: TimeInterval {
#if DEBUG
        if let override = uptimeOverride { return override() }
#endif
        return ProcessInfo.processInfo.systemUptime
    }

    /// Test seam: production runs through `ProcessRunner`; tests inject a fake
    /// runner so no yabai binary is needed.
    var commandRunnerOverride: ((_ executable: String, _ arguments: [String], _ timeout: TimeInterval) throws -> String)?

#if DEBUG
    /// Test seam: lets cache/deadline tests advance time deterministically.
    var uptimeOverride: (() -> TimeInterval)?
    var yabaiExecutableOverride: Bool?
#endif

    private var _yabaiProcessCheck: () -> Bool = { false }

    var yabaiProcessCheck: () -> Bool {
        get {
            cacheLock.lock()
            defer { cacheLock.unlock() }
            return _yabaiProcessCheck
        }
        set {
            cacheLock.lock()
            defer { cacheLock.unlock() }
            _yabaiProcessCheck = newValue
        }
    }

    init(spaceCreationBudget: TimeInterval = 20) {
        self.spaceCreationBudget = spaceCreationBudget
        yabaiProcessCheck = { [weak self] in guard let self else { return false }; return self.defaultYabaiProcessCheck() }
        signalRetryScheduler = { [weak self] delay, pass in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.yabaiQueue.async(execute: pass)
            }
        }
        let path = yabaiPath
        DispatchQueue.global(qos: .utility).async {
            Self.warnIfYabaiUntrusted(path: path)
        }
    }

    /// Refuse to execute the yabai binary when the trust check fails.
    /// Set from SpacemapConfig.refuseUntrustedYabai at launch; default false
    /// (warn-only) so legit installs never brick.
    private static let refuseLock = NSLock()
    private static var _refuseUntrustedBinaries = false
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

    private static let trustLock = NSLock()
    private static var trustCache: (path: String, issue: String?, checkedAt: TimeInterval)?
    private static let trustCacheTTL: TimeInterval = 30

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
    private static func warnIfYabaiUntrusted(path: String) {
        if let issue = trustIssue(path: path) {
            NSLog("spacemap/yabai: \(issue)")
        }
    }


    func runOnYabaiQueue(_ block: @escaping () -> Void) {
        yabaiQueue.async(execute: block)
    }

    func runOnYabaiQueue(_ workItem: DispatchWorkItem) {
        yabaiQueue.async(execute: workItem)
    }


    private func defaultYabaiProcessCheck() -> Bool {
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


    func querySpaces() throws -> [YabaiSpace] {
        guard isYabaiRunning() else { return [] }
        return try cachedSpaces()
    }

    func queryDisplays() throws -> [YabaiDisplay] {
        guard isYabaiRunning() else { return [] }
        return try queryDisplaysRaw()
    }

    func queryWindows() throws -> [YabaiWindow] {
        guard isYabaiRunning() else { return [] }
        return try cachedWindows()
    }

    func windowSpaceSignature() throws -> String {
        guard isYabaiRunning() else { return "" }
        return try cachedWindows()
            .sorted { $0.id < $1.id }
            .map { "\($0.id):\($0.space)" }
            .joined(separator: ",")
    }

    private func querySpacesRaw(timeout: TimeInterval? = nil) throws -> [YabaiSpace] {
        guard yabaiIsExecutable else {
            throw YabaiError.commandFailed(arguments: ["-m", "query", "--spaces"], status: -1, message: "yabai not found")
        }
        let output = try shell([yabaiPath, "-m", "query", "--spaces"], timeout: timeout)
        return try decodeTolerant(YabaiSpace.self, from: output, label: "space")
    }

    private func queryDisplaysRaw() throws -> [YabaiDisplay] {
        guard yabaiIsExecutable else {
            throw YabaiError.commandFailed(arguments: ["-m", "query", "--displays"], status: -1, message: "yabai not found")
        }
        let output = try shell(yabaiPath, "-m", "query", "--displays")
        return try decodeTolerant(YabaiDisplay.self, from: output, label: "display")
    }

    private func queryWindowsRaw(timeout: TimeInterval? = nil) throws -> [YabaiWindow] {
        guard yabaiIsExecutable else {
            throw YabaiError.commandFailed(arguments: ["-m", "query", "--windows"], status: -1, message: "yabai not found")
        }
        let output = try shell([yabaiPath, "-m", "query", "--windows"], timeout: timeout)
        return try decodeTolerant(YabaiWindow.self, from: output, label: "window")
    }

    // Short-lived snapshots coalesce the HUD/glyph/menubar fan-out that lands
    // within a few milliseconds of one signal. Mutating commands invalidate
    // them so a user-initiated refresh never re-reads pre-mutation state.
    private var _spacesCache: (spaces: [YabaiSpace], cachedAt: TimeInterval)?
    private var _windowsCache: (windows: [YabaiWindow], cachedAt: TimeInterval)?
    private let snapshotCacheTTL: TimeInterval = 0.3
    /// Last-good snapshots older than this must not be served: a permanently
    /// failing yabai should surface its empty/error state, not pin a stale HUD.
    private let snapshotStaleTTL: TimeInterval = 5
    /// Single-flight waiters must outlast the whole kill ladder (timeout, TERM
    /// grace, KILL grace, drain, exit wait) or they spawn a duplicate query
    /// while the first is still tearing down.
    private static let snapshotWaitBound: TimeInterval =
        commandTimeout + 2 * ProcessRunner.killGrace + ProcessRunner.drainTimeout + 1
    private var spacesFetchInFlight = false
    private var windowsFetchInFlight = false
    private var snapshotGeneration = 0

    private func cachedSpaces(retryOnGenerationMismatch: Bool = true) throws -> [YabaiSpace] {
        cacheLock.lock()
        let cached = _spacesCache
        let now = currentUptime
        if let cached, now - cached.cachedAt < snapshotCacheTTL {
            cacheLock.unlock()
            return cached.spaces
        }
        if spacesFetchInFlight {
            // Single-flight: concurrent callers wait for the one in-flight
            // query instead of spawning duplicates or serving stale data.
            let waitUntil = Date().addingTimeInterval(Self.snapshotWaitBound)
            while spacesFetchInFlight && Date() < waitUntil {
                cacheLock.wait(until: waitUntil)
            }
            let cachedNow = _spacesCache
            let afterWait = currentUptime
            if let cachedNow, afterWait - cachedNow.cachedAt < snapshotCacheTTL {
                cacheLock.unlock()
                return cachedNow.spaces
            }
            if spacesFetchInFlight {
                // Bounded wait expired; fall back to our own query.
                cacheLock.unlock()
                return try querySpacesRaw()
            }
            // The in-flight fetch failed without producing a usable result.
        }
        let generation = snapshotGeneration
        spacesFetchInFlight = true
        cacheLock.unlock()

        let fresh: Result<[YabaiSpace], Error>
        do {
            fresh = .success(try querySpacesRaw())
        } catch {
            fresh = .failure(error)
        }

        cacheLock.lock()
        spacesFetchInFlight = false
        cacheLock.broadcast()
        let completedAt = currentUptime

        if generation != snapshotGeneration {
            // State changed while querying: never return pre-mutation data.
            let cachedNow = _spacesCache
            cacheLock.unlock()
            if let cachedNow, completedAt - cachedNow.cachedAt < snapshotCacheTTL {
                return cachedNow.spaces
            }
            if retryOnGenerationMismatch {
                return try cachedSpaces(retryOnGenerationMismatch: false)
            }
            switch fresh {
            case .success(let spaces):
                return spaces
            case .failure(let error):
                if let cachedNow, completedAt - cachedNow.cachedAt < snapshotStaleTTL {
                    return cachedNow.spaces
                }
                throw error
            }
        }

        // A concurrent fill landed while querying: serve it instead.
        if let cachedNow = _spacesCache,
           completedAt - cachedNow.cachedAt < snapshotCacheTTL {
            let spaces = cachedNow.spaces
            cacheLock.unlock()
            return spaces
        }
        switch fresh {
        case .success(let spaces):
            // A transient empty spaces result must not evict a good snapshot.
            if spaces.isEmpty,
               let existing = _spacesCache,
               !existing.spaces.isEmpty,
               completedAt - existing.cachedAt < snapshotStaleTTL {
                let stale = existing.spaces
                cacheLock.unlock()
                return stale
            }
            _spacesCache = (spaces, completedAt)
            cacheLock.unlock()
            return spaces
        case .failure(let error):
            let staleEntry = _spacesCache ?? cached
            cacheLock.unlock()
            if let staleEntry, completedAt - staleEntry.cachedAt < snapshotStaleTTL {
                return staleEntry.spaces
            }
            throw error
        }
    }

    private func cachedWindows(retryOnGenerationMismatch: Bool = true) throws -> [YabaiWindow] {
        cacheLock.lock()
        let cached = _windowsCache
        let now = currentUptime
        if let cached, now - cached.cachedAt < snapshotCacheTTL {
            cacheLock.unlock()
            return cached.windows
        }
        if windowsFetchInFlight {
            let waitUntil = Date().addingTimeInterval(Self.snapshotWaitBound)
            while windowsFetchInFlight && Date() < waitUntil {
                cacheLock.wait(until: waitUntil)
            }
            let cachedNow = _windowsCache
            let afterWait = currentUptime
            if let cachedNow, afterWait - cachedNow.cachedAt < snapshotCacheTTL {
                cacheLock.unlock()
                return cachedNow.windows
            }
            if windowsFetchInFlight {
                cacheLock.unlock()
                return try queryWindowsRaw()
            }
        }
        let generation = snapshotGeneration
        windowsFetchInFlight = true
        cacheLock.unlock()

        let fresh: Result<[YabaiWindow], Error>
        do {
            fresh = .success(try queryWindowsRaw())
        } catch {
            fresh = .failure(error)
        }

        cacheLock.lock()
        windowsFetchInFlight = false
        cacheLock.broadcast()
        let completedAt = currentUptime

        if generation != snapshotGeneration {
            let cachedNow = _windowsCache
            cacheLock.unlock()
            if let cachedNow, completedAt - cachedNow.cachedAt < snapshotCacheTTL {
                return cachedNow.windows
            }
            if retryOnGenerationMismatch {
                return try cachedWindows(retryOnGenerationMismatch: false)
            }
            switch fresh {
            case .success(let windows):
                return windows
            case .failure(let error):
                if let cachedNow, completedAt - cachedNow.cachedAt < snapshotStaleTTL {
                    return cachedNow.windows
                }
                throw error
            }
        }

        if let cachedNow = _windowsCache,
           completedAt - cachedNow.cachedAt < snapshotCacheTTL {
            let windows = cachedNow.windows
            cacheLock.unlock()
            return windows
        }
        switch fresh {
        case .success(let windows):
            _windowsCache = (windows, completedAt)
            cacheLock.unlock()
            return windows
        case .failure(let error):
            let staleEntry = _windowsCache ?? cached
            cacheLock.unlock()
            if let staleEntry, completedAt - staleEntry.cachedAt < snapshotStaleTTL {
                return staleEntry.windows
            }
            throw error
        }
    }

    /// Called after any yabai command that can change spaces/windows/focus,
    /// including mutations made outside Spacemap (socket onRefresh/onShow).
    func invalidateSnapshotCaches() {
        cacheLock.lock()
        snapshotGeneration += 1
        _spacesCache = nil
        _windowsCache = nil
        cacheLock.unlock()
    }

    func queryFocusedWindow() throws -> Int? {
        guard isYabaiRunning(), yabaiIsExecutable else { return nil }
        let output = try shell(yabaiPath, "-m", "query", "--windows", "--window")
        guard let data = output.data(using: .utf8),
              let json = try? JSONDecoder().decode(YabaiWindow.self, from: data) else { return nil }
        return json.id
    }

    func queryFocusedSpaceIndex() -> Int? {
        guard isYabaiRunning() else { return nil }
        do {
            let spaces = try querySpacesRaw()
            return spaces.first { $0.hasFocus }?.index
        } catch {
            return nil
        }
    }


    /// Delays before each registration retry. A daemon that just started
    /// accepts `--add` before it can hold a signal, so the first attempts fail.
    /// Six attempts total: the immediate one, then one per delay (31s bound).
    static let signalRegistrationRetryDelays: [TimeInterval] = [1, 2, 4, 8, 16]

    /// Test seam: tests run the retry inline so attempt counts stay
    /// deterministic. Production delays off-main and runs the pass on the
    /// yabai queue.
    var signalRetryScheduler: (_ delay: TimeInterval, _ pass: @escaping () -> Void) -> Void = { delay, pass in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: pass)
    }

    private let signalRegistrationLock = NSLock()
    private var signalRegistrationToken = 0

    func registerSignals(
        socketPath: String,
        showHUDOnSpaceChange: Bool = false,
        refreshWorkspacePreviews: Bool = false,
        refreshWindowGeometry: Bool = true
    ) {
        // A new trigger supersedes a retry chain that is still pending.
        signalRegistrationLock.lock()
        signalRegistrationToken += 1
        let token = signalRegistrationToken
        signalRegistrationLock.unlock()
        attemptSignalRegistration(
            socketPath: socketPath,
            showHUDOnSpaceChange: showHUDOnSpaceChange,
            refreshWorkspacePreviews: refreshWorkspacePreviews,
            refreshWindowGeometry: refreshWindowGeometry,
            attempt: 0,
            token: token
        )
    }

    private func isCurrentSignalRegistration(_ token: Int) -> Bool {
        signalRegistrationLock.lock()
        defer { signalRegistrationLock.unlock() }
        return token == signalRegistrationToken
    }

    private func attemptSignalRegistration(
        socketPath: String,
        showHUDOnSpaceChange: Bool,
        refreshWorkspacePreviews: Bool,
        refreshWindowGeometry: Bool,
        attempt: Int,
        token: Int
    ) {
        guard isCurrentSignalRegistration(token) else { return }
        guard isYabaiRunning(forceRefresh: true) else { return }
        // A nonce-less action is always dropped by the listener. Leave any
        // existing working signals alone instead of replacing them with no-ops.
        guard SpacemapCommand.currentNonceHex(for: socketPath) != nil else {
            NSLog("spacemap/yabai: skipping signal registration — nonce missing")
            return
        }
        guard yabaiIsExecutable else { return }
        if installSignals(
            socketPath: socketPath,
            showHUDOnSpaceChange: showHUDOnSpaceChange,
            refreshWorkspacePreviews: refreshWorkspacePreviews,
            refreshWindowGeometry: refreshWindowGeometry
        ) {
            NSLog("spacemap/yabai: yabai signals registered on attempt %d", attempt + 1)
            return
        }
        let delays = Self.signalRegistrationRetryDelays
        let next = attempt + 1
        // `attempt` indexes the delay for the retry it is about to schedule, so
        // the last attempt (one past the array) gives up instead of retrying.
        guard attempt < delays.count else {
            NSLog("spacemap/yabai: yabai signal registration failed after %d attempts — signals stay unregistered until the next yabai restart", attempt + 1)
            return
        }
        signalRetryScheduler(delays[attempt]) { [weak self] in
            guard let self, self.isCurrentSignalRegistration(token) else { return }
            self.attemptSignalRegistration(
                socketPath: socketPath,
                showHUDOnSpaceChange: showHUDOnSpaceChange,
                refreshWorkspacePreviews: refreshWorkspacePreviews,
                refreshWindowGeometry: refreshWindowGeometry,
                attempt: next,
                token: token
            )
        }
    }

    /// One remove-all-then-add pass, then read the signal table back: a daemon
    /// that is still starting accepts an add and silently keeps no signal.
    private func installSignals(
        socketPath: String,
        showHUDOnSpaceChange: Bool,
        refreshWorkspacePreviews: Bool,
        refreshWindowGeometry: Bool
    ) -> Bool {
        removeSignals()
        let action = spaceChangedSignalAction(
            socketPath: socketPath,
            showHUDOnSpaceChange: showHUDOnSpaceChange
        )
        _ = try? shell(yabaiPath, "-m", "signal", "--add",
                       "label=spacemap_space_changed",
                       "event=space_changed",
                       "action=\(action)")
        if refreshWorkspacePreviews {
            for event in previewRefreshEvents(refreshWindowGeometry: refreshWindowGeometry) {
                _ = try? shell(yabaiPath, "-m", "signal", "--add",
                               "label=spacemap_\(event)",
                               "event=\(event)",
                               "action=\(refreshSignalAction(socketPath: socketPath))")
            }
        }
        guard let listing = try? shell(yabaiPath, "-m", "signal", "--list"),
              let nonce = SpacemapCommand.currentNonceHex(for: socketPath)
        else { return false }
        return listingShowsLiveSpaceChangedSignal(listing, nonce: nonce)
    }

    /// `--list` prints one JSON-like object per signal, with `label` before
    /// `action`. A label alone is not enough: a stale signal left behind by a
    /// failed remove still carries the old nonce, whose actions never reach
    /// this process. Require the current nonce inside this label's own object.
    private func listingShowsLiveSpaceChangedSignal(_ listing: String, nonce: String) -> Bool {
        guard let label = listing.range(of: "spacemap_space_changed") else { return false }
        let remainder = listing[label.upperBound...]
        let entry = remainder.range(of: "\"label\"").map { remainder[..<$0.lowerBound] } ?? remainder
        return entry.contains(":\(nonce)")
    }

    let windowGeometryRefreshEvents: [String] = [
        "window_created",
        "window_destroyed",
        "window_moved",
        "window_resized",
        "window_minimized",
        "window_deminimized",
        // Focus changes alter which space is highlighted, and an app gaining or
        // losing focus changes the window list without a create/destroy event.
        "window_focused",
        "app_focused"
    ]

    let workspaceTopologyRefreshEvents: [String] = [
        "space_created",
        "space_destroyed",
        "display_added",
        "display_removed",
        "display_moved",
        "display_resized"
    ]

    var workspacePreviewRefreshEvents: [String] {
        windowGeometryRefreshEvents + workspaceTopologyRefreshEvents
    }

    func previewRefreshEvents(refreshWindowGeometry: Bool) -> [String] {
        refreshWindowGeometry ? workspacePreviewRefreshEvents : workspaceTopologyRefreshEvents
    }

    func spaceChangedSignalAction(socketPath: String, showHUDOnSpaceChange: Bool) -> String {
        guard let quoted = SpacemapCommand.shellQuoted(socketPath) else {
            NSLog("spacemap/yabai: refusing signal with untrusted socket path")
            return "/usr/bin/false"
        }
        guard let nonce = SpacemapCommand.currentNonceHex(for: socketPath) else {
            NSLog("spacemap/yabai: refusing signal without a nonce")
            return "/usr/bin/false"
        }
        guard let command = (showHUDOnSpaceChange ? SpacemapCommand.show : .refresh).socketByte else {
            return "/usr/bin/false"
        }
        return "printf '\(command):\(nonce)' | /usr/bin/nc -U \(quoted)"
    }

    func refreshSignalAction(socketPath: String) -> String {
        guard let quoted = SpacemapCommand.shellQuoted(socketPath) else {
            NSLog("spacemap/yabai: refusing signal with untrusted socket path")
            return "/usr/bin/false"
        }
        guard let nonce = SpacemapCommand.currentNonceHex(for: socketPath) else {
            NSLog("spacemap/yabai: refusing signal without a nonce")
            return "/usr/bin/false"
        }
        guard let command = SpacemapCommand.refresh.socketByte else { return "/usr/bin/false" }
        return "printf '\(command):\(nonce)' | /usr/bin/nc -U \(quoted)"
    }

    func removeSignals() {
        guard isYabaiRunning(), yabaiIsExecutable else { return }
        _ = try? shell(yabaiPath, "-m", "signal", "--remove", "spacemap_space_changed")
        for event in workspacePreviewRefreshEvents {
            _ = try? shell(yabaiPath, "-m", "signal", "--remove", "spacemap_\(event)")
        }
    }


    func focusSpace(_ index: Int) {
        guard yabaiIsExecutable, isYabaiRunning() else { return }
        _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(index)")
        invalidateSnapshotCaches()
    }

    @discardableResult
    func focusSpace(_ target: SpaceFocusTarget) -> Bool {
        guard yabaiIsExecutable, isYabaiRunning() else { return false }
        defer { invalidateSnapshotCaches() }
        do {
            _ = try shell(yabaiPath, "-m", "space", "--focus", target.value)
            return true
        } catch {
            fputs("spacemap: \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    func focusSpaceAsync(_ index: Int) {
        focusQueue.async { [weak self] in
            guard let self = self, self.yabaiIsExecutable, self.isYabaiRunning() else { return }
            _ = try? self.shell(yabaiPath, "-m", "space", "--focus", "\(index)")
            self.invalidateSnapshotCaches()
        }
    }


    struct SpaceSwapStep: Equatable {
        let windowID: Int
        let target: Int
    }

    /// Each window moves to the opposite space. IDs are captured before any
    /// move so a window never gets moved twice.
    static func spaceSwapPlan(windows: [YabaiWindow], first: Int, second: Int) -> [SpaceSwapStep] {
        let fromFirst = windows.filter { $0.space == first }
            .map { SpaceSwapStep(windowID: $0.id, target: second) }
        let fromSecond = windows.filter { $0.space == second }
            .map { SpaceSwapStep(windowID: $0.id, target: first) }
        return fromFirst + fromSecond
    }

    func swapSpaces(_ first: Int, _ second: Int, mode: SpaceDropMode, focusMode: DragFocusMode) {
        guard first > 0, second > 0, first != second else { return }
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable, self.isYabaiRunning() else { return }
            switch mode {
            case .content: self.swapSpaceContents(first, second, focusMode: focusMode)
            case .spaces: self.moveSpaces(first, second, focusMode: focusMode)
            }
            self.invalidateSnapshotCaches()
        }
    }

    /// Swap the windows between two spaces. Mission Control order and empty
    /// spaces stay unchanged; the visible content swaps.
    private func swapSpaceContents(_ first: Int, _ second: Int, focusMode: DragFocusMode) {
        guard let windows = try? queryWindowsRaw() else { return }
        let plan = Self.spaceSwapPlan(windows: windows, first: first, second: second)
        for step in plan {
            _ = try? shell(yabaiPath, "-m", "window", "\(step.windowID)", "--space", "\(step.target)")
        }
        focusAfterSpaceDrag(focusMode, source: first, destination: second)
    }

    /// Reorder the spaces themselves. Requires a yabai build with macOS 27.2
    /// space-move support. yabai can only swap the selected space, so focus
    /// the source first and restore the original focus afterwards.
    private func moveSpaces(_ first: Int, _ second: Int, focusMode: DragFocusMode) {
        let originalUUID = focusedSpaceUUID()
        _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(first)")
        for _ in 0..<40 where focusedSpaceUUID() != spaceUUID(forIndex: first) {
            Thread.sleep(forTimeInterval: 0.025)
        }
        _ = try? shell(yabaiPath, "-m", "space", "--swap", "\(second)")
        switch focusMode {
        case .stay:
            if let originalUUID, let originalIndex = spaceIndex(forUUID: originalUUID) {
                _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(originalIndex)")
            }
        case .destination:
            _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(second)")
        case .source:
            _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(first)")
        }
    }

    private func focusAfterSpaceDrag(_ mode: DragFocusMode, source: Int, destination: Int) {
        switch mode {
        case .stay: return
        case .destination: _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(destination)")
        case .source: _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(source)")
        }
    }

    private func spaceUUID(forIndex index: Int) -> String? {
        guard let data = try? shell(yabaiPath, "-m", "query", "--spaces"),
              let spaces = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [[String: Any]] else { return nil }
        return spaces.first(where: { $0["index"] as? Int == index })?["uuid"] as? String
    }

    /// UUIDs are not in `YabaiSpace`, but the swap restore needs them: after a
    /// swap the original space's index changes while its content stays.
    private func focusedSpaceUUID() -> String? {
        guard let data = try? shell(yabaiPath, "-m", "query", "--spaces"),
              let spaces = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [[String: Any]] else { return nil }
        return spaces.first(where: { $0["has-focus"] as? Bool == true })?["uuid"] as? String
    }

    private func spaceIndex(forUUID uuid: String) -> Int? {
        guard let data = try? shell(yabaiPath, "-m", "query", "--spaces"),
              let spaces = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [[String: Any]] else { return nil }
        return spaces.first(where: { $0["uuid"] as? String == uuid })?["index"] as? Int
    }

    func createSpace() {
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            self.runIgnoringFailure(["-m", "space", "--create"], "createSpace")
        }
    }

    func destroySpace(_ index: Int) {
        guard index > 0 else { return }
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            self.runIgnoringFailure(["-m", "space", "--destroy", "\(index)"], "destroySpace(\(index))")
        }
    }

    func moveFocusedWindow(toSpace index: Int) {
        moveWindows([], toSpace: index)
    }

    func moveWindows(_ windowIDs: [Int], toSpace index: Int) {
        guard index > 0 else { return }
        // An empty list means "the focused window", which is yabai's default target.
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            if windowIDs.isEmpty {
                self.runIgnoringFailure(["-m", "window", "--space", "\(index)"], "moveFocusedWindow")
                return
            }
            for windowID in windowIDs {
                self.runIgnoringFailure(
                    ["-m", "window", "\(windowID)", "--space", "\(index)"],
                    "moveWindow(\(windowID))"
                )
            }
        }
    }

    func moveWindows(_ windowIDs: [Int], toSpace index: Int, focusMode: DragFocusMode, sourceSpace: Int?) {
        guard index > 0 else { return }
        // An empty list means "the focused window", which is yabai's default target.
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            if windowIDs.isEmpty {
                self.runIgnoringFailure(["-m", "window", "--space", "\(index)"], "moveFocusedWindow")
            } else {
                for windowID in windowIDs {
                    self.runIgnoringFailure(
                        ["-m", "window", "\(windowID)", "--space", "\(index)"],
                        "moveWindow(\(windowID))"
                    )
                }
            }
            switch focusMode {
            case .destination:
                _ = try? self.shell(self.yabaiPath, "-m", "space", "--focus", "\(index)")
            case .source:
                if let sourceSpace, sourceSpace > 0 {
                    _ = try? self.shell(self.yabaiPath, "-m", "space", "--focus", "\(sourceSpace)")
                }
            case .stay:
                if let sourceSpace, sourceSpace > 0 {
                    _ = try? self.shell(self.yabaiPath, "-m", "space", "--focus", "\(sourceSpace)")
                }
            }
        }
    }

    func toggleWindowFullscreen() {
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            self.runIgnoringFailure(["-m", "window", "--toggle", "native-fullscreen"], "toggleFullscreen")
        }
    }

    func balanceWindows() {
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            self.runIgnoringFailure(["-m", "space", "--balance"], "balanceWindows")
        }
    }

    func toggleWindowFloat() {
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            self.runIgnoringFailure(["-m", "window", "--toggle", "float"], "toggleFloat")
        }
    }

    func setSpaceLayout(_ layout: SpaceLayout) {
        // yabaiQueue, not focusQueue: refresh() fetches state on yabaiQueue,
        // so the layout command must be enqueued ahead of that fetch on the
        // same serial queue. On focusQueue the two orderings race and the
        // HUD re-renders the pre-layout snapshot.
        yabaiQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            self.runIgnoringFailure(["-m", "space", "--layout", layout.rawValue], "setSpaceLayout(\(layout.rawValue))")
        }
    }

    /// Fire-and-forget yabai command. The result is discarded, but a failure is
    /// logged rather than swallowed: these are driven by menu-bar clicks, so a
    /// silent no-op is indistinguishable from a broken action otherwise.
    private func runIgnoringFailure(_ arguments: [String], _ label: String) {
        defer { invalidateSnapshotCaches() }
        do {
            _ = try shell([yabaiPath] + arguments)
        } catch {
            NSLog("spacemap/yabai: \(label) failed — \(error.localizedDescription)")
        }
    }

    func showSpacemap() {
        do { try SpacemapCommand.show.send() } catch { fputs("spacemap: \(error)\n", stderr) }
    }


    func moveWindowCreatingSpacesIfNeeded(
        _ windowID: Int,
        toSpace targetIndex: Int,
        focusDestination: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        yabaiQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                guard targetIndex > 0 else {
                    throw YabaiError.spaceCreationMadeNoProgress(target: targetIndex)
                }

                let budget = self.spaceCreationBudget
                guard budget > 0 else {
                    throw YabaiError.spaceCreationTimedOut(target: targetIndex, budget: budget)
                }
                let deadline = self.currentUptime + budget

                func remainingBudget() throws -> TimeInterval {
                    let remaining = deadline - self.currentUptime
                    guard remaining > 0 else {
                        throw YabaiError.spaceCreationTimedOut(target: targetIndex, budget: budget)
                    }
                    return min(remaining, YabaiClientImpl.commandTimeout)
                }

                func querySpacesWithinBudget() throws -> [YabaiSpace] {
                    let timeout = try remainingBudget()
                    do {
                        return try self.querySpacesRaw(timeout: timeout)
                    } catch YabaiError.commandTimedOut(_, _) {
                        throw YabaiError.spaceCreationTimedOut(target: targetIndex, budget: budget)
                    }
                }

                func runWithinBudget(_ arguments: [String]) throws -> String {
                    let timeout = try remainingBudget()
                    do {
                        return try self.shell([self.yabaiPath] + arguments, timeout: timeout)
                    } catch YabaiError.commandTimedOut(_, _) {
                        throw YabaiError.spaceCreationTimedOut(target: targetIndex, budget: budget)
                    }
                }

                var spaces = try querySpacesWithinBudget()
                var attempts = 0
                while !spaces.contains(where: { $0.index == targetIndex }) {
                    guard attempts < 16 else {
                        throw YabaiError.spaceCreationMadeNoProgress(target: targetIndex)
                    }
                    attempts += 1
                    let previousIndices = Set(spaces.map(\.index))
                    guard self.yabaiIsExecutable else {
                        throw YabaiError.commandFailed(arguments: ["space", "--create"], status: -1, message: "yabai not found")
                    }
                    _ = try runWithinBudget(["-m", "space", "--create"])
                    self.invalidateSnapshotCaches()
                    spaces = try querySpacesWithinBudget()

                    guard Set(spaces.map(\.index)) != previousIndices else {
                        throw YabaiError.spaceCreationMadeNoProgress(target: targetIndex)
                    }
                }

                guard self.yabaiIsExecutable else {
                    throw YabaiError.commandFailed(arguments: ["window", "\(windowID)", "--space", "\(targetIndex)"], status: -1, message: "yabai not found")
                }
                _ = try runWithinBudget(["-m", "window", "\(windowID)", "--space", "\(targetIndex)"])
                if focusDestination {
                    _ = try runWithinBudget(["-m", "space", "--focus", "\(targetIndex)"])
                }
                self.invalidateSnapshotCaches()
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }


    func buildGridState(config: SpacemapConfig, focusedIndex: Int? = nil) -> GridState {
        // NSScreen.main is main-only: capture on main, pass in.
        let displayBounds = Self.mainDisplayBounds()
        // Callers already run off-main (yabai queue / utility queue), so query
        // directly instead of fanning out and blocking on group.wait.
        guard isYabaiRunning() else {
            return GridState(config: config, spaces: [], windows: [], displayBounds: displayBounds, focusedIndex: nil)
        }
        // Cached snapshots keep the last good result when a query fails, so a
        // transient timeout never publishes an empty grid and blanks the HUD.
        let spaces = (try? cachedSpaces()) ?? []
        let displays = cachedDisplays()
        let windows = (try? cachedWindows()) ?? []
        let resolvedFocus = focusedIndex ?? spaces.first { $0.hasFocus }?.index
        return GridState(config: config, spaces: spaces, windows: windows, displayBounds: displayBounds, focusedIndex: resolvedFocus, displays: displays)
    }

    private static let boundsLock = NSLock()
    private static var cachedMainBounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    private static func mainDisplayBounds() -> CGRect {
        let fallback = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        if Thread.isMainThread {
            let bounds = NSScreen.main?.frame ?? fallback
            boundsLock.lock()
            cachedMainBounds = bounds
            boundsLock.unlock()
            return bounds
        }
        // Never main.sync: buildGridState runs off-main and main may wait
        // on it. Refresh cache async, return last known bounds now.
        DispatchQueue.main.async {
            let bounds = NSScreen.main?.frame ?? fallback
            boundsLock.lock()
            cachedMainBounds = bounds
            boundsLock.unlock()
        }
        boundsLock.lock()
        defer { boundsLock.unlock() }
        return cachedMainBounds
    }

    private var _displaysCache: (displays: [YabaiDisplay], cachedAt: TimeInterval)?
    private let displaysCacheTTL: TimeInterval = 5.0
    private var displaysFetchInFlight = false

    func cachedDisplays() -> [YabaiDisplay] {
        cacheLock.lock()
        let cached = _displaysCache
        let now = currentUptime
        if let cached, now - cached.cachedAt < displaysCacheTTL {
            cacheLock.unlock()
            return cached.displays
        }
        // Single-flight: a concurrent miss serves stale instead of a second spawn.
        if displaysFetchInFlight {
            let stale = cached?.displays ?? []
            cacheLock.unlock()
            return stale
        }
        displaysFetchInFlight = true
        cacheLock.unlock()
        // Cache only non-empty results: a failed query yields [] and must not
        // evict the last good snapshot for a full TTL, or multi-monitor blanks.
        // On failure return last good (or [] if none) without touching cache,
        // so the next call retries instead of serving stale emptiness.
        let fresh = try? queryDisplaysRaw()
        cacheLock.lock()
        displaysFetchInFlight = false
        // Recheck under lock: a concurrent fill may have landed while querying.
        let completedAt = currentUptime
        if let cachedNow = _displaysCache,
           completedAt - cachedNow.cachedAt < displaysCacheTTL {
            let displays = cachedNow.displays
            cacheLock.unlock()
            return displays
        }
        guard let fresh, !fresh.isEmpty else {
            let stale = _displaysCache?.displays ?? cached?.displays ?? []
            cacheLock.unlock()
            return stale
        }
        _displaysCache = (fresh, completedAt)
        cacheLock.unlock()
        return fresh
    }


    private func shell(_ args: String...) throws -> String {
        try shell(args)
    }

    /// Array form. `shell(path, args...)` cannot be spelled — a trailing `...`
    /// after an identifier parses as a postfix range, not a variadic spread — so
    /// callers that build their argument list dynamically use this instead.
    private func shell(_ args: [String], timeout: TimeInterval? = nil) throws -> String {
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
