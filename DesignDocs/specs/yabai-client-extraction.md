# YabaiClient Extraction

**Status:** In Progress
**Date:** 2026-08-04
**Author:** Architecture Review

## Summary

Extract a `YabaiService` protocol from the static `YabaiClient` enum, creating a `YabaiClientImpl` class that conforms to it. This enables mocking for unit tests, improves the seam between data fetching and state construction, and makes `GridStateCoordinator`'s dependency injection actually usable.

## Motivation

- `YabaiClient` is a 303-line static enum with no instance, no seam, and no testability through dependency injection
- `GridStateCoordinator` previously used `YabaiClient.buildGridState(config:)` as a static closure default — you could not substitute a mock without swizzling or complex workarounds
- `YabaiClientImpl` already exists with 18 tests covering 11 of 16 protocol methods, but several important methods (`queryDisplays`, `queryFocusedWindow`, `focusSpace(_ target:)`, `showSpacemap`, `moveWindowCreatingSpacesIfNeeded`, `runOnYabaiQueue`, `resetYabaiRunningCache`, `resetYabaiProcessCheck`) lack dedicated tests
- Understanding data flow requires jumping between `shell()`, `query*Raw()`, and `buildGridState()` orchestrator

## Decomposition

### New Modules

| Module | File | Interface | Depth |
|---|---|---|---|
| `YabaiService` | `Sources/spacemap/YabaiService.swift` | Protocol: 16 methods + 4 properties | Interface only |
| `YabaiClientImpl` | `Sources/spacemap/YabaiClientImpl.swift` | Conforms to YabaiService | Deep: ~334 lines behind 16 methods |
| `YabaiClient` | `Sources/spacemap/YabaiClient.swift` | Still full static implementation (not yet a facade) | Deep: ~303 lines |

### Protocol Interface (YabaiService)

```swift
protocol YabaiService {
    var yabaiProcessCheck: () -> Bool { get set }

    var windowGeometryRefreshEvents: [String] { get }
    var workspaceTopologyRefreshEvents: [String] { get }
    var workspacePreviewRefreshEvents: [String] { get }

    func runOnYabaiQueue(_ block: @escaping () -> Void)
    func runOnYabaiQueue(_ workItem: DispatchWorkItem)

    func isYabaiRunning(forceRefresh: Bool) -> Bool
    func resetYabaiRunningCache()
    func resetYabaiProcessCheck()

    func querySpaces() throws -> [YabaiSpace]
    func queryDisplays() throws -> [YabaiDisplay]
    func queryWindows() throws -> [YabaiWindow]
    func queryFocusedWindow() throws -> Int?
    func queryFocusedSpaceIndex() -> Int?

    func registerSignals(
        socketPath: String,
        showHUDOnSpaceChange: Bool,
        refreshWorkspacePreviews: Bool,
        refreshWindowGeometry: Bool
    )
    func removeSignals()

    func focusSpace(_ index: Int)
    func focusSpace(_ target: SpaceFocusTarget) -> Bool
    func focusSpaceAsync(_ index: Int)

    func showSpacemap()

    func moveWindowCreatingSpacesIfNeeded(
        _ windowID: Int,
        toSpace targetIndex: Int,
        focusDestination: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    )

    func buildGridState(config: GridConfig, focusedIndex: Int?) -> GridState
}
```

### Implementation (YabaiClientImpl)

- Moves all static methods from `YabaiClient` to instance methods on `YabaiClientImpl`
- Conforms to `YabaiService`
- Retains all existing shell execution, process checking, caching, and signal management logic
- No behavioral changes — this is a pure extraction
- Key difference from the static version: `focusSpaceAsync` uses `[weak self]` in its closure to avoid retain cycles

### Facade (YabaiClient)

**Not yet implemented.** `YabaiClient` is still the full 303-line static enum. The plan is to convert it to a deprecated facade that delegates to a shared `YabaiClientImpl` instance, maintaining backward compatibility during migration. This is the remaining work item.

