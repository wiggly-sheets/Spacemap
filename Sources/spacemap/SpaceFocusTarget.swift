import Foundation

struct SpaceFocusTarget: Equatable {
    static let namedSelectors: Set<String> = [
        "prev", "next", "first", "last", "recent", "mouse"
    ]

    let value: String

    init?(argument: String) {
        let value = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("-") else { return nil }

        if let index = Int(value) {
            guard (1...16).contains(index) else { return nil }
            self.value = String(index)
            return
        }

        let lowercased = value.lowercased()
        self.value = Self.namedSelectors.contains(lowercased) ? lowercased : value
    }
}
