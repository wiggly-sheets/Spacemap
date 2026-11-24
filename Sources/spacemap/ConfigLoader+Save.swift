import Foundation

extension ConfigLoader {
    static func save(_ config: SpacemapConfig, to path: String) {
        _ = saveReportingResult(config, to: path)
    }

    /// Additive counterpart to `save`: returns whether the file was written.
    @discardableResult
    static func saveReportingResult(_ config: SpacemapConfig, to path: String) -> Bool {
        ioLock.lock()
        defer { ioLock.unlock() }
        return saveUnlocked(config, to: path)
    }

    static func saveUnlocked(_ config: SpacemapConfig, to path: String) -> Bool {
        // EEXIST + O_NOFOLLOW: never write through a planted link or dir.
        guard !isSymlink(at: path) else {
            NSLog("spacemap/ConfigLoader: refusing to write through symlink at \(path)")
            return false
        }
        let dir = (path as NSString).deletingLastPathComponent
        secureDirectory(at: dir)
        backupConfig(at: path)
        let content = tomlConfigString(from: config, includeHeaderComments: true)
        return secureWrite(content, to: path)
    }

    /// Read-only text access with the same guards as `load`, but it never
    /// creates or repairs: presets and exports are user files, not the config.
    static func readText(at path: String) -> String? {
        guard !isSymlink(at: path),
              let read = nofollowData(at: path, limit: maxConfigBytes),
              !read.exceeded,
              var text = String(data: read.data, encoding: .utf8) else { return nil }
        if text.hasPrefix("\u{FEFF}") { text = String(text.dropFirst()) }
        return text
    }

    /// Atomic read-modify-write of the on-disk config. Prefer this over a
    /// separate `load` + `save` pair so concurrent writers cannot drop each
    /// other's changes.
    @discardableResult
    static func update(
        at path: String,
        silentMode: Bool,
        _ mutate: (inout SpacemapConfig) -> Void
    ) -> Bool {
        ioLock.lock()
        defer { ioLock.unlock() }
        // One write only: a repair write here would immediately be followed by
        // the post-mutation save, rotating the backup twice.
        let result = loadUnlocked(from: path, silentMode: silentMode, repair: false)
        guard result.status != .parseFailed else { return false }
        var config = result.config
        mutate(&config)
        return saveUnlocked(config, to: path)
    }

    static func createDefaultConfigFile(at path: String) {
        ioLock.lock()
        defer { ioLock.unlock() }
        _ = createDefaultConfigFileUnlocked(at: path)
    }

    @discardableResult
    static func createDefaultConfigFileReportingResult(at path: String) -> Bool {
        ioLock.lock()
        defer { ioLock.unlock() }
        return createDefaultConfigFileUnlocked(at: path)
    }

    static func createDefaultConfigFileUnlocked(at path: String) -> Bool {
        guard !isSymlink(at: path) else {
            NSLog("spacemap/ConfigLoader: refusing to write through symlink at \(path)")
            return false
        }
        secureDirectory(at: (path as NSString).deletingLastPathComponent)
        backupConfig(at: path)
        let content = tomlConfigString(from: .default, includeHeaderComments: true)
        let written = secureWrite(content, to: path)
        if written {
            NSLog("spacemap: default config created at \(path)")
        }
        return written
    }

    /// Config dir 0700, files 0600. XDG config holds hotkeys/behavior — no
    /// reason group/other ever reads it.
    /// Temp file born 0600, then renamed: no world-readable window
    /// between create and chmod. Rename over symlink replaces link itself.
    @discardableResult
    static func secureWrite(_ content: String, to path: String) -> Bool {
        guard let data = content.data(using: .utf8) else { return false }
        let dir = (path as NSString).deletingLastPathComponent
        let tmpPath = (dir as NSString).appendingPathComponent(
            ".spacemap.\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString).tmp")
        let fd = open(tmpPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else {
            NSLog("spacemap: failed to save config to \(path): cannot create temp file")
            return false
        }
        defer { close(fd) }
        let bytes = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        // write() on blocking fd writes all or fails; short write = failure.
        guard bytes == data.count else {
            unlink(tmpPath)
            NSLog("spacemap: failed to save config to \(path): short write")
            return false
        }
        _ = fchmod(fd, mode_t(0o600))
        guard rename(tmpPath, path) == 0 else {
            unlink(tmpPath)
            NSLog("spacemap: failed to save config to \(path): rename failed")
            return false
        }
        return true
    }

    static func secureDirectory(at path: String) {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        } catch {
            NSLog("spacemap: failed to secure config dir at \(path): \(error)")
        }
    }

    static func backupConfig(at path: String) {
        // Pin source with O_NOFOLLOW fd: link swapped in after isSymlink
        // check fails open() instead of being followed (TOCTOU).
        guard !isSymlink(at: path) else { return }
        let srcFd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard srcFd >= 0 else { return }
        defer { close(srcFd) }
        var srcStat = stat()
        guard fstat(srcFd, &srcStat) == 0, (srcStat.st_mode & S_IFMT) == S_IFREG else { return }
        let backupPath = path + ".bak"
        rotateBackup(at: backupPath)
        // Oversized input is not worth copying, but it must not be destroyed
        // by the write that follows: move it aside instead. Cap the read as
        // well so a lying/growing file cannot make the backup unbounded.
        if srcStat.st_size > off_t(maxConfigBytes) {
            moveAside(path: path, backupPath: backupPath, srcFd: srcFd)
            return
        }
        let data = FileHandle(fileDescriptor: srcFd, closeOnDealloc: false)
            .readData(ofLength: maxConfigBytes + 1)
        guard data.count <= maxConfigBytes else {
            moveAside(path: path, backupPath: backupPath, srcFd: srcFd)
            return
        }
        // O_EXCL|O_NOFOLLOW: fail closed if link planted after rotation.
        let dstFd = open(backupPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard dstFd >= 0 else { return }
        defer { close(dstFd) }
        let written = data.withUnsafeBytes { write(dstFd, $0.baseAddress, $0.count) }
        guard written == data.count else {
            unlink(backupPath)
            return
        }
        _ = fchmod(dstFd, mode_t(0o600))
    }

    /// Rotate `path.bak` to `path.bak.1`, dropping whatever was there.
    static func rotateBackup(at backupPath: String) {
        let rotatedPath = backupPath + ".1"
        // unlink() never follows: removes planted link itself, not target.
        unlink(rotatedPath)
        var backupStat = stat()
        if lstat(backupPath, &backupStat) == 0 {
            if (backupStat.st_mode & S_IFMT) == S_IFLNK || (backupStat.st_mode & S_IFMT) != S_IFREG {
                unlink(backupPath)
            } else if rename(backupPath, rotatedPath) == 0 {
                // rename moves link itself; lstat gate stops chmod through link.
                var rotStat = stat()
                if lstat(rotatedPath, &rotStat) == 0, (rotStat.st_mode & S_IFMT) == S_IFREG {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: rotatedPath)
                }
            }
        }
    }

    /// Move the pinned regular file from `path` to the backup slot without
    /// reading it. `fchmod` on the still-open fd avoids a path-based chmod race.
    static func moveAside(path: String, backupPath: String, srcFd: Int32) {
        guard rename(path, backupPath) == 0 else { return }
        _ = fchmod(srcFd, mode_t(0o600))
    }
}
