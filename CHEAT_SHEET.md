# spacemap Cheat Sheet

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
| `make dmg` | Build DMG installer |
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
| `spacemap --show-menu` | Show menu bar dropdown (app continues running) |
| `spacemap --settings` | Open settings window directly (app continues running) |

## Key File Locations

| File | Purpose |
|------|---------|
| `~/.config/spacemap/config` | User configuration (reloads on HUD open, except HOTKEY) |
| `/Applications/spacemap.app` | Installed application bundle |
| `/usr/local/bin/spacemap` | CLI symlink (if installed) |
| `/tmp/spacemap_<username>.socket` | Unix domain socket for yabai signals |
| `Console.app` | View logs (filter by "spacemap") |

## Key Classes & Structs

| File | Key Types | Responsibility |
|------|-----------|----------------|
| `App.swift` | `spacemapApp` | Entry point, menubar, settings window, launch checks |
| `HUDWindowController.swift` | `HUDWindowController` | NSPanel lifecycle, show/hide, auto-hide timer, state refresh |
| `GridView.swift` | `GridView` | SwiftUI grid container, cell layout, theme |
| `CellView.swift` | `CellView` | Per-cell rendering (rects/icons/hybrid), space names |
| `YabaiClient.swift` | `YabaiClient` | yabai CLI wrapper, space/window queries, signal management |
| `ConfigReader.swift` | `ConfigReader` | Config parsing with inline comments, SPACE_NAMES support |
| `HotkeyMonitor.swift` | `HotkeyMonitor` | Global CGEventTap for hotkey capture |
| `SocketListener.swift` | `SocketListener` | Unix domain socket server for yabai signals |
| `WindowDragHandler.swift` | `WindowDragHandler` | Drag-and-drop detection via CGEventTap |
| `Models.swift` | `GridConfig`, `YabaiSpace`, etc. | Data structures |
| `SettingsView.swift` | `SettingsView` | Settings window UI with live-save |
| `SettingsWindowController.swift` | `SettingsWindowController` | AppKit window wrapper for SettingsView |

## Development Workflow

1. `make dev1` (uninstalls app)
2. Remove spacemap from System Settings → Privacy & Security → Accessibility
3. Make code changes
4. `make dev2` (rebuilds, reinstalls, launches)
5. Grant Accessibility permission when prompted

## Common Issues & Fixes

- **Accessibility permission lost after rebuild**: Use `make dev1` → remove from System Settings → `make dev2`.
- **Hotkey not working**: Ensure Accessibility permission granted; HOTKEY changes require app restart.
- **Config changes not taking effect**: Most config reloads on HUD open; HOTKEY requires restart.
- **yabai not found**: Ensure yabai is installed at `/opt/homebrew/bin/yabai` (Apple Silicon) or create symlink for Intel.
- **Icon flicker**: Known issue due to re-fetching icons on each render; optimization planned.

## Important Notes

- macOS grants Accessibility permission to the `.app` bundle, not the raw binary. Always use `make run` or open `/Applications/spacemap.app`.
- The app runs with `NSApp.setActivationPolicy(.prohibited)` so it never appears in Dock or Cmd+Tab.
- yabai path is hardcoded to `/opt/homebrew/bin/yabai`; no PATH search.
- Config file uses simple `KEY=VALUE` format with inline `#` comments allowed.
- Space names configurable via `SPACE_NAMES=1:Name,2:Name` format in config.