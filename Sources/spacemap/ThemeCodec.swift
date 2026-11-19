import Foundation

/// Pure theme text: parse a theme file, render the TOML the editor saves, and
/// format a colour as six hex digits. No state, no file access.
enum ThemeCodec {

    /// Plain key/value `.smthemes` files and TOML `.toml` files share one
    /// grammar; both are accepted so users can keep custom themes in TOML.
    /// Keys are canonical in their on-disk (lowercased) form.
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
        return AppTheme(colors: vals)
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

    static func hex(_ value: UInt32) -> String {
        let s = String(value & 0xFFFFFF, radix: 16)
        return String(repeating: "0", count: max(0, 6 - s.count)) + s
    }

    /// Editor input: every role as typed text. Nil while any field is not a hex
    /// colour, so a bad value can never be saved as black.
    static func theme(fromHexes hexes: [String: String]) -> AppTheme? {
        var values: [String: UInt32] = [:]
        for key in AppTheme.colorNames {
            guard let value = parseHexValue(hexes[key] ?? "") else { return nil }
            values[key] = value
        }
        return AppTheme(colors: values)
    }

    /// The TOML body the editor saves: quoted camelCase keys under `[colors]`,
    /// unchanged since the first release so existing files stay identical.
    static func renderTheme(_ theme: AppTheme) -> String {
        let lines = ["[colors]"] + AppTheme.colorNames.map { key in
            "\(key) = \"#\(hex(theme.value(for: key) ?? 0))\""
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
