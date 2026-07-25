# Spacemap - Developer Guide

Technical deep-dive, debugging, and configuration details for contributors.

## Core Architecture

### Data Flow
1. **App launches** → `App.swift` checks yabai, sets up menubar, hotkey monitor, socket listener
2. **Hotkey pressed** → `HUDWindowController.show()` fetches yabai data, builds grid state
3. **Grid renders** → SwiftUI `GridView` → `CellView` for each cell
4. **Live updates** → yabai `space_changed` signal → socket message → `HUDWindowController.refresh()`
5. **Drag-and-drop** → `WindowDragHandler` CGEventTap correlates mouse to cell, moves window via yabai

### Key Components
| File | Responsibility |
|------|----------------|
| `App.swift` | Entry point, menubar, settings window, yabai/accessibility checks |
| `HUDWindowController.swift` | NSPanel lifecycle, auto-hide timer, state management |
| `GridView.swift` | SwiftUI grid container, cell layout, theme application |
| `CellView.swift` | Per-cell rendering (rects/icons/thumbnails), space names display |
| `YabaiClient.swift` | yabai CLI wrapper, signal management, space/window queries |
| `ConfigReader.swift` | Config parsing with inline comments, SPACE_NAMES support |
| `HotkeyMonitor.swift` | Global CGEventTap for hotkey capture |
| `SocketListener.swift` | Unix domain socket server for yabai signals |
| `WindowDragHandler.swift` | Drag-and-drop detection via CGEventTap |
| `Models.swift` | Data structures (GridConfig, YabaiSpace, AppTheme) |
| `SettingsView.swift` | Settings window UI with live config save |
| `ThumbnailCache.swift` | ScreenCaptureKit thumbnail capture per space (macOS 14+) |
| `IconCache.swift` | Caches app icons by name to avoid repeated NSWorkspace lookups |

## Configuration System

### Config File Location
`~/.config/spacemap/config` — read on every HUD open (except `HOTKEY` requires restart).

### Config Keys
| Key | Type | Default | Range | Description |
|-----|------|--------|--------|-------------|
| `GRID_COLS` | Int | 8 | 1–20 | Grid columns |
| `GRID_ROWS` | Int | 2 | 1–10 | Grid rows |
| `CELL_STYLE` | String | `rects` | `rects\|icons\|thumbnails` | Window display style. `thumbnails` requires macOS 14+ and Screen Recording permission |
| `HOTKEY` | String | `ctrl+pgdn` | modifiers+key | Toggle hotkey (requires restart) |
| `UI_SCALE` | Double | 0.5 | 0.0–1.0 | HUD scale (effective: 0.5×–4.0×) |
| `THEME` | String | `default` | theme names | Color theme |
| `AUTO_HIDE_TIMEOUT` | Int | 5 | 0–60 | Seconds before HUD hides (0=never) |
| `SHOW_MODE` | String | `all` | `all\|active` | Show all or active-only spaces |
| `MAX_SPACES` | Int | 16 | 1–16 | Max spaces to display |
| `BACKGROUND_ALPHA` | Double | 0.3 | 0.0–1.0 | HUD background transparency |
| `MODE` | String | `auto` | `light\|dark\|auto` | Light/dark appearance |
| `ICON_SCALE` | Double | 0.5 | 0.0–1.0 | App icon size (effective: 0.2×–1.0×) |
| `SHOW_SPACE_NUMBERS` | Bool | `true` | `true\|false` | Show space number in top-left of each cell |
| `SHOW_SPACE_NAMES` | Bool | `true` | `true\|false` | Show custom space names in center of each cell |
| `SHOW_ICON_STRIP` | Bool | `true` | `true\|false` | Show app icon strip at bottom of each cell |
| `SHOW_MULTI_APP_ICONS` | Bool | `false` | `true\|false` | Show one icon per window (true) or one per unique app (false) |
| `HIDE_MENUBAR_ICON` | Bool | `false` | `true\|false` | Hide menubar icon (run headless) |
| `SPACE_NAMES` | String | `""` | `"1:Name,2:Name"` | Custom space names |
| `SOCKET_HEALTH_INTERVAL` | Int | 60 | 15–60 | Socket health check interval (seconds) |

