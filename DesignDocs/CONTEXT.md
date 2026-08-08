# Spacemap — Domain Glossary

## Core domain terms

- **grid** — the 2D arrangement of yabai spaces rendered as cells in the HUD overlay.
- **cell** — one visual slot in the grid, representing a single yabai space. Sized at 80×50 base pixels, scaled by `uiScale`.
- **space** — a yabai desktop (also called a "workspace" in yabai terminology). Identified by a 1-based index.
- **display** — a physical screen. Each display has its own set of spaces.
- **HUD** — the floating NSPanel overlay that shows the grid; toggled by hotkey or CLI/deep-link trigger.
- **focus** — the currently active space (the one with keyboard focus).
- **drag-and-drop** — moving a window from one space to another by dragging it over the HUD grid.
- **thumbnail** — a live ScreenCaptureKit capture of a space's windows, shown per-cell (macOS 14+, Screen Recording permission required).
- **theme** — a `.smthemes` file that defines colors for the grid (background, focused, text, drop-target, cell backgrounds).
- **config** — `~/.config/spacemap/config.toml`; governs grid dimensions, cell style, hotkey, behavior, and appearance.
- **hotkey** — a global CGEventTap binding (keyCode + modifiers) that toggles the HUD.
- **trigger** — any entry point that causes the HUD to show or toggle (hotkey, CLI `--trigger`, deep link `spacemap://toggle-hud`, yabai `space_changed` signal).

## Architecture terms (from codebase-design glossary)

- **module** — a coherent unit with an interface and an implementation. Scale-agnostic (function, type, or slice).
- **interface** — everything a caller must know to use the module correctly (type signature, invariants, ordering, error modes).
- **depth** — leverage at the interface: more behaviour per unit of interface learned.
- **shallow** — interface nearly as complex as the implementation (pass-through).
- **seam** — a place where behaviour can be altered without editing in that place; where a module's interface lives.
- **adapter** — a concrete thing that satisfies an interface at a seam. One adapter = hypothetical seam; two = real.
- **leverage** — what callers get from depth: one implementation, N call sites.
- **locality** — what maintainers get from depth: change, bugs, knowledge concentrate in one place.

## Key modules

| Module | File(s) | Interface seam |
|---|---|---|
| `GridLayout` | `Sources/spacemap/GridLayout.swift` | Static geometry: cell size, gap, padding, ideal size, slot frames, hit-test, window→cell transforms |
| `YabaiClient` | `Sources/spacemap/YabaiClient.swift` | `querySpaces()`, `queryWindows()`, `buildGridState()`, `focusSpace()`, `moveWindowCreatingSpacesIfNeeded()` |
| `HUDWindowController` | `Sources/spacemap/HUDWindowController.swift` | `show()`, `hide()`, `toggle()`, `refresh()`, `reloadConfig()` |
| `Config` | `Sources/spacemap/Config.swift` | `load()`, `saveConfig()`, `parseConfig()`, `parseHotkey()` |
| `SocketListener` | `Sources/spacemap/SocketListener.swift` | Callback closures: `onRefresh`, `onShow`, `onToggle`, `onSettings` |
| `HotkeyMonitor` | `Sources/spacemap/HotkeyMonitor.swift` | `start()`, `stop()`, `onTrigger` closure |
| `WindowDragHandler` | `Sources/spacemap/WindowDragHandler.swift` | `onHoverCell`, `onDropInCell` closures; `cellFrames`, `cachedWindows` |
| `SpaceNavigator` | `Sources/spacemap/SpaceNavigator.swift` | Pure computation: `destination(...)`, `destinationAcrossDisplays(...)` |
| `GridStateCoordinator` | `Sources/spacemap/GridStateCoordinator.swift` | Single-writer state machine: `fetch(completion:replacingFocusedIndex:)`, `refresh(completion:)`, `updateFocusedIndex(_:)`, `latestState`, `phase` |
| `StateFactory` | `Sources/spacemap/StateFactory.swift` | `state(_:withFocusedIndex:)`, `emptyState(config:)` |
| `Hotkey` | `Sources/spacemap/Hotkey.swift` | Parse/format round-trip, key-code and media-key tables |
