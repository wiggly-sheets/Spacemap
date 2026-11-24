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
- **theme** — a `.smthemes` or `.toml` file that defines colors for the grid and strip (background, focused, text, drop-target, cell backgrounds). Editable in Settings, which saves TOML. _Avoid:_ ThemeManager (the old singleton; `ThemeStore` owns the themes, `ThemeCodec` parses and renders them).
- **config** — `~/.config/spacemap/config.toml`; governs grid dimensions, cell style, hotkey, behavior, and appearance.
- **SpacemapConfig** — the whole-app configuration value: grid, appearance, behavior, advanced, glyph strip, hotkeys, and space names. _Avoid:_ GridConfig (name predates scope growth; it holds the whole app config, not only the grid).
- **hotkey** — a global CGEventTap binding (keyCode + modifiers, fn preserved) that toggles the HUD; the glyph-strip hotkey is session-only and never persisted.
- **HUDCommand** — one configurable HUD key action (move, jump, create, delete, cycle layout), matched from a binding and executed through a single entry point. _Avoid:_ HUDKeyAction, InputAction (merged into HUDCommand).
- **glyph strip** — the always-visible menu-bar strip showing each space's index plus a glyph per window; theme-driven, notch-aware (`leftOfNotch`/`rightOfNotch`/`center`/`custom`).
- **segment** — one strip slot for a single space: its number, glyphs, and hit area. _Avoid:_ cell (that is a HUD grid slot).
- **SegmentLayout** — the complete geometry value the strip model emits for one render: slot frames, run frames, and the drag window mapping. Drawing and hit-testing read it instead of re-deriving frames.
- **space-name profile** — a named set of space names with an active index, switchable from Settings or the menu bar.
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
| `GridLayout` | `Sources/spacemap/GridLayout.swift` | Static geometry: cell size, gap, padding, ideal size, slot frames, hit-test, window→cell transforms (guarded inputs) |
| `YabaiClient` | `Sources/spacemap/YabaiClientImpl.swift` + `YabaiService.swift` | `querySpaces()`, `queryWindows()`, `buildGridState()`, `focusSpace()`, `moveWindowCreatingSpacesIfNeeded()` (10s timeout, async pipe drain) |
| `HUDWindowController` | `Sources/spacemap/HUDWindowController.swift` + `HUDInput`/`HUDDisplay`/`GridStateCoordinator` | `show()`, `hide()`, `toggle()`, `refresh()`, `reloadConfig()` |
| `Config` | `Sources/spacemap/ConfigStore.swift` + `ConfigLoader`/`TOMLConfigCodec` + `ConfigSchema` | `load()`, `saveConfig()`, `updateConfig()`, `parseConfig()` (one key table drives decode, repair, and encode; invalid fields self-heal after `.bak`) |
| `SocketListener` | `Sources/spacemap/SocketListener.swift` | Callback closures: `onRefresh`, `onShow`, `onToggle`, `onSettings` (socket mode 0600) |
| `HotkeyMonitor` | `Sources/spacemap/HotkeyMonitor.swift` + `HotkeyService`/`HotkeyHandler` | `start()`, `stop()`, `onTrigger` closure (normal/pinned/glyph-strip bindings; fn preserved) |
| `WindowDragHandler` | `Sources/spacemap/WindowDragHandler.swift` | `onHoverCell`, `onDropInCell` closures; `cellFrames`, `cachedWindows` |
| `SpaceNavigator` | `Sources/spacemap/SpaceNavigator.swift` | Pure computation: `destination(...)`, `destinationAcrossDisplays(...)` |
| `GridStateCoordinator` | `Sources/spacemap/GridStateCoordinator.swift` | Single-writer state machine: `fetch(completion:)`, `refresh(completion:)`, `updateFocusedIndex(_:)`, `latestState`, `phase` |
| `GlyphStrip` | `Sources/spacemap/GlyphStrip.swift` (pure) + `GlyphStripPanel*.swift`, `GlyphStrip*View.swift` (AppKit) | `segments(for:options:font:)`, `layout(...)` → `SegmentLayout`, `frame(...)`, `hoverFill(...)`, `command(...)`; panel `update(config:)`, `refresh()`, `toggleVisibilityByHotkey()` (session-only) |
| `Hotkey` | `Sources/spacemap/Hotkey.swift` | Parse/format round-trip, key-code and media-key tables |
| `ThemeStore` | `Sources/spacemap/ThemeStore.swift` + `ThemeCodec.swift` | `reload()`, `reloadIfChanged()`, `named(_:)`, `allNames()`, `save(theme:name:)`, `resolvedThemeName(strip:hudTheme:)`; directory injected, bundled themes fill gaps, `.smthemes`/`.toml` read, TOML written |
