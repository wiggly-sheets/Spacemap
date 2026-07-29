import AppKit

/// Caches app icons by name to avoid repeated NSWorkspace.icon(forFile:) calls.
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    private var bundlePathByName: [String: String] = [:]
    private var regularApplicationPIDs: Set<pid_t> = []

    private init() {
        rebuildLookup()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: nil
        ) { [weak self] _ in self?.rebuildLookup() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: nil
        ) { [weak self] _ in self?.rebuildLookup() }
    }

    func icon(for appName: String) -> NSImage? {
        if let cached = cache[appName] { return cached }
        guard let path = bundlePathByName[appName] else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[appName] = icon
        return icon
    }

    /// Prime the cache before the HUD is rendered so the first frame contains
    /// app icons instead of resolving them lazily in SwiftUI's body.
    func preload(appNames: some Sequence<String>) {
        for appName in Set(appNames) {
            _ = icon(for: appName)
        }
    }

    func clear() { cache.removeAll() }

    func isRegularApplication(processIdentifier: Int?) -> Bool {
        guard let processIdentifier, processIdentifier > 0 else { return false }
        return regularApplicationPIDs.contains(pid_t(processIdentifier))
    }

    private func rebuildLookup() {
        var lookup: [String: String] = [:]
        var regularPIDs = Set<pid_t>()
        for app in NSWorkspace.shared.runningApplications {
            guard let name = app.localizedName, let url = app.bundleURL else { continue }
            lookup[name] = url.path
            if app.activationPolicy == .regular {
                regularPIDs.insert(app.processIdentifier)
            }
        }
        bundlePathByName = lookup
        regularApplicationPIDs = regularPIDs
    }
}
