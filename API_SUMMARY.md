# spacemap API Summary

## Core Data Structures (`Models.swift`)

### `GridConfig`
Stores parsed configuration values.

| Property | Type | Source Config Key |
|----------|------|-------------------|
| `cols` | `Int` | `GRID_COLS` |
| `rows` | `Int` | `GRID_ROWS` |
| `cellStyle` | `CellStyle` | `CELL_STYLE` |
| `hotkey` | `String` | `HOTKEY` |
| `uiScale` | `Double` | `UI_SCALE` |
| `theme` | `String` | `THEME` |
| `autoHideTimeout` | `Int` | `AUTO_HIDE_TIMEOUT` |
| `showMode` | `String` | `SHOW_MODE` |
| `maxSpaces` | `Int` | `MAX_SPACES` |
| `bgAlpha` | `Double` | `BACKGROUND_ALPHA` |
| `mode` | `String` | `MODE` |
| `iconScale` | `Double` | `ICON_SCALE` |
| `showNames` | `Bool` | `SHOW_NAMES` |
| `spaceNames` | `[Int: String]` | `SPACE_NAMES` |
| `socketHealthInterval` | `Int` | `SOCKET_HEALTH_INTERVAL` |

### `YabaiSpace`
Represents a yabai desktop from `yabai -m query --spaces`.

- `id` (Int), `label` (String), `index` (Int), `display` (Int), `windows` ([Int]), `hasFocus` (Bool)

### `YabaiWindow`
Represents a window from `yabai -m query --windows`.

- `id` (Int), `app` (String), `frame` (CGRect), `space` (Int)

### `GridState`
Assembled state for the HUD grid.

- `spaces` ([SpaceCell]) — each with position (row/col), space info, windows

### `AppTheme`
Color theme data for HUD rendering.

- `background`, `focused`, `text`, `dropTarget`, `cellBg`, `cellBgFocused` (all `UInt64` hex)

## Config System (`ConfigReader.swift`)

### `ConfigReader`
Parses `~/.config/spacemap/config` key=value format (supports `#` inline comments).
- `readConfig()` → `GridConfig`
- `loadConfig() -> GridConfig` — cached read; re-reads on HUD open (except HOTKEY cached)
- `saveConfig(GridConfig)` — persists config back to file, preserving unused keys
- `createDefaultConfigFile()` — creates file with defaults if missing

## Yabai Integration (`YabaiClient.swift`)

### `YabaiClient`
Shells out to `/opt/homebrew/bin/yabai`.

- `querySpaces() -> [YabaiSpace]`
- `queryWindows() -> [YabaiWindow]`
- `buildGridState(GridConfig) -> GridState`
- `focusSpace(spaceId: Int)` — switches to a space
- `moveWindowToSpace(windowId: Int, spaceId: Int)` — moves window
- `queryActiveDisplay() -> Int`
- `sendSignal(label: String, event: String, action: String)` — registers yabai signals

## HUD Window (`HUDWindowController.swift`)

### `HUDWindowController`
Manages the floating NSPanel overlay.

- `show(animated:)` — fetches data, builds grid, displays HUD, starts auto-hide timer
- `hide(animated:)` — hides HUD, stops timers
- `toggle()` — toggles visibility (guarded by `isToggling` to prevent rapid-press)
- `refresh()` — re-fetches data and re-renders grid (space_changed signal handler)
- `refreshState()` — updates active space state without re-creating view (live refresh timer)
- `autoHideTimer`, `refreshTimer` — timers for auto-hide and live updates

## UI Components

### `GridView` (SwiftUI)
Grid layout container with `LazyVGrid`, receives `GridState` and `AppTheme`, renders `CellView` for each space.

### `CellView` (SwiftUI)
Per-cell rendering. Supports three `CellStyle` modes:
- **rects** — scaled window rectangles colored by app name hash
- **icons** — app icons at window positions + strip at bottom
- **hybrid** — rectangles + icon strip

## Event Systems

### `HotkeyMonitor.swift`
- Uses `CGEvent.tapCreate` with `.headInsertEventTap`
- Monitors key-down events matching configured hotkey
- Calls `HUDWindowController.toggle()` on match
- Polls every 2s until Accessibility permission granted

### `SocketListener.swift`
- Unix domain server at `/tmp/spacemap_<username>.socket`
- Listens for yabai signal commands: `0` (refresh), `1` (show), `2` (hide)
- Routes callbacks: `onRefresh`, `onShow`, `onHide`, `onSettings`

### `WindowDragHandler.swift`
- Second CGEventTap (listenOnly, tailAppend)
- Tracks mouse drag events while HUD visible
- Identifies frontmost window via `NSWorkspace.shared.frontmostApplication`
- Correlates mouse position with cell hit-rectangles
- Calls `YabaiClient.moveWindowToSpace(windowId, spaceId)` on drop

## App Lifecycle (`App.swift`)

### Launch sequence
1. Check yabai is running; if not, show alert and exit
2. Set activation policy to `.prohibited` (no dock icon)
3. Create config file if missing (`ConfigReader.createDefaultConfigFile()`)
4. Create CLI symlink (`ensureSymlink()`)
5. Set up menubar icon and menu
6. Initialize hotkey monitor (`HotkeyMonitor`)
7. Initialize socket listener (`SocketListener`) with callbacks
8. Prompt for Accessibility permission if not granted
9. Prompt to move app to Applications if not already there
10. Register settings notification observer
11. Set up Settings window menu item (⌘+,)

### Menubar items
- Show/Hide Spacemap
- Launch at Login (toggle with checkmark)
- Show Space Numbers (toggle with checkmark)
- Settings (⌘+,)
- Quit

## Settings Window

### `SettingsWindowController` (AppKit)
- Wraps `SettingsView` in NSHostingView inside NSWindow
- Creates single instance, reuses on open
- `show()` → orders front

### `SettingsView` (SwiftUI)
- Form with controls for all config keys
- Live-saves on every change via `onChange` handlers
- Calls `ConfigReader.saveConfig(GridConfig)` on each change
- Posts `settingsChanged` notification on save (observed by `App.swift` for hotkey re-registration)
- Includes space name editor (list of space-name pairs)

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