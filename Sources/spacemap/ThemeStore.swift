import Foundation

/// Owns the theme dictionary for one themes directory: loads `.smthemes`/`.toml`
/// files, fills gaps from the bundled themes, saves edited copies, and resolves
/// names to themes.
final class ThemeStore {

    private struct DirectoryStamp: Equatable {
        struct Entry: Equatable {
            let name: String
            let size: Int
            let modificationDate: Date
        }

        let entries: [Entry]
    }

    /// Resolved per call so `CFFIXED_USER_HOME` (tests) still redirects it.
    static var defaultDirectory: URL {
        URL(fileURLWithPath: NSString(string: "~/.config/spacemap/themes").expandingTildeInPath)
    }

    let directory: URL
    private let lock = NSLock()
    private var themes: [String: AppTheme] = [:]
    /// Sorted `(name, size, mtime)` snapshot of the theme files at the last
    /// load. Directory mtime alone misses in-place `.smthemes` edits.
    private var loadedDirectoryStamp: DirectoryStamp?
    /// Unknown names are looked up on every strip refresh; log each once.
    private var loggedUnresolvedNames = Set<String>()

    init(directory: URL = ThemeStore.defaultDirectory) {
        self.directory = directory
        reload()
    }

    func reload() {
        ensureDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }
        let themeFiles = files
            .filter(Self.isThemeFile)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if themeFiles.count > 256 {
            NSLog("spacemap/ThemeStore: dropped %d theme files beyond 256", themeFiles.count - 256)
        }

