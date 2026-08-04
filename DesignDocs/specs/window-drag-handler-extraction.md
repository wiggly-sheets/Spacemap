# WindowDragHandler Extraction

**Status:** Proposed
**Date:** 2026-08-04
**Author:** Architecture Review

## Summary

Extract `WindowDragHandler` behind a `WindowDragService` protocol with a `WindowDragInput` value type. The handler receives all input through its interface rather than reaching into `HUDWindowController`'s properties. This enables mocking for unit tests and separates drag-detection logic from panel management.

## Motivation

- `WindowDragHandler` is a 167-line class with zero tests
- It reaches into `HUDWindowController`'s properties (`cellFrames`, `cachedWindows`, `focusedWindowIDAtOpen`) breaking encapsulation
- The `findDraggedWindowID(atCG:)` logic and `cellSpaceIndex(forCG:)` hit-test are complex algorithms that are untestable due to direct AppKit/NSWorkspace dependencies
- Understanding drag-to-move requires jumping through `HUDWindowController → WindowDragHandler.handleMouseDown/handleDrag/handleMouseUp → findDraggedWindowID → NSWorkspace → YabaiClient`
- The handler's closures (`onHoverCell`, `onDropInCell`) are set in `HUDWindowController.init` and capture `self`, creating tight coupling

## Decomposition

### New Modules

| Module | File | Interface | Depth |
|---|---|---|---|
| `WindowDragService` | `Sources/spacemap/WindowDragService.swift` | Protocol: lifecycle, callbacks, DragState | Interface only |
| `WindowDragHandler` | `Sources/spacemap/WindowDragHandler.swift` | Conforms to WindowDragService | Deep: ~170 lines behind protocol |
| `WindowDragInput` | `Sources/spacemap/WindowDragInput.swift` | Value type with all input data | Pure data |

### WindowDragInput Value Type

```swift
struct WindowDragInput {
    var cellFrames: [(spaceIndex: Int, frame: CGRect)]
    var cachedWindows: [YabaiWindow]
    var focusedWindowIDAtOpen: Int?
}
```

### WindowDragService Protocol

```swift
protocol WindowDragService {
    var onHoverCell: ((Int?) -> Void)? { get set }
    var onDropInCell: ((Int, Int, CGEventFlags) -> Void)? { get set }
    var dragState: DragState { get }
    func start()
    func stop()
    func reset()
    func updateInput(_ input: WindowDragInput)
}

enum DragState: Equatable {
    case idle
    case dragging(
        isDragging: Bool,
        draggedWindowID: Int?,
        lastHoveredCell: Int?,
        frontmostAppAtMouseDown: String?
    )
}
```

### WindowDragHandler Implementation

- Moves CGEventTap management, hit-testing, and window identification logic from `HUDWindowController`
- Receives input via `updateInput(_:)` instead of reaching into controller properties
- Produces `DragState` as a read-only property for consumers to observe
- Retains all existing drag-detection logic (no behavioral changes)

## Implementation Order

1. **WindowDragInput** — pure value type, no dependencies
2. **DragState** — pure enum, no dependencies
3. **WindowDragService protocol** — defines the interface
4. **WindowDragHandler** — implements the protocol, receives input via `updateInput(_:)`
5. **Update HUDWindowController** — create `WindowDragHandler` instance, call `updateInput(_:)` on refresh, observe `dragState`
6. **Tests** — protocol-based unit tests with mock service

## Testing Strategy

| Module | Test Type | Mocks |
|---|---|---|
| `WindowDragInput` | Pure unit tests | None — value type |
| `DragState` | Pure unit tests | None — enum |
| `WindowDragHandler` | Unit tests | Mock `WindowDragService` callbacks |
| `HUDWindowController` | Integration tests | Mock `WindowDragService` |

Key test scenarios:
- `cellSpaceIndex(forCG:)` returns correct space index for point in frame
- `findDraggedWindowID(atCG:)` returns focused window when multiple candidates exist
- `handleMouseDown` sets `isDragging = false` and records frontmost app
- `handleDrag` triggers `onHoverCell` callback when cell changes
- `handleMouseUp` triggers `onDropInCell` callback with windowID and spaceIndex
- `reset()` clears all drag state

## Files Changed

### New Files
- `Sources/spacemap/WindowDragService.swift` — protocol + DragState enum
- `Sources/spacemap/WindowDragInput.swift` — input value type
- `Tests/spacemapTests/WindowDragServiceTests.swift` — unit tests
- `Tests/spacemapTests/WindowDragInputTests.swift` — unit tests

### Modified Files
- `Sources/spacemap/WindowDragHandler.swift` — conforms to protocol, receives input via updateInput
- `Sources/spacemap/HUDWindowController.swift` — creates handler, calls updateInput, observes dragState

### Deleted Files
- None (WindowDragHandler.swift is refactored, not deleted)

## Constraints

- No external dependencies added (zero-dependency project)
- Must maintain macOS 13+ target
- Must maintain Swift 5.9 compatibility
- All existing tests must continue to pass
- No behavioral changes — this is a pure extraction
- No ADR conflicts (no existing ADRs in the project)

## Acceptance Criteria

1. `WindowDragHandler` conforms to `WindowDragService` protocol
2. `WindowDragInput` is a pure value type with no side effects
3. `DragState` is a read-only property on the protocol
4. `HUDWindowController` calls `updateInput(_:)` instead of setting handler properties directly
5. All drag-detection logic moves to `WindowDragHandler`
6. Protocol-based unit tests cover all callback scenarios
7. All existing tests continue to pass
8. No behavioral changes in drag-and-drop functionality
