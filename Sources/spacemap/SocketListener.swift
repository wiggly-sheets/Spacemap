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
    private let queueKey = DispatchSpecificKey<Void>()

    init(socketPath: String, healthInterval: Int = 60, onRefresh: @escaping () -> Void, onShow: @escaping () -> Void, onToggle: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.socketPath = socketPath
        self.healthInterval = healthInterval
        self.onRefresh = onRefresh
        self.onShow = onShow
        self.onToggle = onToggle
        self.onSettings = onSettings
        listenerQueue.setSpecific(key: queueKey, value: ())
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
                dest.copyMemory(from: UnsafeRawBufferPointer(start: src.baseAddress,
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
        let wroteCommand = frame.withUnsafeBytes { write(sock, $0.baseAddress!, $0.count) } == frame.count
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
        // Fail closed on a pre-existing symlink: never bind through a link
        // another user planted. Unlink then bind fresh so we own the node.
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: socketPath)) != nil {
            fputs("spacemap/SocketListener: refusing symlink at socket path — removing\n", stderr)
        }
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            fputs("spacemap/SocketListener: socket() failed\n", stderr)
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            pathBytes.withUnsafeBytes { src in
                dest.copyMemory(from: UnsafeRawBufferPointer(start: src.baseAddress,
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
        rotateNonceFile()
        serverFd = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: listenerQueue)
        src.setEventHandler { [weak self] in self?.accept() }
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
    private func rotateNonceFile() {
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
        if rest.isEmpty { return command(for: first) }
        if rest.count == 1, rest.first == 0x0A { return command(for: first) }
        guard rest.first == UInt8(ascii: ":") else { return nil }
        let hex = String(bytes: rest.dropFirst(), encoding: .utf8) ?? ""
        guard let nonce, hex == nonce else {
            fputs("spacemap/SocketListener: nonce mismatch — dropping frame\n", stderr)
            return nil
        }
        return command(for: first)
    }

    private static func currentNonceHex() -> String? {
        SpacemapCommand.currentNonceHex()
    }

    private func accept() {
        let clientFd = Darwin.accept(serverFd, nil, nil)
        guard clientFd >= 0 else {
            let err = errno
            if err == EINTR || err == EAGAIN { return }
            fputs("spacemap/SocketListener: accept() failed: \(String(cString: strerror(err))) — restarting\n", stderr)
            scheduleRestart()
            return
        }
        defer { close(clientFd) }

        // Cross-user connections share nothing here: same uid or drop.
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(clientFd, &uid, &gid) == 0, uid == getuid() else {
            fputs("spacemap/SocketListener: foreign-uid connect — dropping\n", stderr)
            return
        }

        var buf = [UInt8](repeating: 0, count: 96)
        let bytesRead: Int
        do {
            // Client fd must not block: a connected-but-silent peer would
            // stall the whole listener queue (regression guard:
            // testStalledClientDoesNotBlockCommandsOrShutdown).
            let flags = fcntl(clientFd, F_GETFL, 0)
            if flags >= 0 { _ = fcntl(clientFd, F_SETFL, flags | O_NONBLOCK) }
            bytesRead = read(clientFd, &buf, buf.count)
        }
        let nonce = SpacemapCommand.currentNonceHex(for: socketPath)
        guard bytesRead > 0, let cmd = Self.parseFrame(Data(buf.prefix(bytesRead)), nonce: nonce) else { return }

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
        unlink(socketPath)
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
        if stat(socketPath, &statBuf) == 0 {
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
    }

    deinit { stop() }
}
