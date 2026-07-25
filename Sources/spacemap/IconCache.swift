import AppKit

/// Caches app icons by name to avoid repeated NSWorkspace.icon(forFile:) calls.
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    private var bundlePathByName: [String: String] = [:]

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

    func clear() { cache.removeAll() }

    private func rebuildLookup() {
        var lookup: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let name = app.localizedName, let url = app.bundleURL else { continue }
            lookup[name] = url.path
        }
        bundlePathByName = lookup
    }
}
