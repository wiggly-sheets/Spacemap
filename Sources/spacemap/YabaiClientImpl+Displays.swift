import Foundation
import AppKit

extension YabaiClientImpl {
    func cachedDisplays() -> [YabaiDisplay] {
        cacheLock.lock()
        let cached = _displaysCache
        let now = currentUptime
        if let cached, now - cached.cachedAt < displaysCacheTTL {
            cacheLock.unlock()
            return cached.displays
        }
        // Single-flight: a concurrent miss serves stale instead of a second spawn.
        if displaysFetchInFlight {
            let stale = cached?.displays ?? []
            cacheLock.unlock()
            return stale
        }
        displaysFetchInFlight = true
        cacheLock.unlock()
        // Cache only non-empty results: a failed query yields [] and must not
        // evict the last good snapshot for a full TTL, or multi-monitor blanks.
        // On failure return last good (or [] if none) without touching cache,
        // so the next call retries instead of serving stale emptiness.
        let fresh = try? queryDisplaysRaw()
        cacheLock.lock()
        displaysFetchInFlight = false
        // Recheck under lock: a concurrent fill may have landed while querying.
        let completedAt = currentUptime
        if let cachedNow = _displaysCache,
           completedAt - cachedNow.cachedAt < displaysCacheTTL {
            let displays = cachedNow.displays
            cacheLock.unlock()
            return displays
        }
        guard let fresh, !fresh.isEmpty else {
            let stale = _displaysCache?.displays ?? cached?.displays ?? []
            cacheLock.unlock()
            return stale
        }
        _displaysCache = (fresh, completedAt)
        cacheLock.unlock()
        return fresh
    }


}
