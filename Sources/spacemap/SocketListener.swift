import Foundation
import Security
final class SocketListener {
    let socketPath: String
    let healthInterval: Int
    let onRefresh: () -> Void
    let onShow: () -> Void
    let onToggle: () -> Void
    let onSettings: () -> Void
    let onReloadConfig: () -> Void
    let onUpdate: () -> Void
    let onUpdateFont: () -> Void
    var serverFd: Int32 = -1
    var source: DispatchSourceRead?
    var healthTimer: DispatchSourceTimer?
    var isStopped = false
    var restartScheduled = false
    var ownsSocketFile = false
    var bindFailureCount = 0
    var didFail = false
    var failureReason: String?
    var pendingClients: [Int32] = []
    let listenerQueue = DispatchQueue(label: "com.spacemap.socketlistener")
    let clientQueue = DispatchQueue(label: "com.spacemap.socketlistener.client", attributes: .concurrent)
    let queueKey = DispatchSpecificKey<Void>()
    let clientSlots = DispatchSemaphore(value: SocketListener.maxConcurrentClients)
    let bindRetryDelays: [TimeInterval]

    static let maxConcurrentClients = 8
    static let maxPendingClients = 8
    static let defaultBindRetryDelays: [TimeInterval] = [0.5, 1, 2, 4, 5]
    static let failureLock = NSLock()
    static var _lastFailureDescription: String?
    static let nonceProcessLock = NSLock()
    static var didRotateNonceThisProcess = false

    init(
        socketPath: String,
        healthInterval: Int = 60,
        bindRetryDelays: [TimeInterval] = SocketListener.defaultBindRetryDelays,
        onRefresh: @escaping () -> Void,
        onShow: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onReloadConfig: @escaping () -> Void = {},
        onUpdate: @escaping () -> Void = {},
        onUpdateFont: @escaping () -> Void = {}
    ) {
        self.socketPath = socketPath
        self.healthInterval = healthInterval
        self.bindRetryDelays = bindRetryDelays
        self.onRefresh = onRefresh
        self.onShow = onShow
        self.onToggle = onToggle
        self.onSettings = onSettings
        self.onReloadConfig = onReloadConfig
        self.onUpdate = onUpdate
        self.onUpdateFont = onUpdateFont
        listenerQueue.setSpecific(key: queueKey, value: ())
        guard SpacemapCommand.validatedSocketPath(socketPath) != nil else {
            fputs("spacemap/SocketListener: refusing invalid socket path\n", stderr)
            recordFailure("invalid socket path")
            return
        }
        listenerQueue.async { self.start() }
    }

    /// True once bind/listen has exhausted its retry budget (or the listener
    /// refused a live socket). Safe to read from any queue.
    var hasFailed: Bool {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return didFail }
        return listenerQueue.sync { self.didFail }
    }

    var failureDescription: String? {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return failureReason }
        return listenerQueue.sync { self.failureReason }
    }

    /// Last permanent listener failure (also logged to stderr). Retained for a
    /// future Settings diagnostics consumer; no UI reads it yet.
    static var lastFailureDescription: String? {
        failureLock.lock()
        defer { failureLock.unlock() }
        return _lastFailureDescription
    }

    func recordFailure(_ reason: String) {
        guard !didFail else { return }
        didFail = true
        failureReason = reason
        Self.failureLock.lock()
        if Self._lastFailureDescription == nil {
            Self._lastFailureDescription = reason
        }
        Self.failureLock.unlock()
        fputs("spacemap/SocketListener: failed — \(reason)\n", stderr)
    }

    deinit {
        // Never listenerQueue.sync here: deinit may run while the queue holds
        // the last ref (or blocks on it) — sync deadlocks. Flag + cancel are
        // thread-safe; the cancel handler closes the fd.
        isStopped = true
        let src = source
        let timer = healthTimer
        listenerQueue.async { src?.cancel(); timer?.cancel() }
    }
}
