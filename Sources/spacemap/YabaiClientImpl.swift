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

    private func decodeTolerant<T: Decodable>(_ type: T.Type, from output: String, label: String) throws -> [T] {
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
        case spaceCreationMadeNoProgress(target: Int)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let arguments, let status, let message):
                let detail = message.isEmpty ? "no error output" : message
                return "yabai \(arguments.joined(separator: " ")) failed with status \(status): \(detail)"
            case .commandTimedOut(let arguments, let timeout):
                return "yabai \(arguments.joined(separator: " ")) timed out after \(timeout) seconds"
            case .spaceCreationMadeNoProgress(let target):
                return "yabai did not create the space needed for target index \(target)"
            }
        }
    }

    private static let commandTimeout: TimeInterval = 10

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

    private var _yabaiRunningCache: (result: Bool, checkedAt: TimeInterval)?
    private let yabaiCacheTTL: TimeInterval = 5.0
    private let cacheLock = NSLock()

    var yabaiProcessCheck: () -> Bool = { false }

    init() {
        yabaiProcessCheck = { [weak self] in guard let self else { return false }; return self.defaultYabaiProcessCheck() }
        let path = yabaiPath
        DispatchQueue.global(qos: .utility).async {
            Self.warnIfYabaiUntrusted(path: path)
        }
    }

    /// Refuse to execute the yabai binary when the trust check fails.
    /// Set from GridConfig.refuseUntrustedYabai at launch; default false
    /// (warn-only) so legit installs never brick.
    static var refuseUntrustedBinaries = false

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
    /// the lifecycle surfaces it in the yabai alert UI.
    static func trustIssue(path: String) -> String? {
        var statBuf = stat()
        if stat(path, &statBuf) == 0 {
            let ownerOK = statBuf.st_uid == 0 || statBuf.st_uid == getuid()
            if !ownerOK {
                return "untrusted owner (uid \(statBuf.st_uid)) on \(path) — expected root or self"
            }
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-v", "--strict", path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                return "codesign verify failed for \(path) — check your install source"
            }
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
        let now = ProcessInfo.processInfo.systemUptime
        if !forceRefresh,
           let cached = _yabaiRunningCache,
           now - cached.checkedAt < yabaiCacheTTL {
            let result = cached.result
            cacheLock.unlock()
            return result
        }
        let check = yabaiProcessCheck
        cacheLock.unlock()
        // pgrep outside lock: never hold cacheLock across process spawn.
        let result = check()
        cacheLock.lock()
        _yabaiRunningCache = (result, ProcessInfo.processInfo.systemUptime)
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
        return try querySpacesRaw()
    }

    func queryDisplays() throws -> [YabaiDisplay] {
        guard isYabaiRunning() else { return [] }
        return try queryDisplaysRaw()
    }

    func queryWindows() throws -> [YabaiWindow] {
        guard isYabaiRunning() else { return [] }
        return try queryWindowsRaw()
    }

    private func querySpacesRaw() throws -> [YabaiSpace] {
        guard FileManager.default.isExecutableFile(atPath: yabaiPath) else { return [] }
        let output = try shell(yabaiPath, "-m", "query", "--spaces")
        return try decodeTolerant(YabaiSpace.self, from: output, label: "space")
    }

    private func queryDisplaysRaw() throws -> [YabaiDisplay] {
        guard FileManager.default.isExecutableFile(atPath: yabaiPath) else { return [] }
        let output = try shell(yabaiPath, "-m", "query", "--displays")
        return try decodeTolerant(YabaiDisplay.self, from: output, label: "display")
    }

    private func queryWindowsRaw() throws -> [YabaiWindow] {
        guard FileManager.default.isExecutableFile(atPath: yabaiPath) else { return [] }
        let output = try shell(yabaiPath, "-m", "query", "--windows")
        return try decodeTolerant(YabaiWindow.self, from: output, label: "window")
    }

    func queryFocusedWindow() throws -> Int? {
        guard isYabaiRunning(), FileManager.default.isExecutableFile(atPath: yabaiPath) else { return nil }
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


    func registerSignals(
        socketPath: String,
        showHUDOnSpaceChange: Bool = false,
        refreshWorkspacePreviews: Bool = false,
        refreshWindowGeometry: Bool = true
    ) {
        guard isYabaiRunning(forceRefresh: true) else { return }
        removeSignals()
        let action = spaceChangedSignalAction(
            socketPath: socketPath,
            showHUDOnSpaceChange: showHUDOnSpaceChange
        )
        guard FileManager.default.isExecutableFile(atPath: yabaiPath) else { return }
        _ = try? shell(yabaiPath, "-m", "signal", "--add",
                       "label=spacemap_space_changed",
                       "event=space_changed",
                       "action=\(action)")
        guard refreshWorkspacePreviews else { return }
        let events = previewRefreshEvents(refreshWindowGeometry: refreshWindowGeometry)
        for event in events {
            _ = try? shell(yabaiPath, "-m", "signal", "--add",
                           "label=spacemap_\(event)",
                           "event=\(event)",
                           "action=\(refreshSignalAction(socketPath: socketPath))")
        }
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
        let command = showHUDOnSpaceChange ? SpacemapCommand.show.rawValue : SpacemapCommand.refresh.rawValue
        guard let quoted = SpacemapCommand.shellQuoted(socketPath) else {
            NSLog("spacemap/yabai: refusing signal with untrusted socket path")
            return "/usr/bin/false"
        }
        let nonce = SpacemapCommand.currentNonceHex().map { ":\($0)" } ?? ""
        return "printf '\(command)\(nonce)' | /usr/bin/nc -U \(quoted)"
    }

    func refreshSignalAction(socketPath: String) -> String {
        guard let quoted = SpacemapCommand.shellQuoted(socketPath) else {
            NSLog("spacemap/yabai: refusing signal with untrusted socket path")
            return "/usr/bin/false"
        }
        let nonce = SpacemapCommand.currentNonceHex().map { ":\($0)" } ?? ""
        return "printf '\(SpacemapCommand.refresh.rawValue)\(nonce)' | /usr/bin/nc -U \(quoted)"
    }

    func removeSignals() {
        guard isYabaiRunning(), FileManager.default.isExecutableFile(atPath: yabaiPath) else { return }
        _ = try? shell(yabaiPath, "-m", "signal", "--remove", "spacemap_space_changed")
        for event in workspacePreviewRefreshEvents {
            _ = try? shell(yabaiPath, "-m", "signal", "--remove", "spacemap_\(event)")
        }
    }


    func focusSpace(_ index: Int) {
        guard FileManager.default.isExecutableFile(atPath: yabaiPath), isYabaiRunning() else { return }
        _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(index)")
    }

    @discardableResult
    func focusSpace(_ target: SpaceFocusTarget) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: yabaiPath), isYabaiRunning() else { return false }
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
            guard let self = self, FileManager.default.isExecutableFile(atPath: self.yabaiPath), self.isYabaiRunning() else { return }
            _ = try? self.shell(yabaiPath, "-m", "space", "--focus", "\(index)")
        }
    }


    func createSpace() {
        focusQueue.async { [weak self] in
            guard let self, FileManager.default.isExecutableFile(atPath: self.yabaiPath) else { return }
            self.runIgnoringFailure(["-m", "space", "--create"], "createSpace")
        }
    }

    func destroySpace(_ index: Int) {
        guard index > 0 else { return }
        focusQueue.async { [weak self] in
            guard let self, FileManager.default.isExecutableFile(atPath: self.yabaiPath) else { return }
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
            guard let self, FileManager.default.isExecutableFile(atPath: self.yabaiPath) else { return }
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

    func toggleWindowFullscreen() {
        focusQueue.async { [weak self] in
            guard let self, FileManager.default.isExecutableFile(atPath: self.yabaiPath) else { return }
            self.runIgnoringFailure(["-m", "window", "--toggle", "native-fullscreen"], "toggleFullscreen")
        }
    }

    func balanceWindows() {
        focusQueue.async { [weak self] in
            guard let self, FileManager.default.isExecutableFile(atPath: self.yabaiPath) else { return }
            self.runIgnoringFailure(["-m", "space", "--balance"], "balanceWindows")
        }
    }

    func toggleWindowFloat() {
        focusQueue.async { [weak self] in
            guard let self, FileManager.default.isExecutableFile(atPath: self.yabaiPath) else { return }
            self.runIgnoringFailure(["-m", "window", "--toggle", "float"], "toggleFloat")
        }
    }

    func setSpaceLayout(_ layout: SpaceLayout) {
        // yabaiQueue, not focusQueue: refresh() fetches state on yabaiQueue,
        // so the layout command must be enqueued ahead of that fetch on the
        // same serial queue. On focusQueue the two orderings race and the
        // HUD re-renders the pre-layout snapshot.
        yabaiQueue.async { [weak self] in
            guard let self, FileManager.default.isExecutableFile(atPath: self.yabaiPath) else { return }
            self.runIgnoringFailure(["-m", "space", "--layout", layout.rawValue], "setSpaceLayout(\(layout.rawValue))")
        }
    }

    /// Fire-and-forget yabai command. The result is discarded, but a failure is
    /// logged rather than swallowed: these are driven by menu-bar clicks, so a
    /// silent no-op is indistinguishable from a broken action otherwise.
    private func runIgnoringFailure(_ arguments: [String], _ label: String) {
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

                var spaces = try self.querySpacesRaw()
                var attempts = 0
                while !spaces.contains(where: { $0.index == targetIndex }) {
                    guard attempts < 16 else {
                        throw YabaiError.spaceCreationMadeNoProgress(target: targetIndex)
                    }
                    attempts += 1
                    let previousIndices = Set(spaces.map(\.index))
                    guard FileManager.default.isExecutableFile(atPath: self.yabaiPath) else {
                        throw YabaiError.commandFailed(arguments: ["space", "--create"], status: -1, message: "yabai not found")
                    }
                    _ = try self.shell(yabaiPath, "-m", "space", "--create")
                    spaces = try self.querySpacesRaw()

                    guard Set(spaces.map(\.index)) != previousIndices else {
                        throw YabaiError.spaceCreationMadeNoProgress(target: targetIndex)
                    }
                }

                guard FileManager.default.isExecutableFile(atPath: self.yabaiPath) else {
                    throw YabaiError.commandFailed(arguments: ["window", "\(windowID)", "--space", "\(targetIndex)"], status: -1, message: "yabai not found")
                }
                _ = try self.shell(yabaiPath, "-m", "window", "\(windowID)", "--space", "\(targetIndex)")
                if focusDestination {
                    _ = try self.shell(yabaiPath, "-m", "space", "--focus", "\(targetIndex)")
                }
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }


    func buildGridState(config: GridConfig, focusedIndex: Int? = nil) -> GridState {
        // NSScreen.main is main-only: capture on main, pass in.
        let displayBounds = Self.mainDisplayBounds()
        // Callers already run off-main (yabai queue / utility queue), so query
        // directly instead of fanning out and blocking on group.wait.
        guard isYabaiRunning() else {
            return GridState(config: config, spaces: [], windows: [], displayBounds: displayBounds, focusedIndex: nil)
        }
        let spaces = (try? querySpacesRaw()) ?? []
        let displays = cachedDisplays()
        let windows = (try? queryWindowsRaw()) ?? []
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

    private func cachedDisplays() -> [YabaiDisplay] {
        cacheLock.lock()
        let cached = _displaysCache
        let now = ProcessInfo.processInfo.systemUptime
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
        if let cachedNow = _displaysCache,
           ProcessInfo.processInfo.systemUptime - cachedNow.cachedAt < displaysCacheTTL {
            let displays = cachedNow.displays
            cacheLock.unlock()
            return displays
        }
        guard let fresh, !fresh.isEmpty else {
            let stale = _displaysCache?.displays ?? cached?.displays ?? []
            cacheLock.unlock()
            return stale
        }
        _displaysCache = (fresh, ProcessInfo.processInfo.systemUptime)
        cacheLock.unlock()
        return fresh
    }


    private func shell(_ args: String...) throws -> String {
        try shell(args)
    }

    /// Array form. `shell(path, args...)` cannot be spelled — a trailing `...`
    /// after an identifier parses as a postfix range, not a variadic spread — so
    /// callers that build their argument list dynamically use this instead.
    private func shell(_ args: [String]) throws -> String {
        guard let executable = args.first else { throw YabaiError.commandFailed(arguments: [], status: -1, message: "empty command") }
        if executable == yabaiPath, Self.refuseUntrustedBinaries, let issue = Self.cachedTrustIssue(path: yabaiPath) {
            throw YabaiError.commandFailed(arguments: Array(args.dropFirst()), status: -1, message: "refusing untrusted yabai binary: \(issue)")
        }
        return try Self.runProcessImpl(
            executable: executable,
            arguments: Array(args.dropFirst()),
            timeout: Self.commandTimeout
        )
    }

    private static func runProcessImpl(
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
            // Close pipes on throw: no readers were dispatched, no child runs.
            try? outputPipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            throw error
        }
        outputPipe.fileHandleForWriting.closeFile()
        errorPipe.fileHandleForWriting.closeFile()

        // Drain both pipes on dedicated threads while the process runs so a large
        // output cannot fill the pipe and deadlock the child. Blocking reads are
        // used instead of readabilityHandler callbacks: EOF is guaranteed once the
        // child exits, so no data can be lost to a starved callback queue.
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
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = errorHandle.readDataToEndOfFile()
            errorLock.lock()
            errorData = data
            errorLock.unlock()
            readers.leave()
        }

        if termination.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if termination.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = termination.wait(timeout: .now() + 1)
            }
            readers.wait()
            outputHandle.closeFile()
            errorHandle.closeFile()
            throw YabaiError.commandTimedOut(arguments: arguments, timeout: timeout)
        }
        // The child is dead, so both pipes have hit EOF; the readers are guaranteed to finish.
        readers.wait()
        outputHandle.closeFile()
        errorHandle.closeFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw YabaiError.commandFailed(
                arguments: arguments,
                status: process.terminationStatus,
                message: message
            )
        }
        return String(data: outputData, encoding: .utf8) ?? ""
    }

#if DEBUG
    // Test seam: production path is runProcessImpl (private).
    static func runProcess(executable: String, arguments: [String], timeout: TimeInterval) throws -> String {
        try runProcessImpl(executable: executable, arguments: arguments, timeout: timeout)
    }
#endif
}
