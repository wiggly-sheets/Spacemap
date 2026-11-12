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
            .filter { $0.pathExtension == "smthemes" }
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
        seedDefaultsIfNeeded()
        let dir = Self.ensureThemesDir()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }
        let themeFiles = files
            .filter { $0.pathExtension == "smthemes" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if themeFiles.count > 64 {
            NSLog("spacemap/ThemeManager: dropped %d theme files beyond 64", themeFiles.count - 64)
        }

        var loaded: [String: AppTheme] = [:]
        for file in themeFiles.prefix(64) {
            let name = Self.normalizedName(file.deletingPathExtension().lastPathComponent)
            if let theme = parseTheme(from: file) {
                loaded[name] = theme
            } else {
                NSLog("spacemap/ThemeManager: failed to parse theme file %@", file.lastPathComponent)
            }
        }
        for (name, theme) in Self.builtinThemes() {
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

    private func parseTheme(from url: URL) -> AppTheme? {
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
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces).lowercased()
            let hex = String(parts[1]).trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "#", with: "")
            guard hex.count == 6, let val = UInt32(hex, radix: 16) else { continue }
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

    private func seedDefaultsIfNeeded() {
        let dir = Self.ensureThemesDir()
        let fm = FileManager.default
        if let existing = try? fm.contentsOfDirectory(atPath: dir.path),
           existing.contains(where: { $0.hasSuffix(".smthemes") }) {
            return
        }
        for (name, theme) in Self.builtinThemes() {
            let filename = name.replacingOccurrences(of: " ", with: "-") + ".smthemes"
            let file = dir.appendingPathComponent(filename)
            let content = """
            # \(name.capitalized)
            background=\(Self.hex(theme.background))
            focused=\(Self.hex(theme.focused))
            text=\(Self.hex(theme.text))
            dropTarget=\(Self.hex(theme.dropTarget))
            cellBg=\(Self.hex(theme.cellBg))
            cellBgFocused=\(Self.hex(theme.cellBgFocused))
            rect1=\(Self.hex(theme.rect1))
            rect2=\(Self.hex(theme.rect2))
            rect3=\(Self.hex(theme.rect3))
            """
            _ = ConfigLoader.secureWrite(content, to: file.path)
        }
    }

    private static func builtinThemes() -> [String: AppTheme] {
        [
            "default": .default,
            "tokyo night": .tokyonight,
            "catppuccin": .catppuccin,
            "monokai dark": .monokaiDark,
            "monokai light": .monokaiLight,
            "dracula": .dracula,
            "ayu": .ayu,
            "github": .github,
            "vscode": .vscode,
            "xcode": .xcode,
            "nord": .nord,
            "atom one dark": .atomOneDark,
        ]
    }

    static func hex(_ value: UInt32) -> String {
        let s = String(value & 0xFFFFFF, radix: 16)
        return String(repeating: "0", count: max(0, 6 - s.count)) + s
    }
}
