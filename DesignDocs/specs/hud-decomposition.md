# HUDWindowController Decomposition

**Status:** Proposed
**Date:** 2026-08-04
**Author:** Architecture Review

## Summary

Decompose the 908-line `HUDWindowController` god object into three focused modules plus a thin coordinator. This improves testability (from 0 tests to protocol-based unit tests), locality (changes to input, display, or state each stay in their module), and leverage (each module's interface serves multiple call sites).

## Motivation

- `HUDWindowController` has 908 lines and 0 tests — the largest untested file in the codebase
- Understanding keyboard navigation requires jumping through 7 modules (HUDWindowController → navigationDirection → GridLayout.visibleSpaceIndices → SpaceNavigator.destination → YabaiClient.focusSpaceAsync → GridStateCoordinator.updateFocusedIndex → StateFactory.state)
- The coordinator reaches into `GridStateCoordinator`'s internal state (`latestState`, `pendingFocusedSpaceIndex`, `isPendingFocusValid`, `phase`, `generation`), breaking encapsulation
- The controller is a single point of failure — any change to panel management, input handling, or state synchronization risks regressions in unrelated areas

## Decomposition

### New Modules

| Module | File | Interface | Depth |
|---|---|---|---|
| `HUDInput` | `Sources/spacemap/HUDInput.swift` | `start()`, `stop()`, `handleKeyEvent(_:)` → `InputAction` | Deep: ~200 lines behind 3 methods |
| `HUDDisplay` | `Sources/spacemap/HUDDisplay.swift` | `show()`, `hide()`, `render(state:)`, `updateCellFrames(state:)` | Deep: ~250 lines behind 4 methods |
| `HUDStateSync` | `Sources/spacemap/HUDStateSync.swift` | `currentState`, `focusedIndex`, `updateFocusedIndex(_:)`, `fetch(completion:)`, `refresh(completion:)`, `clearPendingFocus()` | Deep: ~100 lines behind 6 methods |
| `HUDWindowController` | `Sources/spacemap/HUDWindowController.swift` | `show()`, `hide()`, `toggle()`, `refresh()`, `reloadConfig()` | Thin: ~150 lines, delegates to modules |

### Protocol Seams

```swift
// HUDInputDelegate
protocol HUDInputDelegate: AnyObject {
    func navigate(direction: SpaceNavigationDirection)
    func showSettings()
}

// HUDDisplayDelegate
protocol HUDDisplayDelegate: AnyObject {
    func render(state: GridState)
    func updateCellFrames(state: GridState)
    func show()
    func hide()
}

// HUDStateSync (concrete protocol, not a protocol type)
protocol HUDStateSync {
    var currentState: GridState? { get }
    var focusedIndex: Int? { get }
    func updateFocusedIndex(_ index: Int) -> GridState?
    func fetch(completion: @escaping () -> Void)
    func refresh(completion: @escaping () -> Void)
    func clearPendingFocus()
}
```

### InputAction Enum

```swift
enum InputAction {
    case navigate(direction: SpaceNavigationDirection)
    case showSettings
    case none
}
```

## Module Responsibilities

### HUDInput
- Owns the CGEventTap for keyboard input (settings shortcut, vim/arrow navigation)
- Owns the panel drag monitor (NSEvent local monitor for leftMouseDown/dragged/up)
- Parses key events into `InputAction` enum
- Reports navigation requests to delegate
- Reports settings shortcut to delegate
- Manages its own event tap lifecycle (start/stop)

### HUDDisplay
- Owns NSPanel lifecycle (creation, teardown, ordering)
- Manages unified vs separate display modes
- Computes cell frames in Quartz coordinates
- Handles panel positioning (including custom position support)
- Manages thumbnail preloading and refresh
- Manages icon preloading
- Reports visual state changes to delegate

### HUDStateSync
- Wraps `GridStateCoordinator` with a clean interface
- Exposes `currentState` (read-only mirror of coordinator's published state)
- Exposes `focusedIndex` (derived from `currentState`)
- Delegates `updateFocusedIndex(_:)` to coordinator
- Delegates `fetch(completion:)` and `refresh(completion:)` to coordinator
- Delegates `clearPendingFocus()` to coordinator
- Hides coordinator internals (`phase`, `generation`, `pendingFocusedSpaceIndex`, `isPendingFocusValid`)

### HUDWindowController (thin coordinator)
- Owns `HUDInput`, `HUDDisplay`, `HUDStateSync` instances
- Owns auto-hide timer
- Wires delegate callbacks between modules
- Owns `config` property (lazy-loaded from `Config.load()`)
- Owns `currentState` (read-only mirror of HUDStateSync)
- Owns `hoveredCell`, `lastFocusedSpaceIndex`, `isVisible`, `isPinned`, `isToggling`
- Implements `show()`, `hide()`, `toggle()`, `refresh()`, `reloadConfig()`
- Delegates input → HUDInput
- Delegates rendering → HUDDisplay
- Delegates state queries → HUDStateSync

## Implementation Order

1. **HUDStateSync** — simplest module, pure wrapper around GridStateCoordinator
2. **HUDInput** — self-contained, owns its CGEventTap
3. **HUDDisplay** — most complex, touches panels, cell frames, thumbnails
4. **Wire HUDWindowController** — replace direct coordinator access with HUDStateSync, wire delegates
5. **Delete StateFactory** — inline its 3 trivial calls into HUDStateSync/HUDWindowController
6. **Tests** — protocol-based unit tests for each module

## StateFactory Elimination

`StateFactory` (43 lines) is a shallow pass-through namespace. Its three methods will be inlined:

| Current Call | Replacement |
|---|---|
| `StateFactory.state(state, withFocusedIndex: focusedIndex)` | `GridState(config: state.config, spaces: state.spaces, windows: state.windows, displayBounds: state.displayBounds, focusedIndex: focusedIndex, displays: state.displays)` |
| `StateFactory.state(state, withConfig: config)` | `GridState(config: config, spaces: state.spaces, windows: state.windows, displayBounds: state.displayBounds, focusedIndex: state.focusedIndex, displays: state.displays)` |
| `StateFactory.emptyState(config: config)` | `GridState(config: config, spaces: [], windows: [], displayBounds: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440), focusedIndex: nil)` |

## Testing Strategy

Each module is tested through its protocol interface with mock delegates:

| Module | Test Type | Mocks |
|---|---|---|
| `HUDStateSync` | Pure unit tests | Mock `GridStateCoordinator` |
| `HUDInput` | Unit tests | Mock `HUDInputDelegate`, mock `CGEvent` |
| `HUDDisplay` | Unit tests | Mock `HUDDisplayDelegate`, mock `NSPanel` |
| `HUDWindowController` | Integration tests | Mock `HUDInputDelegate`, `HUDDisplayDelegate`, `HUDStateSync` |

## Files Changed

### New Files
- `Sources/spacemap/HUDInput.swift` — input handling module
- `Sources/spacemap/HUDDisplay.swift` — display/presentation module
- `Sources/spacemap/HUDStateSync.swift` — state synchronization module
- `Tests/spacemapTests/HUDStateSyncTests.swift` — unit tests
- `Tests/spacemapTests/HUDInputTests.swift` — unit tests
- `Tests/spacemapTests/HUDDisplayTests.swift` — unit tests
- `Tests/spacemapTests/HUDWindowControllerTests.swift` — integration tests

### Modified Files
- `Sources/spacemap/HUDWindowController.swift` — decomposed from 908 to ~150 lines
- `Sources/spacemap/StateFactory.swift` — deleted (3 calls inlined)
- `Sources/spacemap/GridStateCoordinator.swift` — minor interface cleanup (remove internal state exposure)

### Deleted Files
- `Sources/spacemap/StateFactory.swift`

## Constraints

- No external dependencies added (zero-dependency project)
- Must maintain macOS 13+ target
- Must maintain Swift 5.9 compatibility
- All existing tests must continue to pass
- No ADR conflicts (no existing ADRs in the project)

## Acceptance Criteria

1. `HUDWindowController` is under 200 lines
2. Each new module has a protocol-defined interface
3. `HUDStateSync` has no direct access to `GridStateCoordinator` internals
4. `HUDInput` produces `InputAction` enum, not direct delegate calls
5. `HUDDisplay` has no knowledge of `HUDWindowController`
6. All new modules have protocol-based unit tests
7. `HUDWindowController` integration tests cover show/hide/toggle/navigate
8. StateFactory is deleted, calls inlined
9. All existing tests continue to pass
