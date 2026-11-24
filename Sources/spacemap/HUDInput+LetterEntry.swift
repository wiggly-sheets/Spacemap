import AppKit
import CoreGraphics

extension HUDInput {
    func handleLetterEntry(_ letter: String) {
        // One typed readout at a time: a letter ends any number entry.
        if !pendingNumber.isEmpty { clearNumberEntry() }
        pendingLetters += letter
        letterEntryCount = pendingLetters.count
        evaluatePendingLetters()
    }

    func handleLetterBackspace() {
        guard !pendingLetters.isEmpty else { return }
        pendingLetters.removeLast()
        letterEntryCount = pendingLetters.count
        evaluatePendingLetters()
    }

    /// Same shape as digit entry: a prefix that only one space can match
    /// resolves at once; a prefix shared by several spaces waits 0.3s for the
    /// next letter; a prefix that matches nothing holds briefly and keeps
    /// collecting, because the user may be mid-word.
    func evaluatePendingLetters() {
        letterEntryTimer?.invalidate()
        letterEntryTimer = nil
        letterEntryGeneration += 1
        guard !pendingLetters.isEmpty else {
            onTypedText?(nil)
            return
        }
        let matches = Self.nameMatchOutcome(prefix: pendingLetters, names: spaceNames)
        onTypedText?(Self.letterFeedback(
            prefix: pendingLetters,
            matches: matches.matches,
            mustWait: matches.mustWait,
            names: spaceNames
        ))
        guard !matches.matches.isEmpty else {
            let generation = letterEntryGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.letterEntryGeneration == generation else { return }
                self.onTypedText?(nil)
            }
            return
        }
        guard matches.mustWait else {
            processPendingLetters()
            return
        }
        letterEntryTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.processPendingLetters()
        }
    }

    func processPendingLetters() {
        let entered = pendingLetters
        letterEntryTimer?.invalidate()
        letterEntryTimer = nil
        pendingLetters = ""
        letterEntryCount = 0
        letterEntryGeneration += 1
        guard !entered.isEmpty else {
            onTypedText?(nil)
            return
        }
        let outcome = Self.nameMatchOutcome(prefix: entered, names: spaceNames)
        // Only a unique best match jumps; an ambiguous prefix that timed out
        // just ends the entry rather than guessing a space.
        let target = outcome.mustWait ? nil : outcome.matches.first
        // Hold the typed text either way; the generation stops an old hold from
        // erasing a newer entry. Same hold rule as a typed number.
        let generation = letterEntryGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + (target == nil ? 0.6 : 0.4)) { [weak self] in
            guard let self, self.letterEntryGeneration == generation else { return }
            self.onTypedText?(nil)
        }
        guard let target else { return }
        NSLog("spacemap/HUD: jump to named space \(target)")
        focus(space: target)
    }

    func clearLetterEntry() {
        letterEntryTimer?.invalidate()
        letterEntryTimer = nil
        pendingLetters = ""
        letterEntryCount = 0
        letterEntryGeneration += 1
        onTypedText?(nil)
    }

    /// Spaces a typed prefix selects, ranked: exact name prefixes first, then
    /// subsequence matches, each in ascending space order. Trimmed and
    /// case-insensitive; unnamed and blank names never match. `mustWait` is
    /// true while one ranked tier still holds several spaces, because a
    /// shorter prefix may then be completed by the next letter.
    static func nameMatchOutcome(prefix: String, names: [Int: String]) -> (matches: [Int], mustWait: Bool) {
        let needle = prefix.lowercased()
        guard !needle.isEmpty else { return ([], false) }
        let candidates = names
            .compactMap { index, name -> (index: Int, name: String)? in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return trimmed.isEmpty ? nil : (index, trimmed)
            }
            .sorted { $0.index < $1.index }
        let exact = candidates.filter { $0.name.hasPrefix(needle) }.map(\.index)
        let fuzzy = candidates.filter {
            !$0.name.hasPrefix(needle) && isSubsequence(needle, of: $0.name)
        }.map(\.index)
        // A single exact prefix decides the space even when subsequence matches
        // exist; only a tie inside the best tier is ambiguous.
        let topTierCount = exact.isEmpty ? fuzzy.count : exact.count
        return (exact + fuzzy, topTierCount > 1)
    }

    /// Letters appear in `needle` order inside `haystack`, not necessarily
    /// adjacent.
    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var rest = haystack[...]
        for character in needle {
            guard let position = rest.firstIndex(of: character) else { return false }
            rest = rest[rest.index(after: position)...]
        }
        return true
    }

    /// The typed prefix, plus the space name once the best tier is one space.
    /// `matches` keeps the prefix visibly struck while nothing can match it.
    static func letterFeedback(
        prefix: String,
        matches: [Int],
        mustWait: Bool,
        names: [Int: String]
    ) -> HUDTypedFeedback {
        guard !matches.isEmpty else { return HUDTypedFeedback(text: prefix, matches: false) }
        guard !mustWait,
              let index = matches.first,
              let name = names[index]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return HUDTypedFeedback(text: prefix, matches: true) }
        return HUDTypedFeedback(text: "\(prefix) → \(name)", matches: true)
    }
}
