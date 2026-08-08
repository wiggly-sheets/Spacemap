import Foundation

enum SpacemapCommand: UInt8, Equatable {
    case refresh = 1
    case show = 2
    case settings = 3
    case toggle = 4
    case health = 5

    static let socketPath = "/tmp/spacemap_\(NSUserName()).socket"

    enum SendError: Error, CustomStringConvertible {
        case socketCreateFailed
        case connectFailed
        case writeFailed

        var description: String {
            switch self {
            case .socketCreateFailed: return "Failed to create socket"
            case .connectFailed: return "Failed to connect to spacemap socket"
            case .writeFailed: return "Failed to write command to socket"
            }
        }
    }

    func send() throws {
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

        var byte = rawValue
        let wroteCommand = write(sock, &byte, 1) == 1
        close(sock)
        guard wroteCommand else { throw SendError.writeFailed }
    }
}