### Space Naming Support
Config format for custom space names:
```ini
SPACE_NAMES=1:Desktop,2:Dev,3:Media,4:Music
```
Format: `SPACE_ID:NAME` pairs separated by commas.
- Space numbers displayed in top-left corner
- Name (if exists) displayed in cell center
- Names editable via Settings window

### Thumbnail Cache (macOS 14+)
`ThumbnailCache` uses ScreenCaptureKit to capture per-space thumbnails.

- Singleton: `ThumbnailCache.shared`
- `captureActiveSpace(spaceIndex:)` — captures the active display, excluding Spacemap's own windows, and caches the `CGImage` keyed by space index
- `thumbnail(forSpace:)` — returns cached `CGImage?` for a cell; `nil` until space is visited
- Requires **Screen Recording** permission
- `@available(macOS 14.0, *)` — all callers must use `#available` guards

### Theme System
Available themes with hex color values:
| Theme | background | focused | text | dropTarget | cellBg | cellBgFocused |
|-------|------------|---------|------|------------|--------|---------------|
| default | 0x000000 | 0x4a9eff | 0xffffff | 0x00ff00 | 0x000000 | 0x4a9eff |
| tokyonight | 0x1a1b26 | 0x7aa2f7 | 0xa9b1d6 | 0xbb9af7 | 0x1a1b26 | 0x1a1b26 |
| catppuccin | 0x1e1e2e | 0xcba6f7 | 0xcdd6f4 | 0xf5c2e7 | 0x313244 | 0x45475a |
| monokai-dark | 0x272822 | 0xa6e22e | 0xf8f8f2 | 0xfd971f | 0x3e3d32 | 0x49483e |
| monokai-light | 0xfafafa | 0xa6e22e | 0x272822 | 0xfd971f | 0xe8e8d8 | 0xd6d6c8 |
| dracula | 0x282a36 | 0xbd93f9 | 0xf8f8f2 | 0xff79c6 | 0x44475a | 0x565a79 |
| ayu | 0x0b0e14 | 0xff8f40 | 0xbfbdb6 | 0xf07178 | 0x1a1f29 | 0x2a3140 |
| github | 0x0d1117 | 0x3fb950 | 0xc9d1d9 | 0x58a6ff | 0x161b22 | 0x21262d |
| vscode | 0x1e1e1e | 0x007acc | 0xcccccc | 0x4ec9b0 | 0x252526 | 0x333333 |
| xcode | 0x1f1f24 | 0x5e9eff | 0xffffff | 0x6c5ce7 | 0x2c2c32 | 0x3a3a42 |
| nord | 0x2e3440 | 0x88c0d0 | 0xd8dee9 | 0x81a1c1 | 0x3b4252 | 0x434c5e |
| atom-one-dark | 0x282c34 | 0x61afef | 0xabb2bf | 0x98c379 | 0x2c323c | 0x3a404a |

## Settings Window

### Architecture
- `SettingsView.swift` — SwiftUI form with live-save to config file
- `SettingsWindowController.swift` — AppKit window wrapper for SwiftUI view
- Menubar → Settings (⌘,) opens window
- Changes auto-save via `onChange` handlers on every control
- Sends `settingsChanged` notification on save — observed by AppDelegate to update hotkey

### Window Controller Pattern
```swift
class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(...)
        window.contentView = NSHostingView(rootView: SettingsView())
        self.init(window: window)
    }
}
```

## Signal Integration

### Socket Protocol
- Unix domain socket at `/tmp/spacemap_<username>.socket`
- Commands: 0=refresh, 1=show, 2=hide, 3=settings
- yabai emits `spacemap_space_changed:1` on space change
- SocketListener routes to `onRefresh`/`onShow`/`onSettings` callbacks

