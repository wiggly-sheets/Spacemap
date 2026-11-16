import Foundation
import Combine

struct ThemeCatalogEntry: Codable, Identifiable, Equatable {
    let name: String
    let file: String
    let colors: [String: String]

    var id: String { file }
    var theme: AppTheme? { AppTheme(colors: colors) }
}

struct ThemeCatalogFile: Codable {
    let version: Int
    let themes: [ThemeCatalogEntry]
}

/// Fetches the optional online theme pack and installs single themes into the
/// user's theme directory. Bundled themes stay read-only.
@MainActor
final class ThemeCatalogService: ObservableObject {
    static let shared = ThemeCatalogService()

    static let catalogURL = URL(
        string: ProcessInfo.processInfo.environment["SPACEMAP_THEME_CATALOG"]
            ?? "https://raw.githubusercontent.com/wiggly-sheets/spacemap-themes/main/index.json"
    )!
    static let baseURL = catalogURL.deletingLastPathComponent()

    @Published private(set) var entries: [ThemeCatalogEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let cacheURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Spacemap/theme-catalog.json")
    }()
    private let lastRefreshKey = "themeCatalogLastRefresh"
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        entries = bundledEntries()
        loadCache()
        let last = UserDefaults.standard.double(forKey: lastRefreshKey)
        if Date().timeIntervalSince1970 - last > 24 * 60 * 60 {
            Task { await refresh(manual: false) }
        }
    }

    func refresh(manual: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            var request = URLRequest(url: Self.catalogURL)
            request.timeoutInterval = 15
            request.setValue("Spacemap", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count <= 4_000_000,
                  let file = try? JSONDecoder().decode(ThemeCatalogFile.self, from: data),
                  file.version == 1 else {
                throw CatalogError.invalidCatalog
            }
            try writeCache(data)
            entries = merge(bundled: bundledEntries(), remote: file.themes)
            lastError = nil
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastRefreshKey)
        } catch {
            if manual { lastError = error.localizedDescription }
        }
    }

    func install(_ entry: ThemeCatalogEntry) async throws {
        guard let url = URL(string: entry.file, relativeTo: Self.baseURL),
              url.scheme == "https" else { throw CatalogError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 256_000,
              let content = String(data: data, encoding: .utf8),
              ThemeManager.parseThemeContent(content) != nil else {
            throw CatalogError.invalidTheme
        }
        ThemeManager.ensureThemesDir()
        let path = ThemeManager.themesDir()
            .appendingPathComponent(Self.safeFilename(entry.name) + ".toml").path
        guard ConfigLoader.secureWrite(content, to: path) else { throw CatalogError.writeFailed }
        ThemeManager.shared.reload()
    }

    func uninstall(_ entry: ThemeCatalogEntry) throws {
        guard !ThemeManager.isBundledTheme(entry.name) else { throw CatalogError.bundledReadOnly }
        let normalized = ThemeManager.normalizedName(entry.name)
        let dir = ThemeManager.themesDir()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )) ?? []
        guard let file = files.first(where: {
            ThemeManager.isThemeFile($0)
                && ThemeManager.normalizedName($0.deletingPathExtension().lastPathComponent) == normalized
        }) else { return }
        try FileManager.default.removeItem(at: file)
        ThemeManager.shared.reload()
    }

    func isInstalled(_ entry: ThemeCatalogEntry) -> Bool {
        if ThemeManager.isBundledTheme(entry.name) { return true }
        return installedNames().contains(ThemeManager.normalizedName(entry.name))
    }

    func isBundled(_ entry: ThemeCatalogEntry) -> Bool {
        ThemeManager.isBundledTheme(entry.name)
    }

    private func installedNames() -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: ThemeManager.themesDir(),
            includingPropertiesForKeys: nil
        )) ?? []
        return Set(files.filter(ThemeManager.isThemeFile).map {
            ThemeManager.normalizedName($0.deletingPathExtension().lastPathComponent)
        })
    }

    private func bundledEntries() -> [ThemeCatalogEntry] {
        ThemeManager.bundledThemeFiles().compactMap { url in
            guard let content = try? String(contentsOf: url, encoding: .utf8),
                  let theme = ThemeManager.parseThemeContent(content) else { return nil }
            return ThemeCatalogEntry(
                name: url.deletingPathExtension().lastPathComponent,
                file: url.lastPathComponent,
                colors: Self.colorStrings(theme)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let file = try? JSONDecoder().decode(ThemeCatalogFile.self, from: data),
              file.version == 1 else { return }
        entries = merge(bundled: bundledEntries(), remote: file.themes)
    }

    private func merge(bundled: [ThemeCatalogEntry], remote: [ThemeCatalogEntry]) -> [ThemeCatalogEntry] {
        var byName = Dictionary(uniqueKeysWithValues: bundled.map { ($0.name, $0) })
        for entry in remote { byName[entry.name] = entry }
        return byName.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func writeCache(_ data: Data) throws {
        let dir = cacheURL.deletingLastPathComponent()
        ConfigLoader.secureDirectory(at: dir.path)
        try data.write(to: cacheURL, options: .atomic)
    }

    private static func colorStrings(_ theme: AppTheme) -> [String: String] {
        var colors: [String: String] = [:]
        for name in AppTheme.colorNames {
            if let value = theme.value(for: name) {
                colors[name] = String(format: "#%06x", value)
            }
        }
        return colors
    }

    private static func safeFilename(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    enum CatalogError: LocalizedError {
        case invalidCatalog, invalidURL, invalidTheme, writeFailed, bundledReadOnly

        var errorDescription: String? {
            switch self {
            case .invalidCatalog: return "Theme catalog could not be read."
            case .invalidURL: return "Theme download address is invalid."
            case .invalidTheme: return "Downloaded theme is not a valid Spacemap theme."
            case .writeFailed: return "Theme could not be saved."
            case .bundledReadOnly: return "Bundled themes cannot be removed."
            }
        }
    }
}

private extension AppTheme {
    init?(colors: [String: String]) {
        func color(_ name: String) -> UInt32? {
            guard let raw = colors[name] else { return nil }
            return UInt32(raw.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16)
        }
        guard let background = color("background"),
              let focused = color("focused"),
              let text = color("text"),
              let drop = color("dropTarget"),
              let cellBg = color("cellBg"),
              let cellFocused = color("cellBgFocused") else { return nil }
        self.init(
            background: background,
            focused: focused,
            text: text,
            dropTarget: drop,
            cellBg: cellBg,
            cellBgFocused: cellFocused,
            rect1: color("rect1") ?? focused,
            rect2: color("rect2") ?? focused,
            rect3: color("rect3") ?? focused
        )
    }
}
