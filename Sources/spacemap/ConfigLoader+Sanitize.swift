import Foundation

extension ConfigLoader {
    /// Label charset allowlist: Unicode letters/numbers/marks/punctuation/
    /// symbols/space separators (emoji survive); control/format/private-use
    /// rejected. Runs post-decode — decode logic itself is untouched. Reports
    /// whether anything changed, so the caller can flag a rewrite.
    static func sanitizeLabels(_ config: SpacemapConfig) -> (config: SpacemapConfig, changed: Bool) {
        var out = config
        var changed = false
        let sanitized = Dictionary(uniqueKeysWithValues: out.spaceNames.map { ($0.key, sanitizeLabel($0.value)) })
        if sanitized != out.spaceNames { changed = true }
        out.spaceNames = sanitized

        out.spaceNameProfiles = out.spaceNameProfiles.map { profile in
            var copy = profile
            let name = sanitizeLabel(profile.name)
            if name != profile.name { changed = true }
            copy.name = name
            let spaceNames = Dictionary(uniqueKeysWithValues: profile.spaceNames.map { ($0.key, sanitizeLabel($0.value)) })
            if spaceNames != profile.spaceNames { changed = true }
            copy.spaceNames = spaceNames
            return copy
        }
        return (out, changed)
    }

    static func sanitizeLabel(_ label: String) -> String {
        // U+2028/U+2029 are line breaks to many consumers and cannot survive a
        // line-oriented config round-trip. Replace with a space rather than
        // letting them split the document; the writer also escapes them.
        let replaced = label
            .replacingOccurrences(of: "\u{2028}", with: " ")
            .replacingOccurrences(of: "\u{2029}", with: " ")
        let filtered = String(replaced.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .nonspacingMark, .spacingMark, .enclosingMark,
                 .decimalNumber, .letterNumber, .otherNumber,
                 .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                 .initialPunctuation, .finalPunctuation, .otherPunctuation,
                 .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol,
                 .spaceSeparator:
                return true
            default:
                return false
            }
        })
        return String(filtered.prefix(maxLabelChars))
    }
}
