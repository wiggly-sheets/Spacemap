import AppKit
import Foundation

/// App-name to NSImage lookup for native icon rendering.
///
/// Resolution order per name: running-application fast path (by pid, then by
/// bundle path), in-memory [appName: bundle path] map rebuilt on
/// launch/terminate, mdfind fallback on miss, workspace icon for the
/// resolved path. Cached images are sized to 64pt up front so every consumer
/// shares one raster.
///
/// Deliberately no disk cache: a persisted map goes stale on every
/// install/move/rename, and the running-app rebuild already covers the steady
/// state. Non-running apps resolve via one background mdfind.
final class IconCache {
    static let shared = IconCache()

    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]
    /// MRU-last key order, parallel to `cache`. Lock-guarded.
    private var order: [String] = []
    private var bundlePathByName: [String: String] = [:]
    /// Names with a Spotlight lookup already running. Lock-guarded.
    private var inFlight: Set<String> = []
    private var pendingCompletions: [String: [(@Sendable (NSImage?) -> Void)]] = [:]
    /// Bumped on clear(): stale Spotlight lookups check it before store.
    private var generation: UInt64 = 0
    /// Negative cache: miss timestamps stop repeat mdfind for unknown apps.
    private var unresolvedUntil: [String: TimeInterval] = [:]

    /// Cap for `cache`. Running-app count bounds the lookup map; only the
    /// image map needs eviction.
    static let maxEntries = 200
    /// Serial Spotlight queue: one mdfind at a time so a wedged
    /// Spotlight never pins the shared utility pool. Coalescing
    /// (inFlight/pendingCompletions) still dedupes repeat names.
    private static let spotlightQueue = DispatchQueue(label: "com.spacemap.iconcache.spotlight")
    static let unresolvedTTL: TimeInterval = 30

    private let workspace: WorkspaceProtocol

    init(workspace: WorkspaceProtocol = NSWorkspace.shared) {
        self.workspace = workspace
        rebuildLookup()
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: nil
        ) { [weak self] _ in self?.rebuildLookup() }
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: nil
        ) { [weak self] _ in self?.rebuildLookup() }
    }

    convenience init() {
        self.init(workspace: NSWorkspace.shared as WorkspaceProtocol)
    }

    /// Memory-only hit: lock read, no IPC, no disk. Safe any thread. The
    /// strip's main-thread measure/draw path uses this so steady-state
    /// refreshes never block on `icon(forFile:)`. Misses paint the fallback
    /// glyph until `resolveInBackground` lands them.
    func cachedIcon(for appName: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let image = cache[appName] else { return nil }
        touchLocked(appName)
        return image
    }

    /// pid fast path first (exact process), then the name map.
    /// Main-only fetch: background callers get the memory hit and use
    /// `resolveInBackground` for the rest, so `icon(forFile:)` IPC never
    /// runs off-main (NSWorkspace + NSImage are main-only).
    func icon(for appName: String, pid: Int32? = nil) -> NSImage? {
        lock.lock()
        if let cached = cache[appName] {
            touchLocked(appName)
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard Thread.isMainThread else { return nil }
        if let pid,
           let app = NSRunningApplication(processIdentifier: pid),
           app.localizedName == appName {
            if let icon = app.icon {
                return store(icon, for: appName)
            }
            if let path = app.bundleURL?.path {
                remember(path: path, for: appName)
                return store(workspace.icon(forFile: path), for: appName)
            }
        }
        // Name map indexed once per rebuild; launch/terminate rebuilds keep it fresh.
        lock.lock()
        let path = bundlePathByName[appName]
        lock.unlock()
        guard let path else { return nil }
        return store(workspace.icon(forFile: path), for: appName)
    }

    /// Async miss resolution: path lookup runs off-main, icon fetch/store
    /// runs on main (NSWorkspace + NSImage are main-only). Never blocks strip.
    /// Coalesced: concurrent misses for one name share one mdfind, and names
    /// with no bundle anywhere sleep `unresolvedTTL` before the next attempt.
    func resolveInBackground(appName: String, completion: (@Sendable (NSImage?) -> Void)? = nil) {
        lock.lock()
        let gen = generation
        let known = bundlePathByName[appName] != nil || cache[appName] != nil
        if known {
            lock.unlock()
            DispatchQueue.main.async { completion?(self.icon(for: appName)) }
            return
        }
        if inFlight.contains(appName) {
            if let completion { pendingCompletions[appName, default: []].append(completion) }
            lock.unlock()
            return
        }
        if let until = unresolvedUntil[appName],
           ProcessInfo.processInfo.systemUptime < until {
            lock.unlock()
            DispatchQueue.main.async { completion?(nil) }
            return
        }
        inFlight.insert(appName)
        if let completion { pendingCompletions[appName, default: []].append(completion) }
        lock.unlock()
        Self.spotlightQueue.async { [weak self] in
            guard let self else { return }
            guard let path = Self.pathViaSpotlight(appName: appName) else {
                self.lock.lock()
                // Stale lookup: clear() already fired these completions.
                // Touch nothing: a new generation may own this state.
                if gen != self.generation {
                    self.lock.unlock()
                    return
                }
                self.inFlight.remove(appName)
                self.unresolvedUntil[appName] = ProcessInfo.processInfo.systemUptime + Self.unresolvedTTL
                let completions = self.pendingCompletions.removeValue(forKey: appName) ?? []
                self.lock.unlock()
                guard !completions.isEmpty else { return }
                DispatchQueue.main.async {
                    for pending in completions { pending(nil) }
                }
                return
            }
            self.lock.lock()
            let stale = gen != self.generation
            self.lock.unlock()
            if !stale { self.remember(path: path, for: appName) }
            DispatchQueue.main.async {
                self.lock.lock()
                // Post-clear lookup must not store into the fresh state.
                // clear() already fired these completions with nil, and a
                // new generation may own this state — touch nothing.
                if gen != self.generation {
                    self.lock.unlock()
                    return
                }
                let image = self.store(self.workspace.icon(forFile: path), for: appName)
                self.inFlight.remove(appName)
                self.unresolvedUntil.removeValue(forKey: appName)
                let completions = self.pendingCompletions.removeValue(forKey: appName) ?? []
                self.lock.unlock()
                for pending in completions { pending(image) }
            }
        }
    }

    func preload(appNames: some Sequence<String>) {
        preloadInBackground(appNames: appNames)
    }

    func preloadInBackground(appNames: some Sequence<String>) {
        for name in Array(Set(appNames)) {
            resolveInBackground(appName: name)
        }
    }

    func clear() {
        lock.lock()
        generation &+= 1
        cache.removeAll()
        order.removeAll()
        bundlePathByName.removeAll()
        unresolvedUntil.removeAll()
        inFlight.removeAll()
        let dropped = pendingCompletions.values.flatMap { $0 }
        pendingCompletions.removeAll()
        lock.unlock()
        // Never drop a waiter: stale lookups check generation and stay out.
        if !dropped.isEmpty {
            DispatchQueue.main.async {
                for pending in dropped { pending(nil) }
            }
        }
        rebuildLookup()
    }

    // MARK: - Lookup

    private func rebuildLookup() {
        var lookup: [String: String] = [:]
        for app in workspace.runningApplications {
            guard let url = app.bundleURL else { continue }
            // Bundle path is the stable key; the name map points at it.
            // localizedName is display-localized and can collide, so prefer
            // the bundle id's app name only as a tiebreak fill.
            if let name = app.localizedName, lookup[name] == nil {
                lookup[name] = url.path
            }
            if let bundleID = app.bundleIdentifier {
                let short = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
                if lookup[short] == nil { lookup[short] = url.path }
            }
        }
        lock.lock()
        bundlePathByName = lookup
        lock.unlock()
    }

    private func remember(path: String, for appName: String) {
        lock.lock()
        bundlePathByName[appName] = path
        lock.unlock()
    }

    @discardableResult
    // Internal for the LRU test; production callers use icon/cachedIcon.
    func store(_ icon: NSImage, for appName: String) -> NSImage {
        icon.size = NSSize(width: 64, height: 64)
        lock.lock()
        cache[appName] = icon
        touchLocked(appName)
        while cache.count > Self.maxEntries,
              let index = order.firstIndex(where: { $0 != appName }) {
            let victim = order.remove(at: index)
            cache.removeValue(forKey: victim)
        }
        lock.unlock()
        return icon
    }

    /// MRU-last ordering for the LRU cap. Call with `lock` held.
    private func touchLocked(_ appName: String) {
        if let index = order.firstIndex(of: appName) { order.remove(at: index) }
        order.append(appName)
    }

    /// Last resort for apps that are neither running nor cached: one mdfind by
    /// display name, validated to a real .app bundle. Slow — background only.
    private static func pathViaSpotlight(appName: String) -> String? {
        // Fail closed: quote/control chars never reach the predicate.
        guard appName.rangeOfCharacter(from: .controlCharacters) == nil,
              !appName.contains("'"), !appName.contains("\"") else { return nil }
        let escaped = appName.replacingOccurrences(of: "\\", with: "\\\\")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemKind == 'Application' && kMDItemDisplayName == '\(escaped)'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // waitUntilExit blocks forever on a wedged Spotlight; cap the wait
        // on this serial-queue lookup and kill the child on timeout.
        // Monotonic clock: wall-clock jumps must not cut the wait short.
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !process.isRunning else {
            process.terminate()
            // Bounded grace: a child ignoring SIGTERM must not wedge queue.
            let killDeadline = ProcessInfo.processInfo.systemUptime + 0.5
            while process.isRunning, ProcessInfo.processInfo.systemUptime < killDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            // SIGTERM→SIGKILL escalation; child is dead so wait returns fast.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return nil
        }
        process.waitUntilExit()
        // Bounded read: first paths only, never the full output.
        let data = pipe.fileHandleForReading.readData(ofLength: 64 * 1024)
        let output = String(data: data, encoding: .utf8) ?? ""
        for line in output.split(separator: "\n") {
            let path = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if path.hasSuffix(".app"),
               FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
}
