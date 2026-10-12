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
    private let listenerQueue = DispatchQueue(label: "com.spacemap.socketlistener")
    private let clientQueue = DispatchQueue(label: "com.spacemap.socketlistener.client", attributes: .concurrent)
    private let queueKey = DispatchSpecificKey<Void>()

    init(socketPath: String, healthInterval: Int = 60, onRefresh: @escaping () -> Void, onShow: @escaping () -> Void, onToggle: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.socketPath = socketPath
        self.healthInterval = healthInterval
        self.onRefresh = onRefresh
        self.onShow = onShow
        self.onToggle = onToggle
        self.onSettings = onSettings
        listenerQueue.setSpecific(key: queueKey, value: ())
        guard SpacemapCommand.validatedSocketPath(socketPath) != nil else {
            fputs("spacemap/SocketListener: refusing invalid socket path\n", stderr)
            return
        }
        listenerQueue.async { self.start() }
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
        guard !isStopped else { return }
        guard SpacemapCommand.validatedSocketPath(socketPath) != nil else {
            fputs("spacemap/SocketListener: refusing invalid socket path\n", stderr)
            return
        }
        // Fail closed on a pre-existing symlink: never bind through a link
        // another user planted. Refuse; operator removes it.
        var existing = stat()
        if lstat(socketPath, &existing) == 0 {
            if (existing.st_mode & S_IFMT) == S_IFLNK {
                fputs("spacemap/SocketListener: refusing symlink at socket path\n", stderr)
                return
            }
            guard existing.st_uid == getuid() else {
                fputs("spacemap/SocketListener: refusing foreign-owned socket path\n", stderr)
                return
            }
            unlink(socketPath)
        }

        // Nonce precedes bind: any client that connects already sees the
        // nonce the sender read, so no bare-frame window exists.
        rotateNonceFile()

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            fputs("spacemap/SocketListener: socket() failed\n", stderr)
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
            return
        }

        chmod(socketPath, 0o600)
        serverFd = fd
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

    /// Per-bind 256-bit nonce for the programmatic send path. Same uid can
    /// read it — it stops blind path-guessers, not same-user malware.
    /// $TMPDIR perms (0700) + peer-uid check carry the cross-user case.
    /// Kept across restarts: yabai signals embed it at registration, so a
    /// rotation without re-registering would drop space_changed frames.
    private func rotateNonceFile() {
        let path = socketPath + ".nonce"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           data.count == 32 { return }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            fputs("spacemap/SocketListener: no entropy for nonce — programmatic send disabled\n", stderr)
            try? FileManager.default.removeItem(atPath: socketPath + ".nonce")
            return
        }
        let url = URL(fileURLWithPath: socketPath + ".nonce")
        do {
            try Data(bytes).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            fputs("spacemap/SocketListener: nonce write failed\n", stderr)
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
            let acceptedFd = clientFd
            clientQueue.async { [weak self] in
                guard let self else { close(acceptedFd); return }
                self.handleClient(acceptedFd)
            }
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
        // costs only the grace retries (~20ms).
        var frame = Data()
        frame.reserveCapacity(96)
        var buf = [UInt8](repeating: 0, count: 96)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        var grace = 0
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
            // not written yet — not proof of a silent peer. Retry within
            // the deadline; a truly silent peer only costs ~20ms.
            if Self.isCompleteFrame(frame) || Self.isInvalidPrefix(frame) { break }
            grace += 1
            if grace > 2 || ProcessInfo.processInfo.systemUptime >= deadline { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        let nonce = SpacemapCommand.currentNonceHex(for: socketPath)
        guard !frame.isEmpty, let cmd = Self.parseFrame(frame, nonce: nonce) else { return }

        DispatchQueue.main.async {
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
        unlinkIfOwned(socketPath)
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
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            isStopped = true
            tearDownSocket()
        } else {
            listenerQueue.sync {
                self.isStopped = true
                self.tearDownSocket()
            }
        }
        unlinkIfOwned(socketPath + ".nonce")
    }

    deinit { stop() }
}
