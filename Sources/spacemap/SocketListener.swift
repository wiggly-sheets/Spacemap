import Foundation
import Security

final class SocketListener {
    private let socketPath: String
    private let healthInterval: Int
    private let onRefresh: () -> Void
    private let onShow: () -> Void
    private let onToggle: () -> Void
    private let onSettings: () -> Void
    private var serverFd: Int32 = -1
    private var source: DispatchSourceRead?
    private var healthTimer: DispatchSourceTimer?
    private var isStopped = false
    private var restartScheduled = false
    private var ownsSocketFile = false
    private var bindFailureCount = 0
    private var didFail = false
    private var failureReason: String?
    private var pendingClients: [Int32] = []
    private let listenerQueue = DispatchQueue(label: "com.spacemap.socketlistener")
    private let clientQueue = DispatchQueue(label: "com.spacemap.socketlistener.client", attributes: .concurrent)
    private let queueKey = DispatchSpecificKey<Void>()
    private let clientSlots = DispatchSemaphore(value: SocketListener.maxConcurrentClients)
    private let bindRetryDelays: [TimeInterval]

    private static let maxConcurrentClients = 8
    private static let maxPendingClients = 8
    static let defaultBindRetryDelays: [TimeInterval] = [0.5, 1, 2, 4, 5]
    private static let failureLock = NSLock()
    private static var _lastFailureDescription: String?
    private static let nonceProcessLock = NSLock()
    private static var didRotateNonceThisProcess = false

    init(
        socketPath: String,
        healthInterval: Int = 60,
        bindRetryDelays: [TimeInterval] = SocketListener.defaultBindRetryDelays,
        onRefresh: @escaping () -> Void,
        onShow: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.socketPath = socketPath
        self.healthInterval = healthInterval
        self.bindRetryDelays = bindRetryDelays
        self.onRefresh = onRefresh
        self.onShow = onShow
        self.onToggle = onToggle
        self.onSettings = onSettings
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

    private func recordFailure(_ reason: String) {
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

    /// Connect probe used both for single-instance detection and to avoid
    /// unlinking a socket another process still owns. A refused connection is
    /// the only proof that an existing self-owned socket is stale; anything
    /// else is treated as live (fail closed).
    static func isSocketLive(path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFSOCK else { return false }
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return true }
        let flags = fcntl(sock, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            pathBytes.withUnsafeBytes { src in
                guard let base = src.baseAddress else { return }
                dest.copyMemory(from: UnsafeRawBufferPointer(start: base,
                                                             count: min(src.count, dest.count - 1)))
            }
        }
        let result = connect(sock, withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
        }, socklen_t(MemoryLayout<sockaddr_un>.size))
        let error = errno
        close(sock)
        if result == 0 { return true }
        if error == EINPROGRESS || error == EAGAIN { return true }
        return error != ECONNREFUSED && error != ENOENT && error != ENOTSOCK
    }

    @discardableResult
    static func sendCommand(to socketPath: String, command: UInt8) -> Bool {
        guard SpacemapCommand.validatedSocketPath(socketPath) != nil else { return false }
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            pathBytes.withUnsafeBytes { src in
                guard let base = src.baseAddress else { return }
                dest.copyMemory(from: UnsafeRawBufferPointer(start: base,
                                                                 count: min(src.count, dest.count - 1)))
            }
        }

        if connect(sock, withUnsafePointer(to: &addr) {
             $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
        }, socklen_t(MemoryLayout<sockaddr_un>.size)) == -1 {
            close(sock)
            return false
        }

