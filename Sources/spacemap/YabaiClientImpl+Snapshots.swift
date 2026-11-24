import Foundation
import AppKit

extension YabaiClientImpl {
    func querySpaces() throws -> [YabaiSpace] {
        guard isYabaiRunning() else { return [] }
        return try cachedSpaces()
    }

    func queryDisplays() throws -> [YabaiDisplay] {
        guard isYabaiRunning() else { return [] }
        return try queryDisplaysRaw()
    }

    func queryWindows() throws -> [YabaiWindow] {
        guard isYabaiRunning() else { return [] }
        return try cachedWindows()
    }

    func windowSpaceSignature() throws -> String {
        guard isYabaiRunning() else { return "" }
        return try cachedWindows()
            .sorted { $0.id < $1.id }
            .map { "\($0.id):\($0.space)" }
            .joined(separator: ",")
    }

    func querySpacesRaw(timeout: TimeInterval? = nil) throws -> [YabaiSpace] {
        guard yabaiIsExecutable else {
            throw YabaiError.commandFailed(arguments: ["-m", "query", "--spaces"], status: -1, message: "yabai not found")
        }
        let output = try shell([yabaiPath, "-m", "query", "--spaces"], timeout: timeout)
        return try decodeTolerant(YabaiSpace.self, from: output, label: "space")
    }

    func queryDisplaysRaw() throws -> [YabaiDisplay] {
        guard yabaiIsExecutable else {
            throw YabaiError.commandFailed(arguments: ["-m", "query", "--displays"], status: -1, message: "yabai not found")
        }
        let output = try shell(yabaiPath, "-m", "query", "--displays")
        return try decodeTolerant(YabaiDisplay.self, from: output, label: "display")
    }

    func queryWindowsRaw(timeout: TimeInterval? = nil) throws -> [YabaiWindow] {
        guard yabaiIsExecutable else {
            throw YabaiError.commandFailed(arguments: ["-m", "query", "--windows"], status: -1, message: "yabai not found")
        }
        let output = try shell([yabaiPath, "-m", "query", "--windows"], timeout: timeout)
        return try decodeTolerant(YabaiWindow.self, from: output, label: "window")
    }

    // Short-lived snapshots coalesce the HUD/glyph/menubar fan-out that lands
    // within a few milliseconds of one signal. Mutating commands invalidate
    // them so a user-initiated refresh never re-reads pre-mutation state.
    func cachedSpaces(retryOnGenerationMismatch: Bool = true) throws -> [YabaiSpace] {
        cacheLock.lock()
        let cached = _spacesCache
        let now = currentUptime
        if let cached, now - cached.cachedAt < snapshotCacheTTL {
            cacheLock.unlock()
            return cached.spaces
        }
        if spacesFetchInFlight {
            // Single-flight: concurrent callers wait for the one in-flight
            // query instead of spawning duplicates or serving stale data.
            let waitUntil = Date().addingTimeInterval(Self.snapshotWaitBound)
            while spacesFetchInFlight && Date() < waitUntil {
                cacheLock.wait(until: waitUntil)
            }
            let cachedNow = _spacesCache
            let afterWait = currentUptime
            if let cachedNow, afterWait - cachedNow.cachedAt < snapshotCacheTTL {
                cacheLock.unlock()
                return cachedNow.spaces
            }
            if spacesFetchInFlight {
                // Bounded wait expired; fall back to our own query.
                cacheLock.unlock()
                return try querySpacesRaw()
            }
            // The in-flight fetch failed without producing a usable result.
        }
        let generation = snapshotGeneration
        spacesFetchInFlight = true
        cacheLock.unlock()

        let fresh: Result<[YabaiSpace], Error>
        do {
            fresh = .success(try querySpacesRaw())
        } catch {
            fresh = .failure(error)
        }

        cacheLock.lock()
        spacesFetchInFlight = false
        cacheLock.broadcast()
        let completedAt = currentUptime

        if generation != snapshotGeneration {
            // State changed while querying: never return pre-mutation data.
            let cachedNow = _spacesCache
            cacheLock.unlock()
            if let cachedNow, completedAt - cachedNow.cachedAt < snapshotCacheTTL {
                return cachedNow.spaces
            }
            if retryOnGenerationMismatch {
                return try cachedSpaces(retryOnGenerationMismatch: false)
            }
            switch fresh {
            case .success(let spaces):
                return spaces
            case .failure(let error):
                if let cachedNow, completedAt - cachedNow.cachedAt < snapshotStaleTTL {
                    return cachedNow.spaces
                }
                throw error
            }
        }

        // A concurrent fill landed while querying: serve it instead.
        if let cachedNow = _spacesCache,
           completedAt - cachedNow.cachedAt < snapshotCacheTTL {
            let spaces = cachedNow.spaces
            cacheLock.unlock()
            return spaces
        }
        switch fresh {
        case .success(let spaces):
            // A transient empty spaces result must not evict a good snapshot.
            if spaces.isEmpty,
               let existing = _spacesCache,
               !existing.spaces.isEmpty,
               completedAt - existing.cachedAt < snapshotStaleTTL {
                let stale = existing.spaces
                cacheLock.unlock()
                return stale
            }
            _spacesCache = (spaces, completedAt)
            cacheLock.unlock()
            return spaces
        case .failure(let error):
            let staleEntry = _spacesCache ?? cached
            cacheLock.unlock()
            if let staleEntry, completedAt - staleEntry.cachedAt < snapshotStaleTTL {
                return staleEntry.spaces
            }
            throw error
        }
    }

