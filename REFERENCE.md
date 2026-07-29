# Spacemap Reference

## Quick Commands

| Command | Description |
|---------|-------------|
| `make run` | Build, install, and launch the app |
| `make dev1` | Uninstall the app (use before code changes) |
| `make dev2` | Reinstall and launch after code changes |
| `make build` | Build release binary only |
| `make app` | Build and assemble .app bundle |
| `make clean` | Remove build artifacts |
| `make config` | Create default config file if missing |
| `make distconfig` | Overwrite config with defaults |
| `make dmg` | Build DMG installer (universal) |
| `make dmg-arm64` | Build ARM64 DMG |
| `make dmg-x86_64` | Build Intel DMG |
| `make dmg-universal` | Build universal DMG |
| `make test` | Run unit tests via swift test |
| `make release RELEASE=x.y.z` | Bump version, commit, tag, push (triggers release) |
| `make install-cli` | Install CLI symlink to `/usr/local/bin/spacemap` |
| `make uninstall-cli` | Remove CLI symlink |
| `make permissions` | Show instructions for fixing Accessibility permission |

## CLI Usage (after `make install-cli`)

| Command | Description |
|---------|-------------|
| `spacemap --version` | Print version and exit |
| `spacemap --help` | Print help and exit |
| `spacemap --config` | Open config file in default editor and exit |
| `spacemap --trigger` | Toggle HUD visibility and exit |
| `spacemap --space <selector>` | Focus a yabai space and show the HUD; accepts 1–16, `prev`, `next`, `first`, `last`, `recent`, `mouse`, or a label |
| `spacemap --show-menu` | Show menu bar dropdown (app continues running) |
| `spacemap --settings` | Open settings window directly (app continues running) |

## Key File Locations

| File | Purpose |
|------|---------|
| `~/.config/spacemap/config.toml` | User configuration (reloads on HUD open; Settings applies hotkeys immediately) |
| `/Applications/Spacemap.app` | Installed application bundle |
| `/usr/local/bin/spacemap` | CLI symlink (if installed) |
| `/tmp/spacemap_<username>.socket` | Unix domain socket for yabai signals |
| `Console.app` | View logs (filter by "spacemap") |

## Config Keys Reference

| Key | Default | Description |
|-----|---------|-------------|
| `GRID_COLS` | 8 | Grid columns |
| `GRID_ROWS` | 2 | Grid rows |
| `CELL_STYLE` | rects | `rects`, `icons`, `thumbnails`, or `simple` |
| `HOTKEY` | ctrl+space | Toggle hotkey (requires restart) |
| `PINNED_HOTKEY` | none | Optional persistent-HUD toggle |
| `UI_SCALE` | 0.5 | HUD scale (0.0–1.0) |
| `THEME` | default | Color theme |
| `AUTO_HIDE_TIMEOUT` | 5 | Seconds before HUD hides (0=never) |
| `SHOW_MODE` | all | `all` or `active` spaces |
| `MULTI_MONITOR_HUD_MODE` | unified | `unified` (one grid) or `separate` (one grid per display) |
| `UNIFIED_HUD_VISIBILITY` | active | In `unified` mode: `all` displays the same grid on every display; `active` displays it only on the focused-space display |
| `SEPARATE_HUD_VISIBILITY` | all | In `separate` mode: `all` displays every HUD; `active` displays only the focused-space HUD |
| `DISPLAY_NAVIGATION_WRAP` | within | With arrow/Vim navigation: `within` stays on one display; `between` wraps across displays |
| `MAX_SPACES` | 16 | Max spaces to display (1–16) |
| `BACKGROUND_ALPHA` | 0.3 | Background transparency (0=transparent, 1=opaque) |
| `MODE` | auto | `light`, `dark`, or `auto` |
| `ICON_SCALE` | 0.5 | Icon size (0.0–1.0) |
| `SHOW_SPACE_NUMBERS` | true | Show space numbers in cells |
| `SHOW_SPACE_NAMES` | true | Show custom space names |
| `SHOW_ICON_STRIP` | true | Show app icon strip in cells |
| `SHOW_MULTI_APP_ICONS` | false | Show one icon per window (true) or per app (false) |
| `HIDE_MENUBAR_ICON` | false | Hide menubar icon |
| `VIM_KEYS` | false | Navigate spaces with hjkl when HUD is visible |
| `ARROW_KEYS` | false | Navigate spaces with arrow keys when HUD is visible |
| `FOCUS_SPACE_ON_WINDOW_DROP` | false | Focus the destination after a successful window drop |
| `SPACE_NAMES` | "" | Custom names: `1:Name,2:Name` |
| `SOCKET_HEALTH_INTERVAL` | 60 | Health check interval (seconds) |

