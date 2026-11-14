import SwiftUI

/// Motion presets for the HUD. `natural` is a short ease, `springy` overshoots
/// slightly for space changes, `fast` gets out of the way.
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
        case .natural: return .easeInOut(duration: 0.18)
        case .springy: return .spring(response: 0.32, dampingFraction: 0.62)
        case .fast: return .easeOut(duration: 0.08)
        }
    }

    /// Panel fade in and out, in seconds.
    var fadeDuration: TimeInterval {
        switch self {
        case .natural: return 0.16
        case .springy: return 0.26
        case .fast: return 0.08
        }
    }
}
