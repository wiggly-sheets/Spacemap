import Foundation

class ThemeManager {

    private struct DirectoryStamp: Equatable {
        struct Entry: Equatable {
            let name: String
            let size: Int
            let modificationDate: Date
        }

        let entries: [Entry]
    }

    private let lock = NSLock()
    private var themes: [String: AppTheme] = [:]
    /// Sorted `(name, size, mtime)` snapshot of the theme files at the last
    /// load. Directory mtime alone misses in-place `.smthemes` edits.
    private var loadedDirectoryStamp: DirectoryStamp?
    /// Unknown names are looked up on every strip refresh; log each once.
    private var loggedUnresolvedNames = Set<String>()

    /// Single shared instance; a fresh `ThemeManager()` re-reads the whole
    /// themes directory on every construction.
    static let shared = ThemeManager()

    init() {
        loadAll()
    }


    func reload() {
        loadAll()
    }

    /// Reloads only when the theme files changed. `HUDWindowController` and the
    /// strip both react to one settings save, so this also prevents a second
    /// parse of the same directory.
    func reloadIfChanged() {
        let stamp = Self.directoryStamp()
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
                NSLog("spacemap/ThemeManager: theme '%@' not found; using default", name)
            }
            return .default
        }
    }

    func allNames() -> [String] {
        withLock { Array(themes.keys).sorted() }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
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

    private static func directoryStamp() -> DirectoryStamp? {
        let dir = themesDir()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return nil }
        let entries: [DirectoryStamp.Entry] = files
            .filter { Self.isThemeFile($0) }
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

    /// Plain key/value `.smthemes` files and TOML `.toml` files share one
    /// grammar; both are accepted so users can keep custom themes in TOML.
    static func isThemeFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "smthemes" || ext == "toml"
    }

    /// Read-only themes shipped in the app bundle. A user file with the same
    /// name wins, so editing or reinstalling a bundled theme works normally.
    static func bundledThemes() -> [String: AppTheme] {
        bundledThemeFiles().reduce(into: [:]) { result, url in
            let name = normalizedName(url.deletingPathExtension().lastPathComponent)
            if let theme = parseTheme(from: url) {
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
    static let bundledNames: Set<String> = Set(bundledThemeFiles().map {
        normalizedName($0.deletingPathExtension().lastPathComponent)
    })

    static func isBundledTheme(_ name: String) -> Bool {
        bundledNames.contains(normalizedName(name))
    }

    static func themesDir() -> URL {
        URL(fileURLWithPath: NSString(string: "~/.config/spacemap/themes").expandingTildeInPath)
    }

    @discardableResult
    static func ensureThemesDir() -> URL {
        let dir = themesDir()
        ConfigLoader.secureDirectory(at: dir.path)
        return dir
    }


    private func loadAll() {
        let dir = Self.ensureThemesDir()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }
        let themeFiles = files
            .filter { Self.isThemeFile($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if themeFiles.count > 256 {
            NSLog("spacemap/ThemeManager: dropped %d theme files beyond 256", themeFiles.count - 256)
        }

        var loaded: [String: AppTheme] = [:]
        for file in themeFiles.prefix(256) {
            let name = Self.normalizedName(file.deletingPathExtension().lastPathComponent)
            if let theme = Self.parseTheme(from: file) {
                loaded[name] = theme
            } else {
                NSLog("spacemap/ThemeManager: failed to parse theme file %@", file.lastPathComponent)
            }
        }
        for (name, theme) in Self.bundledThemes() {
            if loaded[name] == nil {
                loaded[name] = theme
            }
        }
        let stamp = Self.directoryStamp()
        withLock {
            themes = loaded
            loadedDirectoryStamp = stamp
        }
    }

    static func parseTheme(from url: URL) -> AppTheme? {
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
        return Self.parseThemeContent(content)
    }

    static func parseThemeContent(_ content: String) -> AppTheme? {
        var vals: [String: UInt32] = [:]
        for line in content.components(separatedBy: .newlines).prefix(512) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), trimmed.count <= 1024 else { continue }
            // TOML section headers carry no values.
            guard !trimmed.hasPrefix("[") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces).lowercased()
            guard let val = parseHexValue(String(parts[1])) else { continue }
            vals[key] = val
        }
        guard let bg = vals["background"],
              let focused = vals["focused"],
              let text = vals["text"],
              let drop = vals["droptarget"],
              let cellBg = vals["cellbg"],
              let cellBgFocused = vals["cellbgfocused"] else { return nil }
        let r1 = vals["rect1"] ?? focused
        let r2 = vals["rect2"] ?? focused
        let r3 = vals["rect3"] ?? focused
        return AppTheme(
            background: bg, focused: focused, text: text,
            dropTarget: drop, cellBg: cellBg, cellBgFocused: cellBgFocused,
            rect1: r1, rect2: r2, rect3: r3
        )
    }

    static func parseHexValue(_ raw: String) -> UInt32? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if let start = text.firstIndex(where: { $0 == "\"" || $0 == "'" }) {
            let quote = text[start]
            let after = text.index(after: start)
            guard let end = text[after...].firstIndex(of: quote) else { return nil }
            text = String(text[after..<end])
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        // Inline comment after an unquoted value: `#1a1b26 # note`.
        if let space = text.firstIndex(where: { $0.isWhitespace }) {
            text = String(text[..<space])
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return value
    }

    /// Writes a theme as TOML so custom themes stay hand-editable. Refuses a
    /// symlinked target, like every other config write.
    @discardableResult
    /// Editing an existing theme never overwrites its source file. The first
    /// save creates `<name> (Edited)`; later saves update that copy.
    static func saveDestinationName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let exists = isBundledTheme(trimmed) || userThemeExists(trimmed)
        return editedCopyName(trimmed, existing: exists)
    }

    /// Pure naming rule behind `saveDestinationName`: an existing theme gains
    /// one `(Edited)` suffix; saving that copy again keeps its name.
    static func editedCopyName(_ name: String, existing: Bool) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if normalizedName(trimmed).hasSuffix(" (edited)") { return trimmed }
        return existing ? "\(trimmed) (Edited)" : trimmed
    }

    private static func userThemeExists(_ name: String) -> Bool {
        let safe = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let file = themesDir().appendingPathComponent(safe + ".toml")
        return FileManager.default.fileExists(atPath: file.path)
    }

    static func save(theme: AppTheme, name: String) -> String? {
        let trimmed = saveDestinationName(name)
        guard !trimmed.isEmpty else { return nil }
        let safe = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let dir = ensureThemesDir()
        let file = dir.appendingPathComponent(safe.replacingOccurrences(of: " ", with: "-") + ".toml")
        guard !ConfigLoader.isSymlink(at: file.path) else { return nil }
        let lines = ["[colors]"] + AppTheme.colorNames.map { key in
            "\(key) = \"#\(hex(theme.value(for: key) ?? 0))\""
        }
        guard ConfigLoader.secureWrite(lines.joined(separator: "\n") + "\n", to: file.path) else {
            return nil
        }
        shared.reload()
        return trimmed
    }

    static func hex(_ value: UInt32) -> String {
        let s = String(value & 0xFFFFFF, radix: 16)
        return String(repeating: "0", count: max(0, 6 - s.count)) + s
    }
}
