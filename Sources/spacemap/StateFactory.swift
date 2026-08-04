import AppKit
import Foundation

/// Centralizes GridState construction transformations that were previously
/// hand-rolled at multiple sites inside HUDWindowController.
enum StateFactory {
    /// Build a new GridState carrying the same spaces/windows/displays but a
    /// different focused index. This is the single helper the coordinator uses
    /// for focus-preserving and optimistic-focus updates.
    static func state(_ state: GridState, withFocusedIndex focusedIndex: Int?) -> GridState {
        GridState(
            config: state.config,
            spaces: state.spaces,
            windows: state.windows,
            displayBounds: state.displayBounds,
            focusedIndex: focusedIndex,
            displays: state.displays
        )
    }

    /// Build a new GridState from an existing state but with a new config.
    static func state(_ state: GridState, withConfig config: GridConfig) -> GridState {
        GridState(
            config: config,
            spaces: state.spaces,
            windows: state.windows,
            displayBounds: state.displayBounds,
            focusedIndex: state.focusedIndex,
            displays: state.displays
        )
    }

    /// Build an empty GridState used while the first fetch is in flight.
    static func emptyState(config: GridConfig) -> GridState {
        GridState(
            config: config,
            spaces: [],
            windows: [],
            displayBounds: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: nil
        )
    }
}