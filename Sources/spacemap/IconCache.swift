import AppKit
import Foundation

/// App-name to NSImage lookup for native icon rendering.
///
/// Resolution order per name: running-application fast path (by pid, then by
/// bundle path), persistent [appName: bundleURL] disk cache with mdfind
/// fallback on miss, workspace icon for the resolved path. Cached images are
/// sized to 64pt up front so every consumer shares one raster.
final class IconCache {
    static let shared = IconCache()

    /// On-disk [appName: bundle path], seeded by launch/terminate rebuilds and
    /// by mdfind misses. Survives restarts so non-running apps still resolve.
    static var diskCacheURL: URL = {
        let dir = URL(
            fileURLWithPath: NSString(string: "~/Library/Caches/spacemap").expandingTildeInPath
        )
        return dir.appendingPathComponent("appBundleURLs.json")
    }()

    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]
    private var bundlePathByName: [String: String] = [:]

    private let workspace: WorkspaceProtocol

    init(workspace: WorkspaceProtocol = NSWorkspace.shared) {
        self.workspace = workspace
        loadDiskCache()
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
        return cache[appName]
    }

    /// pid fast path first (exact process), then the name map.
    /// Main-only fetch: background callers get the memory hit and use
    /// `resolveInBackground` for the rest, so `icon(forFile:)` IPC never
    /// runs off-main (NSWorkspace + NSImage are main-only).
    func icon(for appName: String, pid: Int32? = nil) -> NSImage? {
        lock.lock()
        if let cached = cache[appName] {
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
        for app in workspace.runningApplications where app.localizedName == appName {
            if let icon = app.icon {
                return store(icon, for: appName)
            }
            if let path = app.bundleURL?.path {
                remember(path: path, for: appName)
                return store(workspace.icon(forFile: path), for: appName)
            }
        }
        lock.lock()
        let path = bundlePathByName[appName]
        lock.unlock()
        guard let path else { return nil }
        return store(workspace.icon(forFile: path), for: appName)
    }

    /// Async miss resolution: path lookup runs off-main, icon fetch/store
    /// runs on main (NSWorkspace + NSImage are main-only). Never blocks strip.
    func resolveInBackground(appName: String, completion: (@Sendable (NSImage?) -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let known = self.bundlePathByName[appName] != nil || self.cache[appName] != nil
            self.lock.unlock()
            if known {
                DispatchQueue.main.async { completion?(self.icon(for: appName)) }
                return
            }
            guard let path = Self.pathViaSpotlight(appName: appName) else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }
            self.remember(path: path, for: appName)
            DispatchQueue.main.async {
                completion?(self.store(self.workspace.icon(forFile: path), for: appName))
            }
        }
    }

    func preload(appNames: some Sequence<String>) {
        for appName in Set(appNames) {
            _ = icon(for: appName)
        }
    }

    func preloadInBackground(appNames: some Sequence<String>) {
        for name in Array(Set(appNames)) {
            resolveInBackground(appName: name)
        }
    }

    func clear() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
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
        for (name, path) in lookup {
            bundlePathByName[name] = path
        }
        let snapshot = bundlePathByName
        lock.unlock()
        saveDiskCache(snapshot)
    }

    private func remember(path: String, for appName: String) {
        lock.lock()
        bundlePathByName[appName] = path
        let snapshot = bundlePathByName
        lock.unlock()
        saveDiskCache(snapshot)
    }

    @discardableResult
    private func store(_ icon: NSImage, for appName: String) -> NSImage {
        icon.size = NSSize(width: 64, height: 64)
        lock.lock()
        cache[appName] = icon
        lock.unlock()
        return icon
    }

    // MARK: - Persistent cache

    private func loadDiskCache() {
        guard let data = try? Data(contentsOf: Self.diskCacheURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        let fm = FileManager.default
        lock.lock()
        for (name, path) in map where fm.fileExists(atPath: path) {
            bundlePathByName[name] = path
        }
        lock.unlock()
    }

    private func saveDiskCache(_ map: [String: String]) {
        let url = Self.diskCacheURL
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            if let data = try? JSONEncoder().encode(map) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// Last resort for apps that are neither running nor cached: one mdfind by
    /// display name, validated to a real .app bundle. Slow — background only.
    private static func pathViaSpotlight(appName: String) -> String? {
        let escaped = appName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemKind == 'Application' && kMDItemDisplayName == '\(escaped)'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
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