## Development Workflow

1. `make dev1` (uninstalls app)
2. Remove Spacemap from System Settings → Privacy & Security → Accessibility
3. Make code changes
4. `make dev2` (rebuilds, reinstalls, launches)
5. Grant Accessibility permission when prompted

## Core Data Structures (`Models.swift`)

### `GridConfig`
Stores parsed configuration values.

| Property | Type | Source Config Key |
|----------|------|-------------------|
| `cols` | `Int` | `GRID_COLS` |
| `rows` | `Int` | `GRID_ROWS` |
| `cellStyle` | `CellStyle` | `CELL_STYLE` |
| `hotkey` | `HotkeyConfig` | `HOTKEY` |
| `pinnedHotkey` | `HotkeyConfig` | `PINNED_HOTKEY` |
| `uiScale` | `Double` | `UI_SCALE` |
| `theme` | `String` | `THEME` |
| `autoHideTimeout` | `Int` | `AUTO_HIDE_TIMEOUT` |
| `showMode` | `ShowMode` | `SHOW_MODE` |
| `multiMonitorHUDMode` | `MultiMonitorHUDMode` | `MULTI_MONITOR_HUD_MODE` |
| `unifiedHUDVisibility` | `SeparateHUDVisibility` | `UNIFIED_HUD_VISIBILITY` |
| `separateHUDVisibility` | `SeparateHUDVisibility` | `SEPARATE_HUD_VISIBILITY` |
| `displayNavigationWrap` | `DisplayNavigationWrap` | `DISPLAY_NAVIGATION_WRAP` |
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
| `focusSpaceOnWindowDrop` | `Bool` | `FOCUS_SPACE_ON_WINDOW_DROP` |

## Settings Categories

The Settings window keeps a permanent 180-point sidebar and renders one independent detail form at a time.

| Category | Scope |
|----------|-------|
| Grid | Layout, multi-monitor behavior, cell style, and visible window metadata |
| Space Names | Name visibility and per-space values |
| Appearance | Theme, appearance mode, transparency, and scale |
| Behavior | Normal and pinned hotkeys, HUD placement, timeout, navigation, drop focus, menu bar, and updates |
| Debug/Advanced | Socket health interval |

Sidebar rows are full-width buttons. The selected row is highlighted and exposed to accessibility as selected; there is no sidebar-collapse control.

### Enums

- **`CellStyle`** — `.rects`, `.icons`, `.thumbnails`, `.simple`
- **`ShowMode`** — `.all`, `.active`
- **`ThemeMode`** — `.light`, `.dark`, `.auto`

### `YabaiSpace`
`id` (Int), `label` (String), `index` (Int), `display` (Int), `windows` ([Int]), `hasFocus` (Bool)

### `YabaiWindow`
`id` (Int), `app` (String), `frame` (CGRect), `space` (Int), `isHidden` (Bool), `isMinimized` (Bool)

### `GridState`
`config` (GridConfig), `spaces` ([YabaiSpace]), `windows` ([YabaiWindow]), `displayBounds` (CGRect), `focusedIndex` (Int?)

### `AppTheme`
`name` (String), `background` (UInt64), `focused` (UInt64), `text` (UInt64), `dropTarget` (UInt64), `cellBg` (UInt64), `cellBgFocused` (UInt64)

## Key Classes

