import AppKit
import CoreGraphics

extension HUDInput {
    /// Never swallow a key the HUD does not act on. A stale or revoked tap
    /// then cannot lock out the keyboard; only HUD shortcuts are captured.
    static func shouldConsumeKeyboardEvent(
        isTrusted: Bool,
        isVisible: Bool,
        isPinned: Bool,
        type: CGEventType,
        press: HUDKeyPress
    ) -> Bool {
        guard isTrusted, isVisible else { return false }
        guard type == .keyDown else { return false }
        return press != .none
    }

    static func keyboardTapRecoveryAction(
        isTrusted: Bool,
        hasTap: Bool,
        tapIsValid: Bool,
        tapIsEnabled: Bool
    ) -> KeyboardTapRecoveryAction {
        EventTapHost.recoveryAction(
            isTrusted: isTrusted,
            hasTap: hasTap,
            tapIsValid: tapIsValid,
            tapIsEnabled: tapIsEnabled
        )
    }


    func startSettingsKeyMonitor() {
        let trusted = accessibilityTrustProvider()
        cachedAccessibilityTrusted = trusted
        guard trusted else {
            // Revoked while a tap was installed: remove it. A stale default tap
            // can sit at the head of the session stream and stall every key.
            stopSettingsKeyMonitor()
            return
        }
        eventTapHost.install(consumer: self)
    }

    func reconcileSettingsKeyMonitor() {
        handleAccessibilityState(isTrusted: accessibilityTrustProvider())
    }

    func stopSettingsKeyMonitor() {
        eventTapHost.tearDown()
    }

    func handleHUDKeyDown(_ event: CGEvent) -> HUDKeyPress {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if Self.isSettingsShortcut(keyCode: keyCode, flags: flags) {
            return .showSettings
        }
        // Legacy scalar keys were checked first, then number jumps, then the
        // `[hudKeys]` table. That order is the observable pre-merge behavior.
        if let command = hudKeys.legacyCommand(for: keyCode, flags: flags) {
            return .command(command)
        }
        if jumpToSpaceEnabled, let number = Self.numberFromKeyCode(keyCode: keyCode, flags: flags) {
            return .number(number)
        }
        if let command = hudKeys.tableCommand(for: keyCode, flags: flags) {
            return .command(command)
        }
        // Only unbound, unmodified keys reach typed letter entry.
        guard fuzzySpaceJumpEnabled else { return .none }
        let letter = Self.letterFromKeyCode(keyCode: keyCode, flags: flags)
        // Shift alone types a letter, not a binding modifier: a binding on the
        // bare key still wins, so Shift+W runs a `w` command.
        if letter != nil, Self.isShiftOnly(flags) {
            let bare = flags.subtracting(.maskShift)
            if let command = hudKeys.legacyCommand(for: keyCode, flags: bare) {
                return .command(command)
            }
            if let command = hudKeys.tableCommand(for: keyCode, flags: bare) {
                return .command(command)
            }
        }
        if let letter {
            // A held key repeats keyDown. A repeat must not grow the prefix or
            // re-fire a jump, so it is consumed as a no-op.
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return .letterRepeat
            }
            letterEntryCount += 1
            return .letter(letter)
        }
        guard letterEntryCount > 0, Self.isUnmodified(flags) else { return .none }
        if keyCode == Self.backspaceKeyCode {
            letterEntryCount = max(0, letterEntryCount - 1)
            return .letterBackspace
        }
        if keyCode == Self.escapeKeyCode {
            letterEntryCount = 0
            return .letterCancel
        }
        return .none
    }

    func dispatch(_ press: HUDKeyPress) {
        switch press {
        case .command(let command):
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // The command owns the keystroke, so it also cancels any typed
                // prefix: a pending ambiguity timer must not repaint or jump
                // after the command runs.
                clearNumberEntry()
                clearLetterEntry()
                delegate?.perform(command)
            }
        case .number(let number):
            DispatchQueue.main.async { [weak self] in
                self?.handleNumberEntry(number)
            }
        case .letter(let letter):
            DispatchQueue.main.async { [weak self] in
                self?.handleLetterEntry(letter)
            }
        case .letterBackspace:
            DispatchQueue.main.async { [weak self] in
                self?.handleLetterBackspace()
            }
        case .letterCancel:
            DispatchQueue.main.async { [weak self] in
                self?.clearLetterEntry()
            }
        case .showSettings:
            DispatchQueue.main.async { [weak self] in
                self?.onShowSettings?()
            }
        case .none, .letterRepeat:
            break
        }
    }

    static func isSettingsShortcut(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        keyCode == 43 && flags.contains(.maskCommand)
    }

    static func numberFromKeyCode(keyCode: CGKeyCode, flags: CGEventFlags) -> Int? {
        guard isUnmodified(flags) else { return nil }
        switch keyCode {
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        case 26: return 7
        case 28: return 8
        case 25: return 9
        case 29: return 0
        case 82: return 0
        case 83: return 1
        case 84: return 2
        case 85: return 3
        case 86: return 4
        case 87: return 5
        case 88: return 6
        case 89: return 7
        case 91: return 8
        case 92: return 9
        default: return nil
        }
    }

    static let backspaceKeyCode: CGKeyCode = 51
    static let escapeKeyCode: CGKeyCode = 53

    /// ⌘/ctrl/alt chords belong to the system, not to type-to-jump. Shift is
    /// allowed; letters match case-insensitively.
    static func isUnmodified(_ flags: CGEventFlags) -> Bool {
        !flags.contains(.maskControl)
            && !flags.contains(.maskCommand)
            && !flags.contains(.maskAlternate)
    }

    /// Shift on its own types a letter; a chord with a real modifier is not
    /// typed at all.
    static func isShiftOnly(_ flags: CGEventFlags) -> Bool {
        isUnmodified(flags) && flags.contains(.maskShift)
    }

    /// ANSI letter keys, matching `Hotkey`'s alphanumeric table.
    static func letterFromKeyCode(keyCode: CGKeyCode, flags: CGEventFlags) -> String? {
        guard isUnmodified(flags) else { return nil }
        switch keyCode {
        case 0: return "a"
        case 11: return "b"
        case 8: return "c"
        case 2: return "d"
        case 14: return "e"
        case 3: return "f"
        case 5: return "g"
        case 4: return "h"
        case 34: return "i"
        case 38: return "j"
        case 40: return "k"
        case 37: return "l"
        case 46: return "m"
        case 45: return "n"
        case 31: return "o"
        case 35: return "p"
        case 12: return "q"
        case 15: return "r"
        case 1: return "s"
        case 17: return "t"
        case 32: return "u"
        case 9: return "v"
        case 13: return "w"
        case 7: return "x"
        case 16: return "y"
        case 6: return "z"
        default: return nil
        }
    }
}
