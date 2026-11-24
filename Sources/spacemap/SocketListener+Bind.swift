import Foundation
import Security

extension SocketListener {
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
    func start() {
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

    func scheduleBindRetry() {
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
    func scheduleRestart() {
        guard !isStopped, !restartScheduled else { return }
        restartScheduled = true
        tearDownSocket()
        fputs("spacemap/SocketListener: restarting in 0.5s\n", stderr)
        listenerQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.restartScheduled = false
            self?.start()
        }
    }

    func tearDownSocket() {
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
    func unlinkIfOwned(_ path: String) {
        var st = stat()
        guard lstat(path, &st) == 0 else { return }
        guard st.st_uid == getuid() else { return }
        unlink(path)
    }

    func startHealthTimer() {
        let timer = DispatchSource.makeTimerSource(queue: listenerQueue)
        timer.schedule(deadline: .now() + .seconds(healthInterval), repeating: .seconds(healthInterval))
        timer.setEventHandler { [weak self] in self?.checkHealth() }
        timer.resume()
        healthTimer = timer
    }

    func checkHealth() {
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
}