    func cachedWindows(retryOnGenerationMismatch: Bool = true) throws -> [YabaiWindow] {
        cacheLock.lock()
        let cached = _windowsCache
        let now = currentUptime
        if let cached, now - cached.cachedAt < snapshotCacheTTL {
            cacheLock.unlock()
            return cached.windows
        }
        if windowsFetchInFlight {
            let waitUntil = Date().addingTimeInterval(Self.snapshotWaitBound)
            while windowsFetchInFlight && Date() < waitUntil {
                cacheLock.wait(until: waitUntil)
            }
            let cachedNow = _windowsCache
            let afterWait = currentUptime
            if let cachedNow, afterWait - cachedNow.cachedAt < snapshotCacheTTL {
                cacheLock.unlock()
                return cachedNow.windows
            }
            if windowsFetchInFlight {
                cacheLock.unlock()
                return try queryWindowsRaw()
            }
        }
        let generation = snapshotGeneration
        windowsFetchInFlight = true
        cacheLock.unlock()

        let fresh: Result<[YabaiWindow], Error>
        do {
            fresh = .success(try queryWindowsRaw())
        } catch {
            fresh = .failure(error)
        }

        cacheLock.lock()
        windowsFetchInFlight = false
        cacheLock.broadcast()
        let completedAt = currentUptime

        if generation != snapshotGeneration {
            let cachedNow = _windowsCache
            cacheLock.unlock()
            if let cachedNow, completedAt - cachedNow.cachedAt < snapshotCacheTTL {
                return cachedNow.windows
            }
            if retryOnGenerationMismatch {
                return try cachedWindows(retryOnGenerationMismatch: false)
            }
            switch fresh {
            case .success(let windows):
                return windows
            case .failure(let error):
                if let cachedNow, completedAt - cachedNow.cachedAt < snapshotStaleTTL {
                    return cachedNow.windows
                }
                throw error
            }
        }

        if let cachedNow = _windowsCache,
           completedAt - cachedNow.cachedAt < snapshotCacheTTL {
            let windows = cachedNow.windows
            cacheLock.unlock()
            return windows
        }
        switch fresh {
        case .success(let windows):
            _windowsCache = (windows, completedAt)
            cacheLock.unlock()
            return windows
        case .failure(let error):
            let staleEntry = _windowsCache ?? cached
            cacheLock.unlock()
            if let staleEntry, completedAt - staleEntry.cachedAt < snapshotStaleTTL {
                return staleEntry.windows
            }
            throw error
        }
    }

    /// Called after any yabai command that can change spaces/windows/focus,
    /// including mutations made outside Spacemap (socket onRefresh/onShow).
    func invalidateSnapshotCaches() {
        cacheLock.lock()
        snapshotGeneration += 1
        _spacesCache = nil
        _windowsCache = nil
        cacheLock.unlock()
    }

    func queryFocusedWindow() throws -> Int? {
        guard isYabaiRunning(), yabaiIsExecutable else { return nil }
        let output = try shell(yabaiPath, "-m", "query", "--windows", "--window")
        guard let data = output.data(using: .utf8),
              let json = try? JSONDecoder().decode(YabaiWindow.self, from: data) else { return nil }
        return json.id
    }

    func queryFocusedSpaceIndex() -> Int? {
        guard isYabaiRunning() else { return nil }
        do {
            let spaces = try querySpacesRaw()
            return spaces.first { $0.hasFocus }?.index
        } catch {
            return nil
        }
    }


}
