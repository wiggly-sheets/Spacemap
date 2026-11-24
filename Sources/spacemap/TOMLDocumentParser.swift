import Foundation

enum TOMLDocumentParser {
    static func parse(_ text: String) -> [String: Any]? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }

        var root: [String: Any] = [:]
        var tables: [String: [String: Any]] = [:]
        var currentTable: String?

        let lines = splitPhysicalLines(text)
        var index = 0
        while index < lines.count {
            let rawLine = lines[index]
            index += 1
            guard let uncommented = stripTOMLComment(rawLine) else { return nil }
            let line = uncommented.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[") {
                guard line.hasSuffix("]"), !line.hasPrefix("[[") else { return nil }
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return nil }
                currentTable = name
                if tables[name] == nil { tables[name] = [:] }
                continue
            }

            guard let equals = firstUnquotedEquals(in: line) else { return nil }
            let rawKey = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            var rawValue = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            // Arrays may span lines. Keep folding continuation lines until the
            // brackets balance so a hand-wrapped `modifiers = [ ... ]` is not
            // treated as a fatal parse error.
            if rawValue.hasPrefix("[") {
                var depth = bracketDepth(rawValue)
                while depth > 0, index < lines.count {
                    guard let continuation = stripTOMLComment(lines[index]) else { return nil }
                    index += 1
                    let trimmed = continuation.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    rawValue += " " + trimmed
                    depth = bracketDepth(rawValue)
                }
                guard depth == 0 else { return nil }
            }
            guard let keyPath = parseTOMLKeyPath(rawKey),
                  let value = parseTOMLValue(rawValue) else { return nil }
            insert(value, keyPath: keyPath, currentTable: currentTable, root: &root, tables: &tables)
        }

        for (name, table) in tables {
            root[name] = table
        }
        return root
    }

    /// Split on line terminators (`\n`, `\r\n`, lone `\r`) but not on
    /// U+2028/U+2029: those are legal inside a quoted string and must reach
    /// the sanitizer instead of corrupting the document.
    private static func splitPhysicalLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r" }
            .map { String($0) }
    }

    /// Bracket balance outside quoted strings. A non-zero result means the
    /// array value continues onto the next line.
    private static func bracketDepth(_ raw: String) -> Int {
        var depth = 0
        var quote: Character?
        var escaping = false
        for character in raw {
            if let activeQuote = quote {
                if activeQuote == "\"", escaping {
                    escaping = false
                } else if activeQuote == "\"", character == "\\" {
                    escaping = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
            }
        }
        return depth
    }

    /// Dotted keys (`grid.cols = 8`) resolve to the same table shape as a
    /// `[grid]` section, so the decoder sees one representation.
    private static func insert(
        _ value: Any,
        keyPath: [String],
        currentTable: String?,
        root: inout [String: Any],
        tables: inout [String: [String: Any]]
    ) {
        guard let key = keyPath.last else { return }
        let prefix = Array(keyPath.dropLast())
        if let currentTable {
            if prefix.isEmpty {
                tables[currentTable, default: [:]][key] = value
            } else {
                tables[([currentTable] + prefix).joined(separator: "."), default: [:]][key] = value
            }
        } else if prefix.isEmpty {
            root[key] = value
        } else {
            tables[prefix.joined(separator: "."), default: [:]][key] = value
        }
    }
    /// Strips full-line and trailing `#` comments; `#` inside quotes is
    /// literal. Nil means unbalanced quote — fail closed, whole file rejected.
    private static func stripTOMLComment(_ line: String) -> String? {
        var quote: Character?
        var escaping = false
        for index in line.indices {
            let character = line[index]
            if let activeQuote = quote {
                if activeQuote == "\"", escaping {
                    escaping = false
                } else if activeQuote == "\"", character == "\\" {
                    escaping = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" {
                return String(line[..<index])
            }
        }
        return quote == nil ? line : nil
    }

    private static func firstUnquotedEquals(in line: String) -> String.Index? {
        var quote: Character?
        var escaping = false
        for index in line.indices {
            let character = line[index]
            if let activeQuote = quote {
                if activeQuote == "\"", escaping {
                    escaping = false
                } else if activeQuote == "\"", character == "\\" {
                    escaping = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "=" {
                return index
            }
        }
        return nil
    }

    private static func parseTOMLKey(_ raw: String) -> String? {
        if raw.hasPrefix("\""), raw.hasSuffix("\"") {
            return decodeTOMLString(raw)
        }
        if raw.hasPrefix("'"), raw.hasSuffix("'"), raw.count >= 2 {
            return String(raw.dropFirst().dropLast())
        }
        guard !raw.isEmpty, raw.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
            return nil
        }
        return raw
    }

    /// Split a dotted key into its unquoted segments: `grid.cols`,
    /// `spaceNames.names."1"`. A quoted segment may contain a literal dot.
    private static func parseTOMLKeyPath(_ raw: String) -> [String]? {
        var parts: [String] = []
        var start = raw.startIndex
        var quote: Character?
        var escaping = false
        for index in raw.indices {
            let character = raw[index]
            if let activeQuote = quote {
                if activeQuote == "\"", escaping {
                    escaping = false
                } else if activeQuote == "\"", character == "\\" {
                    escaping = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "." {
                parts.append(String(raw[start..<index]).trimmingCharacters(in: .whitespaces))
                start = raw.index(after: index)
            }
        }
        guard quote == nil else { return nil }
        parts.append(String(raw[start...]).trimmingCharacters(in: .whitespaces))
        var keys: [String] = []
        for part in parts {
            guard let key = parseTOMLKey(part) else { return nil }
            keys.append(key)
        }
        return keys.isEmpty ? nil : keys
    }

    private static func parseTOMLValue(_ raw: String) -> Any? {
        if raw.hasPrefix("\""), raw.hasSuffix("\"") {
            return decodeTOMLString(raw)
        }
        if raw.hasPrefix("'"), raw.hasSuffix("'"), raw.count >= 2 {
            return String(raw.dropFirst().dropLast())
        }
        if raw == "true" { return true }
        if raw == "false" { return false }
        if let integer = parseTOMLInteger(raw) { return integer }
        if let double = Double(raw.replacingOccurrences(of: "_", with: "")), double.isFinite {
            return double
        }
        if raw.hasPrefix("["), raw.hasSuffix("]") {
            let body = String(raw.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if body.isEmpty { return [String]() }
            guard let items = splitTOMLArray(body) else { return nil }
            var strings: [String] = []
            for item in items {
                guard let value = parseTOMLValue(item) as? String else { return nil }
                strings.append(value)
            }
            return strings
        }
        if raw.hasPrefix("{"), raw.hasSuffix("}") {
            let body = String(raw.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if body.isEmpty { return [String: Any]() }
            guard let items = splitTOMLArray(body) else { return nil }
            var table: [String: Any] = [:]
            for item in items {
                guard let equals = firstUnquotedEquals(in: item) else { return nil }
                let rawKey = String(item[..<equals]).trimmingCharacters(in: .whitespaces)
                let rawValue = String(item[item.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
                guard let keyPath = parseTOMLKeyPath(rawKey), keyPath.count == 1,
                      let value = parseTOMLValue(rawValue) else { return nil }
                table[keyPath[0]] = value
            }
            return table
        }
        return nil
    }

    /// TOML integers: optional sign, `_` separators, and `0x`/`0o`/`0b`
    /// prefixes. `Int(raw)` alone rejects every one of those beyond plain
    /// decimal.
    private static func parseTOMLInteger(_ raw: String) -> Int? {
        let compact = raw.replacingOccurrences(of: "_", with: "")
        guard !compact.isEmpty else { return nil }
        var body = compact
        var negative = false
        if body.hasPrefix("+") {
            body.removeFirst()
        } else if body.hasPrefix("-") {
            negative = true
            body.removeFirst()
        }
        let radix: Int
        if body.hasPrefix("0x") || body.hasPrefix("0X") {
            radix = 16
            body.removeFirst(2)
        } else if body.hasPrefix("0o") || body.hasPrefix("0O") {
            radix = 8
            body.removeFirst(2)
        } else if body.hasPrefix("0b") || body.hasPrefix("0B") {
            radix = 2
            body.removeFirst(2)
        } else {
            radix = 10
        }
        guard !body.isEmpty, let magnitude = Int(body, radix: radix) else { return nil }
        return negative ? -magnitude : magnitude
    }

    private static func splitTOMLArray(_ body: String) -> [String]? {
        var items: [String] = []
        var start = body.startIndex
        var quote: Character?
        var escaping = false
        var depth = 0
        for index in body.indices {
            let character = body[index]
            if let activeQuote = quote {
                if activeQuote == "\"", escaping {
                    escaping = false
                } else if activeQuote == "\"", character == "\\" {
                    escaping = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "[" || character == "{" {
                depth += 1
            } else if character == "]" || character == "}" {
                depth -= 1
            } else if character == ",", depth == 0 {
                items.append(String(body[start..<index]).trimmingCharacters(in: .whitespaces))
                start = body.index(after: index)
            }
        }
        guard quote == nil else { return nil }
        items.append(String(body[start...]).trimmingCharacters(in: .whitespaces))
        // TOML allows a trailing comma; the empty tail is not an item.
        if items.last?.isEmpty == true {
            items.removeLast()
        }
        return items.allSatisfy { !$0.isEmpty } ? items : nil
    }

    private static func decodeTOMLString(_ raw: String) -> String? {
        guard raw.count >= 2, raw.first == "\"", raw.last == "\"" else { return nil }
        let body = raw.dropFirst().dropLast()
        var result = ""
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            guard character == "\\" else {
                result.append(character)
                index = body.index(after: index)
                continue
            }
            index = body.index(after: index)
            guard index < body.endIndex else { return nil }
            switch body[index] {
            case "b": result.append("\u{08}")
            case "t": result.append("\t")
            case "n": result.append("\n")
            case "f": result.append("\u{0C}")
            case "r": result.append("\r")
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            case "u", "U":
                let digits = body[index] == "u" ? 4 : 8
                let start = body.index(after: index)
                guard let end = body.index(start, offsetBy: digits, limitedBy: body.endIndex),
                      let value = UInt32(body[start..<end], radix: 16),
                      let scalar = UnicodeScalar(value) else { return nil }
                result.unicodeScalars.append(scalar)
                index = end
                continue
            default: return nil
            }
            index = body.index(after: index)
        }
        return result
    }
}
