import Foundation
import Security

extension SocketListener {
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
        if byte == SpacemapCommand.show.socketByte || byte == Character("2").asciiValue {
            return .show
        }
        if byte == SpacemapCommand.settings.socketByte || byte == Character("3").asciiValue {
            return .settings
        }
        if byte == SpacemapCommand.toggle.socketByte || byte == Character("4").asciiValue {
            return .toggle
        }
        if byte == SpacemapCommand.health.socketByte || byte == Character("5").asciiValue {
            return .health
        }
        if byte == SpacemapCommand.reloadConfig.socketByte || byte == Character("6").asciiValue {
            return .reloadConfig
        }
        if byte == SpacemapCommand.update.socketByte || byte == Character("7").asciiValue {
            return .update
        }
        if byte == SpacemapCommand.updateFont.socketByte || byte == Character("8").asciiValue {
            return .updateFont
        }
        return .refresh
    }

    /// One readiness event can queue several connects. Drain every
    /// pending client: handling one per event strands the rest with
    /// no later event to wake them (regression guard:
    /// testStalledClientDoesNotBlockCommandsOrShutdown). Accept stays
    /// lightweight on listenerQueue; each client reads on clientQueue so
    /// grace waits never block the next accept.
    func drain() {
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
    func enqueueClient(_ clientFd: Int32) {
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
    func startClient(_ clientFd: Int32) {
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
    func drainPendingClients() {
        while !isStopped, !pendingClients.isEmpty,
              clientSlots.wait(timeout: .now()) == .success {
            startClient(pendingClients.removeFirst())
        }
    }

    func handleClient(_ clientFd: Int32) {
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
        case .reloadConfig:
            self.onReloadConfig()
        case .update:
            self.onUpdate()
        case .updateFont:
            self.onUpdateFont()
        case .health:
            break
        case .showMenu, .version, .help, .config, .printConfig, .status, .restarting:
            // No socket byte, so command(for:) never returns them.
            break
        }
    }
}
