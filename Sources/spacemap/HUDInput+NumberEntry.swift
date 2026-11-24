import AppKit
import CoreGraphics

extension HUDInput {
    func handleNumberEntry(_ number: Int) {
        // One typed readout at a time: a digit ends any letter prefix.
        if !pendingLetters.isEmpty { clearLetterEntry() }
        let indices = currentState?.spaces.map(\.index) ?? []
        pendingNumber = Self.appendedNumber("\(number)", to: pendingNumber, indices: indices)
        numberEntryTimer?.invalidate()
        numberEntryGeneration += 1
        guard let outcome = Self.numberOutcome(pending: pendingNumber, indices: indices) else { return }
        onNumberEntry?(HUDNumberFeedback(number: outcome.number, exists: outcome.exists))
        // A prefix that can only be one space resolves now; waiting is only
        // needed while a longer number is still possible.
        guard !outcome.mustWait else {
            numberEntryTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.processPendingNumber()
            }
            return
        }
        processPendingNumber()
    }

    /// Appends a digit only while the result is still a number that exists or
    /// the start of a longer one. A repeated digit therefore replaces the
    /// previous entry instead of showing "44" for two presses of 4.
    static func appendedNumber(_ digit: String, to pending: String, indices: [Int]) -> String {
        let candidate = pending + digit
        if indices.contains(where: { String($0) == candidate || String($0).hasPrefix(candidate) }) {
            return candidate
        }
        return digit
    }

    /// Typed digits against the spaces that exist. `mustWait` is true while a
    /// longer space number could still share this prefix.
    static func numberOutcome(
        pending: String,
        indices: [Int]
    ) -> (number: Int, exists: Bool, mustWait: Bool)? {
        guard let number = Int(pending) else { return nil }
        let possible = indices.filter { String($0).hasPrefix(pending) }
        return (number, indices.contains(number), possible != [number])
    }

    func processPendingNumber() {
        let enteredNumber = pendingNumber
        numberEntryTimer?.invalidate()
        numberEntryTimer = nil
        pendingNumber = ""
        numberEntryGeneration += 1
        guard let target = Int(enteredNumber) else {
            onNumberEntry?(nil)
            return
        }
        let exists = currentState?.spaces.contains(where: { $0.index == target }) == true
        // Hold the number briefly either way so a valid jump still gives
        // feedback; invalid numbers hold a little longer. The generation stops
        // an old hold from erasing a newer entry.
        onNumberEntry?(HUDNumberFeedback(number: target, exists: exists))
        let generation = numberEntryGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + (exists ? 0.4 : 0.6)) { [weak self] in
            guard let self, self.numberEntryGeneration == generation else { return }
            self.onNumberEntry?(nil)
        }
        guard exists else { return }
        NSLog("spacemap/HUD: jump to space \(target)")
        focus(space: target)
    }

    func clearNumberEntry() {
        numberEntryTimer?.invalidate()
        numberEntryTimer = nil
        pendingNumber = ""
        numberEntryGeneration += 1
        onNumberEntry?(nil)
    }
}