        var frame = Data([command])
        if let nonce = SpacemapCommand.currentNonceHex(for: socketPath) {
            frame.append(contentsOf: (":" + nonce).utf8)
        }
        let wroteCommand: Bool = frame.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return false }
            return write(sock, base, ptr.count) == frame.count
        }
        close(sock)
        return wroteCommand
    }

    static func command(for byte: UInt8) -> SpacemapCommand {
        if byte == SpacemapCommand.show.rawValue || byte == Character("2").asciiValue {
            return .show
        }
        if byte == SpacemapCommand.settings.rawValue || byte == Character("3").asciiValue {
            return .settings
        }
        if byte == SpacemapCommand.toggle.rawValue || byte == Character("4").asciiValue {
            return .toggle
        }
        if byte == SpacemapCommand.health.rawValue || byte == Character("5").asciiValue {
            return .health
        }
        return .refresh
    }

    private func start() {
        guard !isStopped, !didFail else { return }
        guard SpacemapCommand.validatedSocketPath(socketPath) != nil else {
            recordFailure("invalid socket path")
            return
        }
        // Fail closed on a pre-existing symlink: never bind through a link
        // another user planted. Refuse; operator removes it.
        var existing = stat()
        if lstat(socketPath, &existing) == 0 {
            if (existing.st_mode & S_IFMT) == S_IFLNK {
                recordFailure("refusing symlink at socket path")
                return
            }
            guard existing.st_uid == getuid() else {
                recordFailure("refusing foreign-owned socket path")
                return
            }
            if (existing.st_mode & S_IFMT) == S_IFSOCK, Self.isSocketLive(path: socketPath) {
                // Another instance still owns it. Never steal a live socket:
                // the App-level single-instance guard normally prevents this,
                // but a direct binary launch must not unlink it either.
                recordFailure("socket is already live — refusing to steal it")
                return
            }
            unlink(socketPath)
        }

        // Nonce precedes bind: any client that connects already sees the
        // nonce the sender read, so no bare-frame window exists.
        _ = Self.ensureNonceFile(for: socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            fputs("spacemap/SocketListener: socket() failed\n", stderr)
            close(fd)
            scheduleBindRetry()
            return
        }
        // Nonblocking accept: drain() loops until EAGAIN instead of
        // blocking with no pending client.
        let listenFlags = fcntl(fd, F_GETFL, 0)
        if listenFlags >= 0 { _ = fcntl(fd, F_SETFL, listenFlags | O_NONBLOCK) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            pathBytes.withUnsafeBytes { src in
                guard let base = src.baseAddress else { return }
                dest.copyMemory(from: UnsafeRawBufferPointer(start: base,
                                                                 count: min(src.count, dest.count - 1)))
            }
        }

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            fputs("spacemap/SocketListener: bind/listen failed\n", stderr)
            close(fd)
            scheduleBindRetry()
            return
        }

        chmod(socketPath, 0o600)
        serverFd = fd
        ownsSocketFile = true
        bindFailureCount = 0
        didFail = false
        failureReason = nil
        Self.failureLock.lock()
        Self._lastFailureDescription = nil
        Self.failureLock.unlock()
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: listenerQueue)
        src.setEventHandler { [weak self] in self?.drain() }
        src.setCancelHandler { [weak self] in
            close(fd)
            self?.serverFd = -1
        }
        src.resume()
        source = src

        startHealthTimer()
    }

    private func scheduleBindRetry() {
        guard !isStopped, !didFail else { return }
        guard bindFailureCount < bindRetryDelays.count else {
            recordFailure("bind/listen failed \(bindRetryDelays.count) times — giving up")
            return
        }
        let delay = bindRetryDelays[bindFailureCount]
        bindFailureCount += 1
        fputs("spacemap/SocketListener: retrying bind/listen in \(delay)s\n", stderr)
        listenerQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.start()
        }
    }

    /// Per-bind 256-bit nonce for the programmatic send path. Same uid can
    /// read it — it stops blind path-guessers, not same-user malware.
    /// $TMPDIR perms (0700) + peer-uid check carry the cross-user case.
    /// Kept across listener restarts: yabai signals embed it at registration,
    /// so a rotation without re-registering would drop space_changed frames.
    /// Rotate the nonce once per app process, before the first listener/signal
    /// registration. Later listener rebuilds call `ensureNonceFile` and keep it.
    /// A live socket means another instance already registered yabai actions
    /// with this nonce: reuse it and never rotate, even if this process has not
    /// rotated yet (two near-simultaneous launches can both pass the guard).
    @discardableResult
    static func prepareNonceForProcess(for socketPath: String) -> String? {
        nonceProcessLock.lock()
        let alreadyRotated = didRotateNonceThisProcess
        didRotateNonceThisProcess = true
        nonceProcessLock.unlock()

        let socketIsLive = isSocketLive(path: socketPath)
        if !alreadyRotated && !socketIsLive {
            removeNonceFileIfOwned(socketPath)
        }
        return ensureNonceFile(for: socketPath)
    }

    /// Test seam for the once-per-process rotation flag.
    static func resetNonceRotationForTesting() {
        nonceProcessLock.lock()
        didRotateNonceThisProcess = false
        nonceProcessLock.unlock()
    }

    private static func removeNonceFileIfOwned(_ socketPath: String) {
        let path = socketPath + ".nonce"
        var st = stat()
        guard lstat(path, &st) == 0, st.st_uid == getuid() else { return }
        // unlink() removes a symlink itself, never its target.
        unlink(path)
    }

    @discardableResult
    static func ensureNonceFile(for socketPath: String) -> String? {
        guard SpacemapCommand.validatedSocketPath(socketPath) != nil else { return nil }
        let path = socketPath + ".nonce"
        let url = URL(fileURLWithPath: path)
        var st = stat()
        if lstat(path, &st) == 0 {
            guard st.st_uid == getuid() else {
                fputs("spacemap/SocketListener: refusing foreign-owned nonce file\n", stderr)
                return nil
            }
            if (st.st_mode & S_IFMT) == S_IFREG,
               let data = try? Data(contentsOf: url),
               data.count == 32 {
                // Re-assert permissions: an old/relaxed file must be 0600
                // before it is trusted again.
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
                SpacemapCommand.invalidateNonceCache()
                return data.map { String(format: "%02x", $0) }.joined()
            }
            // Wrong size, symlink, or other self-owned junk: remove the path
            // entry (never follow the link) before writing a fresh nonce.
            if (st.st_mode & S_IFMT) != S_IFDIR {
                unlink(path)
            }
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            fputs("spacemap/SocketListener: no entropy for nonce — programmatic send disabled\n", stderr)
            try? FileManager.default.removeItem(atPath: path)
            SpacemapCommand.invalidateNonceCache()
            return nil
        }
        do {
            try Data(bytes).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            SpacemapCommand.invalidateNonceCache()
            return bytes.map { String(format: "%02x", $0) }.joined()
        } catch {
            fputs("spacemap/SocketListener: nonce write failed\n", stderr)
            return nil
        }
    }

    /// Frame: <cmdByte> [":" <64 hex nonce>] with a lone trailing "\n"
    /// tolerated for `echo N | nc` compat. Unknown shape or bad nonce = drop.
    static func parseFrame(_ data: Data, nonce: String?) -> SpacemapCommand? {
        guard let first = data.first else { return nil }
        let rest = data.dropFirst()
        if rest.isEmpty || (rest.count == 1 && rest.first == 0x0A) {
            // Nonce configured: bare frames prove no nonce, drop them.
            guard nonce == nil else {
                fputs("spacemap/SocketListener: bare frame without nonce — dropping\n", stderr)
                return nil
            }
            return command(for: first)
        }
        guard rest.first == UInt8(ascii: ":") else { return nil }
        var hexData = rest.dropFirst()
        if hexData.last == 0x0A { hexData = hexData.dropLast() }
        let hex = String(bytes: hexData, encoding: .utf8) ?? ""
        guard let nonce, hex == nonce else {
            fputs("spacemap/SocketListener: nonce mismatch — dropping frame\n", stderr)
            return nil
        }
        return command(for: first)
    }

    /// Frame shapes from parseFrame: lone byte, byte + "\n", or
    /// byte + ":" + 64 hex nonce (67 max with trailing newline).
    private static func isCompleteFrame(_ frame: Data) -> Bool {
        guard !frame.isEmpty else { return false }
        if frame.count == 1 { return true }
        if frame.count == 2, frame[frame.index(after: frame.startIndex)] == 0x0A { return true }
        return frame.count >= 66
    }

    /// No valid frame starts this way: more waiting cannot fix it.
    private static func isInvalidPrefix(_ frame: Data) -> Bool {
        guard frame.count >= 2 else { return false }
        let second = frame[frame.index(after: frame.startIndex)]
        if second == UInt8(ascii: ":") { return false }
        if frame.count == 2, second == 0x0A { return false }
        return true
    }

    private static func currentNonceHex() -> String? {
        SpacemapCommand.currentNonceHex()
    }

    /// One readiness event can queue several connects. Drain every
    /// pending client: handling one per event strands the rest with
    /// no later event to wake them (regression guard:
    /// testStalledClientDoesNotBlockCommandsOrShutdown). Accept stays
    /// lightweight on listenerQueue; each client reads on clientQueue so
    /// grace waits never block the next accept.
    private func drain() {
        while !isStopped {
            let clientFd = Darwin.accept(serverFd, nil, nil)
            if clientFd < 0 {
                let err = errno
                if err == EINTR { continue }
                if err == EAGAIN || err == EWOULDBLOCK { break }
                fputs("spacemap/SocketListener: accept() failed: \(String(cString: strerror(err))) — restarting\n", stderr)
                scheduleRestart()
                break
            }
            enqueueClient(clientFd)
        }
    }

    /// Run on listenerQueue. Acquire a worker slot or queue the accepted fd
    /// (bounded) so a short burst is not dropped after the client's write
    /// already succeeded.
    private func enqueueClient(_ clientFd: Int32) {
        if clientSlots.wait(timeout: .now()) == .success {
            startClient(clientFd)
        } else if pendingClients.count < Self.maxPendingClients {
            pendingClients.append(clientFd)
        } else {
            fputs("spacemap/SocketListener: client backlog full — dropping connection\n", stderr)
            close(clientFd)
        }
    }

    /// Caller holds one `clientSlots` permit; the worker releases it.
    private func startClient(_ clientFd: Int32) {
        let slots = clientSlots
        clientQueue.async { [weak self] in
            defer {
                slots.signal()
                if let self { self.listenerQueue.async { self.drainPendingClients() } }
            }
            guard let self else { close(clientFd); return }
            self.handleClient(clientFd)
        }
    }

    /// Run on listenerQueue when a worker frees a slot.
    private func drainPendingClients() {
        while !isStopped, !pendingClients.isEmpty,
              clientSlots.wait(timeout: .now()) == .success {
            startClient(pendingClients.removeFirst())
        }
    }

    private func handleClient(_ clientFd: Int32) {
        defer { close(clientFd) }

        // Cross-user connections share nothing here: same uid or drop.
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(clientFd, &uid, &gid) == 0, uid == getuid() else {
            fputs("spacemap/SocketListener: foreign-uid connect — dropping\n", stderr)
            return
        }

        // Client fd must not block: a connected-but-silent peer would
        // stall the whole listener queue (regression guard:
        // testStalledClientDoesNotBlockCommandsOrShutdown).
        let flags = fcntl(clientFd, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(clientFd, F_SETFL, flags | O_NONBLOCK) }
        // One write() can arrive split: accumulate until a complete frame,
        // a hard invalid shape, the cap, or a short deadline. A silent peer
        // waits in poll() on this worker only — listenerQueue keeps
        // draining, stop() never joins workers.
        var frame = Data()
        frame.reserveCapacity(96)
        var buf = [UInt8](repeating: 0, count: 96)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        while frame.count < buf.count {
            let n = read(clientFd, &buf, buf.count - frame.count)
            if n > 0 {
                frame.append(contentsOf: buf.prefix(n))
                if Self.isCompleteFrame(frame) { break }
                continue
            }
            if n == 0 { break }
            let err = errno
            if err == EINTR { continue }
            guard err == EAGAIN || err == EWOULDBLOCK else { break }
            // Empty frame with EAGAIN means the peer connected but has
            // not written yet — not proof of a silent peer. Wait for
            // readability bounded by the deadline; a truly silent peer
            // costs one worker in poll(), nothing else.
            if Self.isCompleteFrame(frame) || Self.isInvalidPrefix(frame) { break }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { break }
            var pfd = pollfd(fd: clientFd, events: Int16(POLLIN), revents: 0)
            guard Darwin.poll(&pfd, 1, Int32(min(remaining * 1000, 200))) > 0 else { break }
        }
        let nonce = SpacemapCommand.currentNonceHex(for: socketPath)
        guard !frame.isEmpty, let cmd = Self.parseFrame(frame, nonce: nonce) else { return }

        // Inline delivery on this worker, never main.async: a waiter with
        // no pumped main runloop (swift test, CLI) still observes the
        // command (regression guard:
        // testStalledClientDoesNotBlockCommandsOrShutdown). UI callers
        // hop to the main queue themselves.
        switch cmd {
        case .show:
            self.onShow()
        case .settings:
            self.onSettings()
        case .toggle:
            self.onToggle()
        case .refresh:
            self.onRefresh()
        case .health:
            break
        }
    }

    private func scheduleRestart() {
        guard !isStopped, !restartScheduled else { return }
        restartScheduled = true
        tearDownSocket()
        fputs("spacemap/SocketListener: restarting in 0.5s\n", stderr)
        listenerQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.restartScheduled = false
            self?.start()
        }
    }

    private func tearDownSocket() {
        healthTimer?.cancel(); healthTimer = nil
        source?.cancel(); source = nil
        for fd in pendingClients { close(fd) }
        pendingClients.removeAll()
        // Only remove a socket this listener actually bound. A refused
        // second listener must never unlink the live instance's socket.
        if ownsSocketFile {
            ownsSocketFile = false
            unlinkIfOwned(socketPath)
        }
    }

    /// unlink() never follows symlinks; uid gate stops foreign-planted link removal.
    private func unlinkIfOwned(_ path: String) {
        var st = stat()
        guard lstat(path, &st) == 0 else { return }
        guard st.st_uid == getuid() else { return }
        unlink(path)
    }

    private func startHealthTimer() {
        let timer = DispatchSource.makeTimerSource(queue: listenerQueue)
        timer.schedule(deadline: .now() + .seconds(healthInterval), repeating: .seconds(healthInterval))
        timer.setEventHandler { [weak self] in self?.checkHealth() }
        timer.resume()
        healthTimer = timer
    }

    private func checkHealth() {
        let fdValid = serverFd >= 0 && fcntl(serverFd, F_GETFD) != -1
        let fileExists = FileManager.default.fileExists(atPath: socketPath)
        var ownedBySelf = false
        var statBuf = stat()
        if lstat(socketPath, &statBuf) == 0 {
            ownedBySelf = statBuf.st_uid == getuid() && (statBuf.st_mode & S_IFMT) == S_IFSOCK
        }
        guard fdValid && fileExists && ownedBySelf else {
            fputs("spacemap/SocketListener: health check failed (fdValid=\(fdValid) fileExists=\(fileExists) ownedBySelf=\(ownedBySelf)) — restarting\n", stderr)
            scheduleRestart()
            return
        }
    }

    func stop() {
        // Keep the nonce file: yabai signal actions embed it at registration
        // and stop() is also used to rebuild the listener at runtime. Removing
        // it here would strand those actions until the next re-registration.
        let work = {
            self.isStopped = true
            self.tearDownSocket()
        }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            listenerQueue.sync(execute: work)
        }
        SpacemapCommand.invalidateNonceCache()
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
