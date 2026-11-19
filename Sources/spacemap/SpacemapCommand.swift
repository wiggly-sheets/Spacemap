import Foundation

/// Every action argv can name, plus every command that can arrive over the
/// single-instance socket. One enum keeps the flag table, the wire protocol,
/// and the deep-link handoff from drifting apart.
enum SpacemapCommand: Equatable {
    // Socket protocol commands.
    case refresh
    case show
    case settings
    case toggle
    case health
    case reloadConfig
    case update
    case updateFont
    // App action delivered only by deep link.
    case showMenu
    // CLI-only actions: they print or act in the CLI process and exit.
    case version
    case help
    case config
    case printConfig
    case status
    // Launch marker read from argv by the running app.
    case restarting

    /// Byte on the single-instance socket; nil for commands that never travel
    /// over it.
    var socketByte: UInt8? {
        switch self {
        case .refresh: return 1
        case .show: return 2
        case .settings: return 3
        case .toggle: return 4
        case .health: return 5
        case .reloadConfig: return 6
        case .update: return 7
        case .updateFont: return 8
        case .showMenu, .version, .help, .config, .printConfig, .status, .restarting:
            return nil
        }
    }

    /// Per-user temp dir ($TMPDIR, mode 0700), not the shared /tmp stencil.
    /// Predictable /tmp paths let another user pre-create the socket.
    static var socketPath: String {
        (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("spacemap_\(sanitizedUserName()).socket")
    }

    private static func sanitizedUserName() -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        let sanitized = NSUserName().unicodeScalars.filter({ allowed.contains($0) }).map(String.init).joined()
        return sanitized.isEmpty ? String(getuid()) : sanitized
    }

    static var noncePath: String { noncePath(for: socketPath) }

    static func noncePath(for path: String) -> String { path + ".nonce" }

    /// Allowlist for paths interpolated into yabai signal shell actions.
    /// Anything outside fails closed (nil) — never quote-and-hope.
    /// Confined to the per-user temp dir, capped to 103 bytes (sun_path is
    /// 104 incl. NUL — longer would silently truncate at bind/connect).
    static func validatedSocketPath(_ path: String) -> String? {
        guard !path.isEmpty, path.utf8.count <= 103 else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./-")
        guard path.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard !path.contains("..") else { return nil }
        guard path.hasPrefix(NSTemporaryDirectory()) else { return nil }
        return path
    }

    /// Single-quote for sh. Quote char is outside the allowlist, so the
    /// replacement below never fires on validated input — belt and braces.
    static func shellQuoted(_ path: String) -> String? {
        guard let valid = validatedSocketPath(path) else { return nil }
        return "'" + valid.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Hex nonce written by the listener beside the socket (mode 0600).
    /// Same-uid processes can read it; it stops blind writes from processes
    /// that only guess the path (yabai actions embed it at registration).
    /// Cached in memory: senders read it per command, disk only on miss or
    /// after invalidateNonceCache (rotate/stop).
    private static let nonceLock = NSLock()
    private static var cachedNonceHex: String?
    private static var cachedNoncePath: String?

    static func currentNonceHex() -> String? {
        currentNonceHex(for: socketPath)
    }

    static func currentNonceHex(for path: String) -> String? {
        let nonceFile = noncePath(for: path)
        nonceLock.lock()
        let cached = (cachedNonceHex != nil && cachedNoncePath == nonceFile) ? cachedNonceHex : nil
        nonceLock.unlock()
        if let cached { return cached }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: nonceFile)),
              data.count == 32 else { return nil }
        let hex = data.map { String(format: "%02x", $0) }.joined()
        nonceLock.lock()
        cachedNonceHex = hex
        cachedNoncePath = nonceFile
        nonceLock.unlock()
        return hex
    }

    static func invalidateNonceCache() {
        nonceLock.lock()
        defer { nonceLock.unlock() }
        cachedNonceHex = nil
        cachedNoncePath = nil
    }

    enum SendError: Error, CustomStringConvertible {
        case socketCreateFailed
        case connectFailed
        case writeFailed
        case invalidSocketPath
        case notSendable

        var description: String {
            switch self {
            case .socketCreateFailed: return "Failed to create socket"
            case .connectFailed: return "Failed to connect to spacemap socket"
            case .writeFailed: return "Failed to write command to socket"
            case .invalidSocketPath: return "Refusing to connect: socket path outside allowlist"
            case .notSendable: return "Command cannot be sent over the socket"
            }
        }
    }

    func send() throws {
        guard let byte = socketByte else { throw SendError.notSendable }
        guard Self.validatedSocketPath(Self.socketPath) != nil else {
            throw SendError.invalidSocketPath
        }
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { throw SendError.socketCreateFailed }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Self.socketPath.utf8CString
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
            throw SendError.connectFailed
        }

        var frame = Data([byte])
        if let nonce = Self.currentNonceHex() {
            frame.append(contentsOf: (":" + nonce).utf8)
        }
        let wroteCommand: Bool = frame.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return false }
            return write(sock, base, ptr.count) == frame.count
        }
        close(sock)
        guard wroteCommand else { throw SendError.writeFailed }
    }
}