| File | Key Types | Responsibility |
|------|-----------|----------------|
| `App.swift` | `spacemapApp` | Entry point, menubar, settings window, launch checks |
| `HUDWindowController.swift` | `HUDWindowController` | NSPanel lifecycle, show/hide, auto-hide timer, state refresh |
| `GridView.swift` | `GridView` | SwiftUI grid container, cell layout, theme |
| `CellView.swift` | `CellView` | Per-cell rendering (rects/icons/thumbnails), space names |
| `YabaiClient.swift` | `YabaiClient` | yabai CLI wrapper, space/window queries, signal management |
| `ConfigReader.swift` | `ConfigReader` | Config parsing with inline comments, SPACE_NAMES support |
| `HotkeyMonitor.swift` | `HotkeyMonitor` | Global CGEventTap for hotkey capture |
| `SocketListener.swift` | `SocketListener` | Unix domain socket server for yabai signals |
| `WindowDragHandler.swift` | `WindowDragHandler` | Drag-and-drop detection via CGEventTap |
| `Models.swift` | `GridConfig`, `YabaiSpace`, etc. | Data structures |
| `SettingsView.swift` | `SettingsView` | Permanent category sidebar with separate live-save detail forms |
| `SettingsWindowController.swift` | `SettingsWindowController` | AppKit window wrapper for SettingsView |
| `ThumbnailCache.swift` | `ThumbnailCache` | ScreenCaptureKit capture, per-space caching (macOS 14+) |
| `IconCache.swift` | `IconCache` | App icon cache to avoid repeated NSWorkspace lookups |

## Yabai Integration (`YabaiClient.swift`)

Shells out to yabai binary (auto-detected: `/opt/homebrew/bin/yabai` for ARM, `/usr/local/bin/yabai` for Intel).

- `querySpaces() -> [YabaiSpace]`
- `queryWindows() -> [YabaiWindow]`
- `buildGridState(config:focusedIndex:) -> GridState`
- `focusSpace(_ index: Int)` — switches to a space
- `moveWindowCreatingSpacesIfNeeded(_:toSpace:focusDestination:completion:)` — creates missing spaces, moves the window, and optionally focuses the destination
- `queryFocusedSpaceIndex() -> Int?`
- `queryFocusedWindow() -> Int?`
- `isYabaiRunning() -> Bool`
- `registerSignals(socketPath:)` — registers yabai signals
- `removeSignals()` — unregisters yabai signals

## HUD Window (`HUDWindowController.swift`)

- `show()` — fetches data, builds grid, displays HUD, starts auto-hide timer
- `hide()` — hides HUD, stops timers
- `toggle()` — toggles visibility (guarded by `isToggling` to prevent rapid-press)
- `refresh()` — re-fetches data and re-renders grid (space_changed signal handler)
- `reloadConfig()` — clears cached config, forces re-read on next access

## Event Systems

### `HotkeyMonitor.swift`
- `CGEvent.tapCreate` with `.headInsertEventTap`
- Monitors key-down events matching configured hotkey
- Calls `HUDWindowController.toggle()` on match
- Polls every 2s until Accessibility permission granted

### `SocketListener.swift`
- Unix domain server at `/tmp/spacemap_<username>.socket`
- Listens for yabai signal commands: `0` (refresh), `1` (show), `2` (hide), `3` (settings)
- Periodic health check via `fcntl(fd, F_GETFD)` + file existence

### `WindowDragHandler.swift`
- Second CGEventTap (listenOnly, tailAppend)
- Tracks mouse drag events while HUD visible
- Identifies frontmost window via `NSWorkspace.shared.frontmostApplication`
- Correlates mouse position with cell hit-rectangles

## Theme System

Each theme defines 6 hex colors in `AppTheme`. Edit `.smthemes` files in `~/.config/spacemap/themes/`.

Available themes: `default`, `tokyonight`, `catppuccin`, `monokai-dark`, `monokai-light`, `dracula`, `ayu`, `github`, `vscode`, `xcode`, `nord`, `atom-one-dark`

## Signal Integration

- Commands: `0`=refresh, `1`=show, `2`=hide, `3`=settings
- yabai emits `spacemap_space_changed:1` via signal on space change

## UI Scaling

- `UI_SCALE` range: 0.0–1.0
- Effective scale mapping: `0.5 + uiScale * 3.5` (0→0.5x, 1→4.0x)
- `ICON_SCALE` range: 0.0–1.0
- Effective icon scale: `0.2 + iconScale * 0.8` (0→0.2x, 1→1.0x)
