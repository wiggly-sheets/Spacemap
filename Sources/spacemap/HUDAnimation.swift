import SwiftUI

/// Motion presets for the HUD. `natural` is a calm ease, `springy` overshoots
/// and settles for space changes, `fast` gets out of the way.
enum HUDAnimationStyle: String, CaseIterable, Identifiable, Equatable {
    case natural
    case springy
    case fast

    var id: String { rawValue }

    var label: String {
        switch self {
        case .natural: return "Natural"
        case .springy: return "Springy"
        case .fast: return "Fast"
        }
    }

    /// Drives SwiftUI state changes: cell focus, add, delete.
    var animation: Animation {
        switch self {
        case .natural: return .easeInOut(duration: 0.32)
        case .springy: return .spring(response: 0.45, dampingFraction: 0.42)
        case .fast: return .easeOut(duration: 0.08)
        }
    }

    /// Panel fade and slide duration, in seconds. Matches `animation`.
    var fadeDuration: TimeInterval {
        switch self {
        case .natural: return 0.28
        case .springy: return 0.42
        case .fast: return 0.08
        }
    }
}


/// How the HUD panel arrives and leaves. Kept separate from timing so a fast
/// fade and a slow slide can share the same motion scale.
enum HUDEntranceStyle: String, CaseIterable, Identifiable, Equatable {
    case fade
    case slideFromLeft
    case slideFromRight
    case slideFromTop
    case slideFromBottom
    case scale

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fade: return "Fade"
        case .slideFromLeft: return "Slide from Left"
        case .slideFromRight: return "Slide from Right"
        case .slideFromTop: return "Slide from Top"
        case .slideFromBottom: return "Slide from Bottom"
        case .scale: return "Scale"
        }
    }
}