### Registering Signal in yabai
```bash
# In yabai config (~/.yabairc):
space_change:
  emit:
    - 'spacemap_space_changed:1'
```

## Hotkey Implementation

### CGEventTap Details
- Uses `.headInsertEventTap` (not tailAppend) to capture before system shortcuts
- Requires Accessibility permissions (prompted on launch)
- Polls every 2s until permission granted

### Key Code Reference
| Key | Code | Key | Code |
|-----|------|-----|------|
| space | 49 | tab | 48 |
| return | 36 | escape | 53 |
| delete | 51 | pgdn | 121 |
| pgup | 116 | home | 115 |
| end | 119 | left/right/up/down | 123/124/126/125 |
| f1-f4 | 122,120,99,118 | f5-f8 | 96,97,98,100 |
| f9-f12 | 101,109,103,111 | a-z | various |

## UI Scaling

### Calculation
- Config `UI_SCALE` range: 0.0–1.0 (default: 0.5)
- Effective scale: `0.5 + uiScale * 3.5` → 0.5× at 0.0, 4.0× at 1.0
- Config `ICON_SCALE` range: 0.0–1.0 (default: 0.5)
- Effective icon scale: `0.2 + iconScale * 0.8` → 0.2× at 0.0, 1.0× at 1.0
- Applied to: cell size, gap, padding, fonts, icon sizes

## Debug Logging

### Console Logging
Use `NSLog` with "spacemap/" prefix:
```swift
NSLog("spacemap/ModuleName: message")
```

### Viewing Logs
1. Open Console.app
2. Filter by process: "spacemap"
3. Or filter by subsystem: "spacemap"

### Running Raw Binary for Debug
```bash
./.build/release/spacemap  # logs appear in Console.app
```

## Build Workflow

### Make Targets
| Target | Description |
|--------|-------------|
| `make build` | Build release binary |
| `make app` | Build and assemble .app bundle |
| `make install` | Install to /Applications |
| `make run` | Install and launch |
| `make test` | Run unit tests via swift test |
| `make dev1` | Uninstall (remove from /Applications) |
| `make dev2` | Reinstall and relaunch |
| `make clean` | Remove build artifacts |
| `make config` | Create default config |
| `make distconfig` | Overwrite config with defaults |
| `make dmg` | Build universal DMG |
| `make dmg-arm64` | Build ARM64 DMG |
| `make dmg-x86_64` | Build Intel DMG |
| `make build-arm64` | Build for Apple Silicon only |
| `make build-x86_64` | Build for Intel only |
| `make build-universal` | Build universal binary |

### Xcode Project
```bash
python3 scripts/generate-xcodeproj.py   # Generate from SPM
open spacemap.xcodeproj                 # Open in Xcode
```
4 targets: default, arm64, x86_64, universal. Edit `Package.swift`, not the `.xcodeproj`.

### Development Cycle
1. `make dev1` — uninstalls app
2. Remove Spacemap from System Settings → Privacy & Security → Accessibility
3. Make code changes
4. `make dev2` — rebuilds, reinstalls, launches
5. Grant Accessibility permission when prompted

## Known Issues & Workarounds

### Permission Revocation
**Problem:** Rebuilding revokes Accessibility because binary hash changes.
**Workaround:** Use `make dev1` → remove from System Settings → `make dev2`.

### Icon Flicker
**Problem:** `NSWorkspace.shared.icon(forFile:)` re-fetches on every render.
**Workaround:** `IconCache` singleton caches icons by app name. Flicker reduced but not eliminated.

### yabai Path
 yabai is auto-detected: `/opt/homebrew/bin/yabai` (ARM) or `/usr/local/bin/yabai` (Intel). No manual symlink needed.

### Config Reloading
**Problem:** `HOTKEY` requires restart to take effect.
**Reason:** CGEventTap is created once at startup with the configured key combo.