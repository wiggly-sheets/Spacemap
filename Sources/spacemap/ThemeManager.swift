import Foundation

class ThemeManager {
    static let shared = ThemeManager()

    private var themes: [String: AppTheme] = [:]

    private init() {
        loadAll()
    }

    // MARK: - Public

    func reload() {
        loadAll()
    }

    func named(_ name: String) -> AppTheme {
        themes[name.lowercased()] ?? .default
    }

    func allNames() -> [String] {
        Array(themes.keys).sorted()
    }

    static func themesDir() -> URL {
        let dir = URL(fileURLWithPath: NSString(string: "~/.config/spacemap/themes").expandingTildeInPath)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Private

    private func loadAll() {
        themes.removeAll()
        seedDefaultsIfNeeded()
        let dir = Self.themesDir()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "smthemes" {
            let name = file.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "-", with: " ")
            if let theme = parseTheme(from: file) {
                themes[name.lowercased()] = theme
            }
        }
        // Always have hardcoded fallbacks for built-in names
        for (name, theme) in Self.builtinThemes() {
            if themes[name] == nil {
                themes[name] = theme
            }
        }
    }

    private func parseTheme(from url: URL) -> AppTheme? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Self.parseThemeContent(content)
    }

    static func parseThemeContent(_ content: String) -> AppTheme? {
        var vals: [String: UInt32] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces).lowercased()
            let hex = String(parts[1]).trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "#", with: "")
            guard let val = UInt32(hex, radix: 16) else { continue }
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
        let dir = Self.themesDir()
        let fm = FileManager.default
        // Check if any .smthemes files exist
        if let existing = try? fm.contentsOfDirectory(atPath: dir.path),
           existing.contains(where: { $0.hasSuffix(".smthemes") }) {
            return
        }
        for (name, theme) in Self.builtinThemes() {
            let filename = name.replacingOccurrences(of: " ", with: "-") + ".smthemes"
            let file = dir.appendingPathComponent(filename)
            let content = """
            # \(name.capitalized)
            background=\(hex(theme.background))
            focused=\(hex(theme.focused))
            text=\(hex(theme.text))
            dropTarget=\(hex(theme.dropTarget))
            cellBg=\(hex(theme.cellBg))
            cellBgFocused=\(hex(theme.cellBgFocused))
            rect1=\(hex(theme.rect1))
            rect2=\(hex(theme.rect2))
            rect3=\(hex(theme.rect3))
            """
            try? content.write(to: file, atomically: true, encoding: .utf8)
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

    func hex(_ value: UInt32) -> String {
        let s = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 6 - s.count)) + s
    }
}
