import Foundation
import Security

extension SocketListener {
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
    static func isCompleteFrame(_ frame: Data) -> Bool {
        guard !frame.isEmpty else { return false }
        if frame.count == 1 { return true }
        if frame.count == 2, frame[frame.index(after: frame.startIndex)] == 0x0A { return true }
        return frame.count >= 66
    }

    /// No valid frame starts this way: more waiting cannot fix it.
    static func isInvalidPrefix(_ frame: Data) -> Bool {
        guard frame.count >= 2 else { return false }
        let second = frame[frame.index(after: frame.startIndex)]
        if second == UInt8(ascii: ":") { return false }
        if frame.count == 2, second == 0x0A { return false }
        return true
    }

    static func currentNonceHex() -> String? {
        SpacemapCommand.currentNonceHex()
    }
}
