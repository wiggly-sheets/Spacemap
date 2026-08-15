import AppKit

final class IconCacheService {

    private let iconCache: IconCache

    init(iconCache: IconCache = IconCache()) {
        self.iconCache = iconCache
    }

    func icon(for appName: String) -> NSImage? {
        iconCache.icon(for: appName)
    }

    func preload(appNames: some Sequence<String>) {
        iconCache.preload(appNames: appNames)
    }

    func clear() {
        iconCache.clear()
    }
}
