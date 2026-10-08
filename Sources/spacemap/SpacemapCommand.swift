import Foundation

enum SpacemapCommand: UInt8, Equatable {
    case refresh = 1
    case show = 2
    case settings = 3
    case toggle = 4
    case health = 5

    /// Per-user temp dir ($TMPDIR, mode 0700), not the shared /tmp stencil.
    /// Predictable /tmp paths let another user pre-create the socket.
    static var socketPath: String {
        (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("spacemap_\(NSUserName()).socket")
    }

    static var noncePath: String { noncePath(for: socketPath) }

    static func noncePath(for path: String) -> String { path + ".nonce" }

    /// Allowlist for paths interpolated into yabai signal shell actions.
    /// Anything outside fails closed (nil) — never quote-and-hope.
    static func validatedSocketPath(_ path: String) -> String? {
        guard !path.isEmpty, path.utf8.count < 256 else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./-")
        guard path.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
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
    static func currentNonceHex() -> String? {
        currentNonceHex(for: socketPath)
    }

    static func currentNonceHex(for path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: noncePath(for: path))),
              data.count == 32 else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    enum SendError: Error, CustomStringConvertible {
        case socketCreateFailed
        case connectFailed
        case writeFailed
        case invalidSocketPath

        var description: String {
            switch self {
            case .socketCreateFailed: return "Failed to create socket"
            case .connectFailed: return "Failed to connect to spacemap socket"
            case .writeFailed: return "Failed to write command to socket"
            case .invalidSocketPath: return "Refusing to connect: socket path outside allowlist"
            }
        }
    }

    func send() throws {
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

        var frame = Data([rawValue])
        if let nonce = Self.currentNonceHex() {
            frame.append(contentsOf: (":" + nonce).utf8)
        }
        let wroteCommand = frame.withUnsafeBytes { write(sock, $0.baseAddress!, $0.count) } == frame.count
        close(sock)
        guard wroteCommand else { throw SendError.writeFailed }
    }
}
