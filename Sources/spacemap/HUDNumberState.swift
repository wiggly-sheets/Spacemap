import SwiftUI
import Combine

/// What the HUD shows for a typed space number. `exists` drives the styling;
/// one value at a time replaces the previous one, so rapid key presses never
/// stack overlays.
struct HUDNumberFeedback: Equatable {
    let number: Int
    let exists: Bool
}

/// What the HUD shows for typed letters. `matches` is false when no space name
/// matches the prefix, so the overlay can mark the miss like a missing space
/// number.
struct HUDTypedFeedback: Equatable {
    let text: String
    let matches: Bool
}

/// Small observable so a key press repaints only the number overlay. The grid
/// body is not re-rendered, and no state fetch is needed to show a digit.
final class HUDNumberState: ObservableObject {
    @Published private(set) var feedback: HUDNumberFeedback?
    /// Typed letters for a fuzzy space-name jump. Shares this observable so the
    /// one overlay host repaints without a grid render.
    @Published private(set) var typedText: HUDTypedFeedback?
    private var clearWork: DispatchWorkItem?

    /// Shows `feedback`, or clears when nil. Invalid numbers can ask for a
    /// short hold so the user sees the miss before it disappears. One typed
    /// readout at a time: a digit also ends a held letter readout.
    func update(_ feedback: HUDNumberFeedback?, clearAfter delay: TimeInterval? = nil) {
        clearWork?.cancel()
        clearWork = nil
        self.feedback = feedback
        if feedback != nil { typedText = nil }
        guard feedback != nil, let delay else { return }
        let work = DispatchWorkItem { [weak self] in self?.feedback = nil }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Shows typed letters, or clears when nil. Holds are scheduled by the
    /// caller, exactly like number entry. A letter also ends a held digit.
    func updateTypedText(_ feedback: HUDTypedFeedback?) {
        if feedback != nil {
            clearWork?.cancel()
            clearWork = nil
            self.feedback = nil
        }
        typedText = feedback
    }
}

/// Large typed-number readout. Exists draws in the theme text colour; a space
/// that does not exist draws in the drop-target colour with a strike so the
/// miss is obvious. Typed letters for a fuzzy jump reuse this overlay, smaller.
struct HUDNumberOverlay: View {
    @ObservedObject var state: HUDNumberState
    let theme: AppTheme
    var fontName: String = ""
    var overrideColor: Color? = nil

    var body: some View {
        if let typed = state.typedText {
            Text(typed.text)
                .font(HUDFont.font(name: fontName, size: 44, weight: .semibold))
                .foregroundStyle(
                    (typed.matches ? (overrideColor ?? Color(hex: theme.text)) : Color(hex: theme.dropTarget))
                        .opacity(typed.matches ? 0.9 : 0.8)
                )
                .strikethrough(!typed.matches, color: Color(hex: theme.dropTarget))
                .allowsHitTesting(false)
        } else if let feedback = state.feedback {
            Text("\(feedback.number)")
                .font(HUDFont.font(name: fontName, size: 96, weight: .bold))
                .foregroundStyle(
                    (feedback.exists ? (overrideColor ?? Color(hex: theme.text)) : Color(hex: theme.dropTarget))
                        .opacity(feedback.exists ? 0.9 : 0.8)
                )
                .strikethrough(!feedback.exists, color: Color(hex: theme.dropTarget))
                .allowsHitTesting(false)
        }
    }
}

/// One short message about a completed hotkey action. A new message replaces
/// the old one; the timer is cancelled so two actions never fight.
final class HUDNoticeState: ObservableObject {
    @Published private(set) var text: String?
    private var clearWork: DispatchWorkItem?

    func show(_ text: String, clearAfter delay: TimeInterval = 0.9) {
        clearWork?.cancel()
        self.text = text
        let work = DispatchWorkItem { [weak self] in self?.text = nil }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// Bottom-centred action message, small enough not to cover the cells.
struct HUDNoticeOverlay: View {
    @ObservedObject var state: HUDNoticeState
    let theme: AppTheme
    var fontName: String = ""
    var overrideColor: Color? = nil

    var body: some View {
        if let text = state.text {
            Text(text)
                .font(HUDFont.font(name: fontName, size: 20, weight: .semibold))
                .foregroundStyle((overrideColor ?? Color(hex: theme.text)).opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .allowsHitTesting(false)
        }
    }
}
