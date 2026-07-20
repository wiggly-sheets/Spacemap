# spacemap API Summary

## Core Data Structures (`Models.swift`)

### `GridConfig`
Stores parsed configuration values.

| Property | Type | Source Config Key |
|----------|------|-------------------|
| `cols` | `Int` | `GRID_COLS` |
| `rows` | `Int` | `GRID_ROWS` |
| `cellStyle` | `CellStyle` | `CELL_STYLE` |
| `hotkey` | `HotkeyConfig` | `HOTKEY` |
| `uiScale` | `Double` | `UI_SCALE` |
| `theme` | `String` | `THEME` |
| `autoHideTimeout` | `Int` | `AUTO_HIDE_TIMEOUT` |
| `showMode` | `ShowMode` | `SHOW_MODE` |
| `maxSpaces` | `Int` | `MAX_SPACES` |
| `bgAlpha` | `Double` | `BACKGROUND_ALPHA` |
| `mode` | `ThemeMode` | `MODE` |
| `iconScale` | `Double` | `ICON_SCALE` |
| `showSpaceNumbers` | `Bool` | `SHOW_SPACE_NUMBERS` |
| `showSpaceNames` | `Bool` | `SHOW_SPACE_NAMES` |
| `showIconStrip` | `Bool` | `SHOW_ICON_STRIP` |
| `showMultiAppIcons` | `Bool` | `SHOW_MULTI_APP_ICONS` |
| `hideMenuBarIcon` | `Bool` | `HIDE_MENUBAR_ICON` |
| `spaceNames` | `[Int: String]` | `SPACE_NAMES` |
| `socketHealthInterval` | `Int` | `SOCKET_HEALTH_INTERVAL` |

### `CellStyle` (enum)
- `.rects` — colored rectangles representing window positions/sizes
- `.icons` — app icons at window positions
- `.thumbnails` — live ScreenCaptureKit thumbnails (macOS 14+)

### `ShowMode` (enum)
- `.all` — show all spaces up to `maxSpaces`
- `.active` — show only spaces that have windows

### `ThemeMode` (enum)
- `.light`, `.dark`, `.auto`

### `HotkeyConfig`
- `keyCode` (Int) — Carbon virtual key code
- `modifiers` (UInt) — Carbon modifier mask bits

### `YabaiSpace`
Represents a yabai desktop from `yabai -m query --spaces`.

- `id` (Int), `label` (String), `index` (Int), `display` (Int), `windows` ([Int]), `hasFocus` (Bool)

### `YabaiWindow`
Represents a window from `yabai -m query --windows`.

- `id` (Int), `app` (String), `frame` (CGRect), `space` (Int), `isHidden` (Bool), `isMinimized` (Bool)
- Computed: `cgFrame` (CGRect) — parsed from frame string

### `GridState`
Assembled state for the HUD grid.

- `config` (GridConfig), `spaces` ([YabaiSpace]), `windows` ([YabaiWindow]), `displayBounds` (CGRect), `focusedIndex` (Int?)

### `AppTheme`
Color theme data for HUD rendering.

- `name` (String), `background` (UInt64), `focused` (UInt64), `text` (UInt64), `dropTarget` (UInt64), `cellBg` (UInt64), `cellBgFocused` (UInt64)

### `SpaceCell`
Individual cell in the grid.

- `space` (YabaiSpace), `row` (Int), `col` (Int), `windows` ([YabaiWindow])

## Config System (`ConfigReader.swift`)

### `ConfigReader`
Parses `~/.config/spacemap/config` key=value format (supports `#` inline comments, BOM, CR/LF).
- `load() -> GridConfig` — reads config, auto-generates if missing, self-heals missing keys
- `saveConfig(GridConfig)` — persists config back to file, preserving unused keys
- `createDefaultConfigFile()` — creates file with defaults if missing

## Yabai Integration (`YabaiClient.swift`)

### `YabaiClient`
Shells out to `/opt/homebrew/bin/yabai`.

- `querySpaces() -> [YabaiSpace]`
- `queryWindows() -> [YabaiWindow]`
- `buildGridState(config:focusedIndex:) -> GridState`
- `focusSpace(_ index: Int)` — switches to a space
- `moveWindow(_ windowId: Int, toSpace spaceIndex: Int)` — moves window
- `queryFocusedSpaceIndex() -> Int?`
- `queryFocusedWindow() -> Int?`
- `isYabaiRunning() -> Bool`
- `registerSignals(socketPath:)` — registers yabai signals
- `removeSignals()` — unregisters yabai signals

## HUD Window (`HUDWindowController.swift`)

### `HUDWindowController`
Manages the floating NSPanel overlay.

- `show()` — fetches data, builds grid, displays HUD, starts auto-hide timer
- `hide()` — hides HUD, stops timers
- `toggle()` — toggles visibility (guarded by `isToggling` to prevent rapid-press)
- `refresh()` — re-fetches data and re-renders grid (space_changed signal handler)
- `reloadConfig()` — clears cached config, forces re-read on next access
- `onShowSettings` — callback to open settings window

