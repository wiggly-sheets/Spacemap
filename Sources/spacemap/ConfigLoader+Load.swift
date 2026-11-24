import Foundation

extension ConfigLoader {
    static func isSymlink(at path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    static func load(from path: String, silentMode: Bool) -> (config: SpacemapConfig, needsRepair: Bool) {
        let result = loadReportingResult(from: path, silentMode: silentMode)
        return (result.config, result.needsRepair)
    }

    /// Additive counterpart to `load`: same behavior plus a status explaining
    /// unreadable / oversized / parse-failed files.
    static func loadReportingResult(
        from path: String,
        silentMode: Bool
    ) -> (config: SpacemapConfig, needsRepair: Bool, status: ConfigLoadStatus) {
        ioLock.lock()
        defer { ioLock.unlock() }
        return loadUnlocked(from: path, silentMode: silentMode)
    }

    static func loadUnlocked(
        from path: String,
        silentMode: Bool,
        repair: Bool = true
    ) -> (config: SpacemapConfig, needsRepair: Bool, status: ConfigLoadStatus) {
        if isSymlink(at: path) {
            NSLog("spacemap/ConfigLoader: refusing to read symlinked config at \(path)")
            return (.default, true, .unreadable)
        }
        // O_NOFOLLOW open: a link swapped in after the check above still
        // fails here instead of being followed (TOCTOU). Nil also covers
        // missing/unreadable files.
        guard let read = nofollowData(at: path, limit: maxConfigBytes) else {
            if !silentMode { NSLog("spacemap/ConfigLoader: failed to read config at \(path)") }
            let wroteDefault = createDefaultConfigFileUnlocked(at: path)
            return (.default, true, wroteDefault ? .createdDefault : .unreadable)
        }
        // Stop at the ceiling instead of slurping a huge file into memory.
        guard !read.exceeded else {
            NSLog("spacemap/ConfigLoader: config at \(path) exceeds size ceilings — using defaults")
            return (.default, true, .oversized)
        }
        guard var raw = String(data: read.data, encoding: .utf8) else {
            if !silentMode { NSLog("spacemap/ConfigLoader: config at \(path) is not UTF-8") }
            _ = createDefaultConfigFileUnlocked(at: path)
            return (.default, true, .unreadable)
        }
        if raw.hasPrefix("\u{FEFF}") { raw = String(raw.dropFirst()) }
        let contents = raw
        if !silentMode { NSLog("spacemap/ConfigLoader: successfully read config from \(path)") }

        // Fail closed on absurd single lines even though the byte ceiling passed.
        guard contents.split(separator: "\n", omittingEmptySubsequences: false)
            .allSatisfy({ $0.utf8.count <= maxLineBytes }) else {
            NSLog("spacemap/ConfigLoader: config at \(path) has an oversized line — using defaults")
            return (.default, true, .oversized)
        }

        let parsed: (config: SpacemapConfig, needsRepair: Bool)
        do {
            parsed = try TOMLParser.parse(contents)
        } catch {
            // Never overwrite a file we could not understand: the user can fix
            // a broken file, but cannot recover defaults written over it. Fall
            // back for this session and leave the bytes untouched.
            logParseFailureOnce(at: path, error.localizedDescription)
            return (.default, true, .parseFailed)
        }
        // A later relapse should log again.
        loggedParseFailures.remove(path)
        let (config, invalidLabels) = sanitizeLabels(parsed.config)
        let needsRepair = parsed.needsRepair || invalidLabels
        guard needsRepair else {
            return (config, false, .loaded)
        }
        // Persist the resolved model, not the raw input (e.g. `cols =
        // 9223372036854775807`): writing raw input makes every load rediscover
        // the same repair and rewrite the file forever. `update` passes
        // `repair: false` so it writes once, after applying its mutation.
        if repair {
            _ = saveUnlocked(config, to: path)
        }
        return (config, true, .repaired)
    }

    /// O_NOFOLLOW read of a regular file, capped at `limit + 1` bytes so the
    /// size check is decided on one extra byte rather than a full slurp.
    /// Returns nil for symlinks (even ones planted after `isSymlink`),
    /// directories, and read failures.
    static func nofollowData(at path: String, limit: Int) -> (data: Data, exceeded: Bool)? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var statBuf = stat()
        guard fstat(fd, &statBuf) == 0, (statBuf.st_mode & S_IFMT) == S_IFREG else { return nil }
        var data = Data()
        data.reserveCapacity(min(Int(statBuf.st_size), limit + 1))
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while data.count <= limit {
            let remaining = limit + 1 - data.count
            let chunk = min(buffer.count, max(remaining, 1))
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, chunk) }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if count == 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return (data, data.count > limit)
    }

    static func logParseFailureOnce(at path: String, _ reason: String) {
        guard loggedParseFailures.insert(path).inserted else { return }
        NSLog("spacemap/ConfigLoader: parse failed at \(path) (\(reason)) — using defaults")
    }
}
