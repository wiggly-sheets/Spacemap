import Foundation
import AppKit

class YabaiClientImpl: YabaiService {
    enum YabaiError: LocalizedError {
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

    static let commandTimeout: TimeInterval = 10

    /// Total monotonic-time budget for the create-loop, so 16 attempts cannot
    /// occupy the serial yabai queue for minutes.
    let spaceCreationBudget: TimeInterval

    let yabaiQueue = DispatchQueue(label: "com.spacemap.yabai", qos: .userInitiated)
    // Keep interactive focus changes ahead of state refreshes.
    let focusQueue = DispatchQueue(label: "com.spacemap.yabai.focus", qos: .userInteractive)

    let yabaiPath: String = {
        let arm = "/opt/homebrew/bin/yabai"
        let intel = "/usr/local/bin/yabai"
        if FileManager.default.isExecutableFile(atPath: arm) { return arm }
        if FileManager.default.isExecutableFile(atPath: intel) { return intel }
        return arm
    }()

    var yabaiIsExecutable: Bool {
#if DEBUG
        if let override = yabaiExecutableOverride { return override }
#endif
        return FileManager.default.isExecutableFile(atPath: yabaiPath)
    }

    var _yabaiRunningCache: (result: Bool, checkedAt: TimeInterval)?
    let yabaiCacheTTL: TimeInterval = 5.0
    // NSCondition so snapshot single-flight can wake waiters without polling.
    let cacheLock = NSCondition()

    var currentUptime: TimeInterval {
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

    var _yabaiProcessCheck: () -> Bool = { false }

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

    var _spacesCache: (spaces: [YabaiSpace], cachedAt: TimeInterval)?
    var _windowsCache: (windows: [YabaiWindow], cachedAt: TimeInterval)?
    let snapshotCacheTTL: TimeInterval = 0.3
    /// Last-good snapshots older than this must not be served: a permanently
    /// failing yabai should surface its empty/error state, not pin a stale HUD.
    let snapshotStaleTTL: TimeInterval = 5
    /// Single-flight waiters must outlast the whole kill ladder (timeout, TERM
    /// grace, KILL grace, drain, exit wait) or they spawn a duplicate query
    /// while the first is still tearing down.
    static let snapshotWaitBound: TimeInterval =
        commandTimeout + 2 * ProcessRunner.killGrace + ProcessRunner.drainTimeout + 1
    var spacesFetchInFlight = false
    var windowsFetchInFlight = false
    var snapshotGeneration = 0

    /// Test seam: tests run the retry inline so attempt counts stay
    /// deterministic. Production delays off-main and runs the pass on the
    /// yabai queue.
    var signalRetryScheduler: (_ delay: TimeInterval, _ pass: @escaping () -> Void) -> Void = { delay, pass in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: pass)
    }

    let signalRegistrationLock = NSLock()
    var signalRegistrationToken = 0

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

    var _displaysCache: (displays: [YabaiDisplay], cachedAt: TimeInterval)?
    let displaysCacheTTL: TimeInterval = 5.0
    var displaysFetchInFlight = false

}