## Implementation Order

1. **YabaiService protocol** — ✅ Done (`Sources/spacemap/YabaiService.swift`)
2. **YabaiClientImpl** — ✅ Done (`Sources/spacemap/YabaiClientImpl.swift`)
3. **Update callers** — ✅ Done. All consumers inject `YabaiService` via initializer
4. **Update GridStateCoordinator** — ✅ Done. Accepts `YabaiService` via initializer (no longer uses a `stateBuilder` closure)
5. **Update HUDWindowController** — ✅ Done. Injects `YabaiService` via initializer
6. **Update App.swift** — ✅ Done. Wires `YabaiClientImpl()` into the dependency graph
7. **Deprecate YabaiClient static methods** — ❌ Not done. Convert `YabaiClient` from a full static enum to a thin deprecated facade delegating to a shared `YabaiClientImpl` instance
8. **Tests** — ✅ Done. `YabaiClientImplTests.swift` (integration), `MockYabaiService.swift` (mock for consumer tests), `YabaiClientTests.swift` (static facade tests)

## Testing Strategy

| Module | Test Type | Mocks |
|---|---|---|
| `YabaiClientImpl` | Integration tests (real yabai) | None — test against real yabai |
| `YabaiService` consumers | Unit tests | Mock `YabaiService` protocol (`MockYabaiService.swift`) |
| `GridStateCoordinator` | Unit tests | Mock `YabaiService` |
| `HUDWindowController` | Unit tests | Mock `YabaiService` |
| `YabaiClient` (static facade) | Unit tests | N/A — tests the deprecated wrappers |

## Files Changed

### New Files (already created)
- `Sources/spacemap/YabaiService.swift` — protocol definition (36 lines)
- `Sources/spacemap/YabaiClientImpl.swift` — implementation (334 lines)
- `Tests/spacemapTests/YabaiClientImplTests.swift` — integration tests (225 lines)
- `Tests/spacemapTests/MockYabaiService.swift` — mock for consumer tests (189 lines)

### Modified Files (already updated)
- `Sources/spacemap/GridStateCoordinator.swift` — accepts `YabaiService` via initializer
- `Sources/spacemap/HUDWindowController.swift` — injects `YabaiService` via initializer
- `Sources/spacemap/App.swift` — wires `YabaiClientImpl` into dependency graph
- `Sources/spacemap/WindowDragHandler.swift` — injects `YabaiService` via initializer
- `Sources/spacemap/HUDDisplay.swift` — injects `YabaiService` via initializer
- `Sources/spacemap/CLI.swift` — injects `YabaiService` via initializer
- `Sources/spacemap/SettingsView.swift` — injects `YabaiService` via initializer
- `Sources/spacemap/SettingsWindowController.swift` — creates `YabaiClientImpl()` for settings view

### Remaining Work
- `Sources/spacemap/YabaiClient.swift` — convert from full static enum to deprecated facade delegating to shared `YabaiClientImpl` instance

### Deleted Files
- None

## Constraints

- No external dependencies added (zero-dependency project)
- Must maintain macOS 13+ target
- Must maintain Swift 5.9 compatibility
- All existing tests must continue to pass
- Backward compatibility: `YabaiClient` static methods must work during migration period
- No ADR conflicts (no existing ADRs in the project)

## Acceptance Criteria

1. `YabaiService` protocol defines all 16 methods + 4 properties
2. `YabaiClientImpl` conforms to `YabaiService` with zero behavioral changes from the original static methods
3. `GridStateCoordinator` accepts `YabaiService` via initializer
4. `HUDWindowController` accepts `YabaiService` via initializer
5. All consumer files inject `YabaiService` via initializer
6. `YabaiClient` static methods are deprecated wrappers delegating to a shared `YabaiClientImpl` instance
7. All new modules have protocol-based unit tests with mocks
8. All existing tests continue to pass
9. No static methods remain in the core implementation path (`YabaiClientImpl` is instance-based)