## Thumbnail Cache (`ThumbnailCache.swift`)

### `ThumbnailCache` (macOS 14+)
Singleton that captures and caches per-space display thumbnails via ScreenCaptureKit.

- `shared` — singleton instance
- `captureActiveSpace(spaceIndex:)` — captures active display (excluding spacemap windows), caches `CGImage` keyed by space index
- `thumbnail(forSpace index: Int) -> CGImage?` — returns cached thumbnail; `nil` if not yet visited
- `clear()` — clears all cached thumbnails

## Icon Cache (`IconCache.swift`)

### `IconCache`
Singleton that caches app icons by name to avoid repeated `NSWorkspace.shared.icon(forFile:)` calls.

- `shared` — singleton instance
- `icon(for appName: String) -> NSImage?` — returns cached icon; looks up bundle via running applications, caches on first access
- `clear()` — clears all cached icons

## UI Components

### `GridView` (SwiftUI)
Grid layout container with `LazyVGrid`, receives `GridState` and config, renders `CellView` for each space.

### `CellView` (SwiftUI)
Per-cell rendering. Supports three `CellStyle` modes:
- **rects** — scaled window rectangles colored by app name hash
- **icons** — app icons at window positions + strip at bottom (if `showIconStrip`)
- **thumbnails** — ScreenCaptureKit display thumbnail (requires macOS 14+)

Also renders: space numbers, space names, icon strip, border/fill styling.

## Event Systems

### `HotkeyMonitor.swift`
- Uses `CGEvent.tapCreate` with `.headInsertEventTap`
- Monitors key-down events matching configured hotkey
- Calls `HUDWindowController.toggle()` on match
- Polls every 2s until Accessibility permission granted

### `SocketListener.swift`
- Unix domain server at `/tmp/spacemap_<username>.socket`
- Listens for yabai signal commands: `0` (refresh), `1` (show), `2` (hide), `3` (settings)
- Routes callbacks: `onRefresh`, `onShow`, `onSettings`
- Periodic health check via `fcntl(fd, F_GETFD)` + file existence

### `WindowDragHandler.swift`
- Second CGEventTap (listenOnly, tailAppend)
- Tracks mouse drag events while HUD visible
- Identifies frontmost window via `NSWorkspace.shared.frontmostApplication`
- Correlates mouse position with cell hit-rectangles
- Calls `YabaiClient.moveWindow(_:toSpace:)` on drop

## App Lifecycle (`App.swift`)

### Launch sequence
1. Ensure CLI symlink exists (`ensureSymlink()`)
2. Handle CLI flags (`--version`, `--help`, `--config`, `--trigger`, `--show-menu`, `--settings`)
3. Set activation policy to `.prohibited` (no dock icon)
4. Check application location; prompt to move to /Applications
5. Check yabai is running; if not, show alert and exit
6. Check MRU spaces; if enabled, warn and offer to disable
7. Set up menubar icon and menu
8. Delay 1s for TCC registration, then:
   - Load config, restart hotkey, apply menubar visibility
   - Set up socket listener with `onRefresh`/`onShow`/`onSettings` callbacks
   - Register yabai signals
   - Observe settings changes notification

### Menubar items
- Show/Hide Map (with hotkey symbols)
- Open Accessibility Permissions
- Open Screen Recording Permissions
- Restart spacemap (⌘+R)
- Settings (⌘+,)
- Launch at Login (toggle with checkmark)
- Quit

## Settings Window

### `SettingsWindowController` (AppKit)
- Wraps `SettingsView` in NSHostingView inside NSWindow
- Sets activation policy to `.regular` so window receives keyboard focus

### `SettingsView` (SwiftUI)
- Grid section: max spaces, layout, show mode, cell style, space numbers, icon strip
- Appearance section: theme, background color, transparency, icon scale, UI scale
- Behavior section: hotkey recorder, socket health interval, auto-hide timeout, hide menubar icon
- Space Names section: per-space text inputs
- Live-saves on every change via `onChange` handlers
- Posts `settingsChanged` notification on save (observed by AppDelegate)

## Theme System

### Theme colors
Each theme defines 6 hex colors in `AppTheme` struct. Available themes:
`default`, `tokyonight`, `catppuccin`, `monokai-dark`, `monokai-light`, `dracula`, `ayu`, `github`, `vscode`, `xcode`, `nord`, `atom-one-dark`

Config key: `THEME=themename`

## Signal Integration

### Socket protocol
- Commands: `0`=refresh, `1`=show, `2`=hide, `3`=settings
- yabai emits `spacemap_space_changed:1` via signal on space change

### Registering in yabai config
```
space_change: emit: 'spacemap_space_changed:1'
```

## UI Scaling

- Config `UI_SCALE` range: 0.1–1.0
- Internal multiplier: `uiScale * 10`
- `UI_SCALE=0.1` → 1× size (original), `UI_SCALE=1.0` → 10× size
- Scaled values: cell size, gap, padding, fonts, icon sizes
