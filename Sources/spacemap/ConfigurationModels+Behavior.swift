import Foundation
import CoreGraphics


enum ShowMode: String, CaseIterable, Identifiable, Equatable { case all, active; var id: String { rawValue } }
enum MultiMonitorHUDMode: String, CaseIterable, Identifiable, Equatable {
    case unified
    case separate

    var id: String { rawValue }

    func hudMode(for displayIndex: Int, in state: GridState) -> HUDDisplayMode {
        switch self {
        case .unified:
            return .unified
        case .separate:
            let spaces = state.spaces(forDisplay: displayIndex)
            return spaces.isEmpty ? .hidden : .separate
        }
    }
}
enum SeparateHUDVisibility: String, CaseIterable, Identifiable, Equatable {
    case all
    case active

    var id: String { rawValue }
}
enum DisplayNavigationWrap: String, CaseIterable, Identifiable, Equatable {
    case within
    case between

    var id: String { rawValue }
}
enum UpdateMode: String, CaseIterable, Identifiable, Equatable { case auto, notify, off; var id: String { rawValue } }
/// Update policy for the bundled sketchybar-app-font glyph font (distinct from
/// `UpdateMode`, which drives Sparkle app updates).
enum AppFontUpdateMode: String, CaseIterable, Identifiable, Equatable {
    case manual
    case auto

    var id: String { rawValue }
}
/// What a dragged space does when it lands on another space.
enum SpaceDropMode: String, CaseIterable, Identifiable, Equatable {
    /// Swap the windows between the two spaces. Works with any yabai build.
    case content
    /// Reorder the spaces themselves. Needs a yabai build that can move
    /// spaces on this macOS version.
    case spaces

    var id: String { rawValue }

    var label: String {
        switch self {
        case .content: return "Swap Contents"
        case .spaces: return "Move Spaces"
        }
    }
}

/// Where focus goes after a drag moves an app or rearranges spaces.
enum DragFocusMode: String, CaseIterable, Identifiable, Equatable {
    case stay
    case destination
    case source

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stay: return "Stay"
        case .destination: return "Dropped-On Space"
        case .source: return "Original Space"
        }
    }
}

enum AppPresence: String, CaseIterable, Identifiable, Equatable {
    case dock = "dock"
    case menuBar = "menuBar"
    case both = "both"
    case none = "none"

    var id: String { rawValue }

    var showsMenuBar: Bool { self == .menuBar || self == .both }
    var showsDock: Bool { self == .dock || self == .both }
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Equatable {
    case icon
    case dots
    case current
    case nearby
    case all

    var id: String { rawValue }
}
enum WindowDropFocusMode: String, CaseIterable, Identifiable, Equatable {
    case never
    case always
    case modifier

    var id: String { rawValue }

    func shouldFocus(
        eventFlags: CGEventFlags,
        requiredModifier: WindowDropFocusModifier
    ) -> Bool {
        switch self {
        case .never: return false
        case .always: return true
        case .modifier: return eventFlags.contains(requiredModifier.eventFlag)
        }
    }
}
enum WindowDropFocusModifier: String, CaseIterable, Identifiable, Equatable {
    case command
    case function = "fn"
    case option
    case control
    case shift

    var id: String { rawValue }

    var eventFlag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .function: return .maskSecondaryFn
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .shift: return .maskShift
        }
    }
}