        var loaded: [String: AppTheme] = [:]
        for file in themeFiles.prefix(256) {
            let name = Self.normalizedName(file.deletingPathExtension().lastPathComponent)
            if let theme = Self.parseTheme(from: file) {
                loaded[name] = theme
            } else {
                NSLog("spacemap/ThemeStore: failed to parse theme file %@", file.lastPathComponent)
            }
        }
        for (name, theme) in bundledThemes() where loaded[name] == nil {
            loaded[name] = theme
        }
        withLock {
            themes = loaded
            loadedDirectoryStamp = directoryStamp()
        }
    }

    /// Reloads only when the theme files changed. `HUDWindowController` and the
    /// strip both react to one settings save, so this also prevents a second
    /// parse of the same directory.
    func reloadIfChanged() {
        let stamp = directoryStamp()
        let changed = withLock { stamp != loadedDirectoryStamp }
        guard changed else { return }
        reload()
    }

    func named(_ name: String) -> AppTheme {
        let key = Self.normalizedName(name)
        let compact = Self.compactName(name)
        return withLock {
            if let theme = themes[key] { return theme }
            // Docs also list compact names (`tokyonight`); accept those without
            // weakening exact-name precedence. Sorted keys keep a collision
            // deterministic across loads.
            for candidate in themes.keys.sorted() where Self.compactName(candidate) == compact {
                if let theme = themes[candidate] { return theme }
            }
            if loggedUnresolvedNames.insert(key).inserted {
                NSLog("spacemap/ThemeStore: theme '%@' not found; using default", name)
            }
            return .default
        }
    }

    func allNames() -> [String] {
        withLock { Array(themes.keys).sorted() }
    }

    /// Theme actually painted by the strip: its own `theme` key when set,
    /// otherwise the main HUD's.
    func resolvedThemeName(strip: GlyphStripConfig, hudTheme: String) -> String {
        if strip.matchHUDAppearance { return hudTheme }
        return strip.theme.isEmpty ? hudTheme : strip.theme
    }

    @discardableResult
    func ensureDirectory() -> URL {
        ConfigLoader.secureDirectory(at: directory.path)
        return directory
    }

    /// Theme files in the directory, sorted by file name.
    func themeFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return files.filter(Self.isThemeFile).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func installedNames() -> Set<String> {
        Set(themeFiles().map {
            Self.normalizedName($0.deletingPathExtension().lastPathComponent)
        })
    }

    /// Writes a theme as TOML so custom themes stay hand-editable. Refuses a
    /// symlinked target, like every other config write. Returns the name it
    /// wrote, which is `name` with path separators replaced, so the result
    /// resolves through `named(_:)`.
    @discardableResult
    func save(theme: AppTheme, name: String) -> String? {
        let trimmed = saveDestinationName(name)
        guard !trimmed.isEmpty else { return nil }
        let safe = Self.fileStem(trimmed)
        let dir = ensureDirectory()
        let file = dir.appendingPathComponent(safe.replacingOccurrences(of: " ", with: "-") + ".toml")
        guard !ConfigLoader.isSymlink(at: file.path) else { return nil }
        guard ConfigLoader.secureWrite(ThemeCodec.renderTheme(theme), to: file.path) else {
            return nil
        }
        reload()
        return safe
    }

    /// On-disk stem for a theme name: path separators become hyphens so a name
    /// can never escape the themes directory. Spaces stay; they are safe and
    /// `normalizedName` collapses them with the hyphens files use.
    static func fileStem(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    /// Editing an existing theme never overwrites its source file. The first
    /// save creates `<name> (Edited)`; later saves update that copy.
    func saveDestinationName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let exists = isBundledTheme(trimmed) || userThemeExists(trimmed)
        return Self.editedCopyName(trimmed, existing: exists)
    }

    /// Pure naming rule behind `saveDestinationName`: an existing theme gains
    /// one `(Edited)` suffix; saving that copy again keeps its name.
    static func editedCopyName(_ name: String, existing: Bool) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if normalizedName(trimmed).hasSuffix(" (edited)") { return trimmed }
        return existing ? "\(trimmed) (Edited)" : trimmed
    }

    private func userThemeExists(_ name: String) -> Bool {
        let safe = Self.fileStem(name).replacingOccurrences(of: " ", with: "-")
        let file = directory.appendingPathComponent(safe + ".toml")
        return FileManager.default.fileExists(atPath: file.path)
    }

    /// Theme names are advertised with hyphens (`monokai-dark`) but stored
    /// with spaces (`monokai dark`). Both, plus underscores and repeated
    /// whitespace, resolve to the same key.
    static func normalizedName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func compactName(_ name: String) -> String {
        normalizedName(name).filter { !$0.isWhitespace }
    }

    static func isThemeFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "smthemes" || ext == "toml"
    }

    // MARK: - Bundled themes

    /// Read-only themes shipped in the app bundle. A user file with the same
    /// name wins, so editing or reinstalling a bundled theme works normally.
    private func bundledThemes() -> [String: AppTheme] {
        Self.bundledThemeFiles().reduce(into: [:]) { result, url in
            let name = Self.normalizedName(url.deletingPathExtension().lastPathComponent)
            if let theme = Self.parseTheme(from: url) {
                result[name] = theme
            }
        }
    }

    static func bundledThemeFiles() -> [URL] {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Themes"),
              let files = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
              ) else { return [] }
        return files.filter(Self.isThemeFile).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Immutable snapshot so listing hundreds of catalog entries does not
    /// re-read the bundle.
    private static let bundledNames: Set<String> = Set(ThemeStore.bundledThemeFiles().map {
        normalizedName($0.deletingPathExtension().lastPathComponent)
    })

    func isBundledTheme(_ name: String) -> Bool {
        Self.bundledNames.contains(Self.normalizedName(name))
    }

    // MARK: - Reading

    private func directoryStamp() -> DirectoryStamp? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return nil }
        let entries: [DirectoryStamp.Entry] = files
            .filter(Self.isThemeFile)
            .compactMap { url in
                guard let values = try? url.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey]
                ) else { return nil }
                return DirectoryStamp.Entry(
                    name: url.lastPathComponent,
                    size: values.fileSize ?? -1,
                    modificationDate: values.contentModificationDate ?? .distantPast
                )
            }
            .sorted { $0.name < $1.name }
        return DirectoryStamp(entries: entries)
    }

    private static func parseTheme(from url: URL) -> AppTheme? {
        // Same fail-closed read as ConfigLoader: refuse symlinks, cap size,
        // O_NOFOLLOW open so a link swapped in after the check still fails.
        guard !ConfigLoader.isSymlink(at: url.path) else { return nil }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var statBuf = stat()
        guard fstat(fd, &statBuf) == 0, (statBuf.st_mode & S_IFMT) == S_IFREG else { return nil }
        guard statBuf.st_size <= ConfigLoader.maxConfigBytes else { return nil }
        let data = FileHandle(fileDescriptor: fd, closeOnDealloc: false).readDataToEndOfFile()
        guard data.count <= ConfigLoader.maxConfigBytes,
              let content = String(data: data, encoding: .utf8) else { return nil }
        return ThemeCodec.parseThemeContent(content)
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
