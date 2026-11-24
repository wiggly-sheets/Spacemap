import Foundation
import Security

extension SocketListener {
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

    static func removeNonceFileIfOwned(_ socketPath: String) {
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
}
