# Spacemap - AGENTS.md

Whenever you are working in this repo, be as concise as possible with your answers. Sacrifice grammar for concision, but don’t sacrifice clarity.

## Project Overview

**Spacemap** is a native macOS utility that visualizes yabai workspaces in a floating 2D grid overlay. Think of it as a "mission control" for your tiling window manager.

### What It Does
- Shows a HUD overlay (toggle with hotkey) displaying your yabai desktops in a configurable grid
- Live-updates as you switch spaces via yabai
- Lets you click cells to jump to spaces
- Supports four display styles: colored rectangles, app icons, plain, or thumbnails (ScreenCaptureKit)
- Window drag-and-drop between cells (drag a window onto a cell to move it)
- Menubar icon for manual show/hide (can be hidden)

## Quick Reference for Agents
- **Entry point**: `Sources/spacemap/App.swift` – sets up menubar, hotkey monitor, socket listener, Sparkle updater.
- **HUD controller**: `Sources/spacemap/HUDWindowController.swift` – manages NSPanel, show/hide, auto-hide timer, state refresh.
- **Sparkle updater**: `App.swift` initializes `SPUStandardUpdaterController` with `startingUpdater: false`; `start()` called after config load. Keys generated via `.build/artifacts/sparkle/Sparkle/bin/generate_keys`.
- **UI**: `GridView.swift` (container) + `CellView.swift` (per-cell rendering).
- **Data**: `YabaiClient.swift` – auto-detects yabai (`/opt/homebrew/bin/yabai` or `/usr/local/bin/yabai`) for spaces/windows; `ConfigReader.swift` – reads `~/.config/spacemap/spacemap.jsonc`.
- **Themes**: `ThemeManager.swift` – loads `.smthemes` files from `~/.config/spacemap/themes/`, seeds built-in themes on first launch.
- **Hotkey**: `HotkeyMonitor.swift` – global CGEventTap for toggle.
- **Drag‑and‑drop**: `WindowDragHandler.swift` – second CGEventTap for window drag detection.
- **Signals**: `SocketListener.swift` – Unix domain socket for yabai `space_changed` events.
- **Models**: `Models.swift` – data structs (GridConfig, YabaiSpace, UpdateMode, etc.).
- **Settings**: `SettingsView.swift` + `SettingsWindowController.swift` – permanent category sidebar with separate live-save detail forms.
- **Thumbnails**: `ThumbnailCache.swift` – ScreenCaptureKit capture, per-space caching (macOS 14+).
- **Build**: Use `make run` to build, install, launch. `make dev1`/`make dev2` for dev cycle.
- **Config**: Stored at `~/.config/spacemap/spacemap.jsonc`; reloads on HUD open (except HOTKEY needs restart).
- **Permissions**: Requires Accessibility permission (prompted on first launch). Screen Recording permission required for thumbnail cell style.
- **Sparkle Keys**: Public key is in `sparklesigner.pub`; `sparklesigner.pem` is the matching local PEM private key. Both are `.gitignore`d. GitHub `SPARKLE_PUBLIC_KEY` stores the public key; `SPARKLE_PRIVATE_KEY` must contain the matching base64-encoded 32-byte Ed25519 seed (not the PEM file). The release workflow verifies the pair before building.

## Architecture

### Tech Stack
- **Language:** Swift 5.9, targeting macOS 13+
- **UI Framework:** SwiftUI embedded in AppKit (NSHostingView)
- **Build System:** Swift Package Manager (Package.swift)
- **Dependencies:** ZERO external dependencies
- **System Integration:** Low-level macOS APIs (CoreGraphics, AppKit), yabai CLI calls, Unix domain sockets, CGEventTaps

### File Structure
```
Sources/spacemap/
├── App.swift              # App entry point, menubar, hotkey setup
├── HUDWindowController.swift  # Manages NSPanel HUD (show/hide/render)
├── GridView.swift         # SwiftUI grid container
├── CellView.swift         # Individual cell rendering (rects/icons/thumbnails)
├── YabaiClient.swift      # Shells out to yabai binary for data/manipulation
├── ConfigReader.swift     # Parses ~/.config/spacemap/spacemap.jsonc
├── HotkeyMonitor.swift   # Global CGEventTap for toggle hotkey
├── WindowDragHandler.swift # Detects window drag-and-drop over HUD
├── SocketListener.swift   # Unix domain socket server for yabai signals
├── Models.swift           # Data structures (GridConfig, YabaiSpace, etc.)
├── ThumbnailCache.swift   # ScreenCaptureKit capture, per-space caching (macOS 14+)
├── IconCache.swift         # App icon cache to avoid repeated NSWorkspace lookups
├── ThemeManager.swift      # Loads .smthemes files, seeds built-in themes on first launch
├── SettingsView.swift     # Fixed settings sidebar + category-specific live-save forms
├── SettingsWindowController.swift # AppKit window wrapper for SettingsView
└── Info.plist            # App bundle metadata
```

### Key Data Flow

1. **App launches** → `App.swift` sets up menubar, hotkey monitor, and socket listener
2. **Hotkey pressed** → `HUDWindowController.show()` is called
3. **Show fetches data** → `YabaiClient.querySpaces()` / `queryWindows()` (shells to `/opt/homebrew/bin/yabai`)
4. **Builds state** → `YabaiClient.buildGridState()` assembles `GridState` with config
5. **Renders grid** → SwiftUI `GridView` → `CellView` for each cell
6. **Live updates** → yabai signal triggers → socket message → `HUDWindowController.refresh()`
7. **Drag-and-drop** → `WindowDragHandler` uses CGEventTap to track mouse, yabai to move window

### External Dependencies
- **yabai** (installed at `/opt/homebrew/bin/yabai`) - tiling window manager
- **skhd** (installed at `/opt/homebrew/bin/skhd`) - hotkey daemon, configured for 2D grid navigation

### Configuration
Reads from `~/.config/spacemap/spacemap.jsonc` on every HUD open (no restart needed):
```bash
GRID_COLS=8              # Grid columns
GRID_ROWS=2              # Grid rows
CELL_STYLE=rects         # rects | icons | thumbnails
HOTKEY=ctrl+space         # Toggle hotkey (requires restart)
SOCKET_HEALTH_INTERVAL=60  # Socket health check interval (seconds)
```

## Important Technical Details

### CGEventTap (Not NSEvent)
Uses `CGEvent.tapCreate` at `cgSessionEventTap` / `headInsertEventTap` for global hotkey capture. This requires Accessibility permissions.

### Binary Running vs App Bundle
macOS grants Accessibility to the `.app` bundle, not the raw binary. Running the binary directly will fail the trust check. Always use `make run` or `open /Applications/spacemap.app`.

### Permission Revocation on Reinstall
Rebuilding and reinstalling revokes Accessibility permissions because the binary hash changes. Use the `make dev1` / `make dev2` workflow.

### App Activation Policy
`NSApp.setActivationPolicy(.prohibited)` means the app never appears in the dock or Cmd+Tab switcher. It runs purely as a background utility.

### yabai Signal Integration
When the HUD is visible, yabai sends a signal to a Unix domain socket on `space_changed`. This triggers HUD refresh for live updates without polling.

### Window Drag Detection
A second CGEventTap (listenOnly, tailAppend) monitors mouse drag events to detect when the user drags an actual window over the HUD. It correlates the mouse position against cell hit-rectangles and uses the frontmost application to identify which window is being dragged.

### Cell Styles
- **rects:** Scales real window geometry to 80x50 cell, colored by app name hash
- **icons:** App icons at window position; app strip at bottom (controlled by `SHOW_ICON_STRIP`)
- **thumbnails:** ScreenCaptureKit display capture per cell (requires macOS 14+, Screen Recording permission)

## Development Workflow

### CHANGELOG Rule
**Always** update `## [Unreleased]` in CHANGELOG.md as you work — not after, not at the end. When you add a feature, add a line. When you fix a bug, add a line. When you change behavior, add a line. Entries go under the appropriate `### Added`, `### Changed`, `### Fixed`, or `### Removed` subheading. If the subheading doesn't exist yet, create it.

### Release Checklist
Before `make release`:
- [ ] Add entries to `## [Unreleased]` in CHANGELOG.md (Added/Changed/Fixed/Removed)
- [ ] Update TASKS.md to mark completed items
- [ ] Run `make test` to verify

### Build Commands
```bash
make build       # swift build -c release
make app         # Build and assemble .app bundle
make install     # Install to /Applications
make run         # Install and launch
make dev1        # Uninstall (then remove Accessibility in System Settings)
make dev2        # Reinstall, relaunch, re-grant permissions
make test        # Run unit tests via swift test
make config      # Create default config
make permissions # Show permission fix instructions
make clean       # Remove build artifacts
make archive     # Build signed archive for release
make dmg         # Build universal DMG
make dmg-arm64   # Build ARM64 DMG
make dmg-x86_64  # Build Intel DMG
make release RELEASE=x.y.z  # Bump version, commit, tag, push (triggers GitHub Actions release)
```

### Xcode Project
```bash
python3 scripts/generate-xcodeproj.py   # Generate from SPM
open spacemap.xcodeproj                 # Open in Xcode
```
Targets: default, arm64, x86_64, universal. Project is regenerated from `Package.swift` — edit SPM, not the `.xcodeproj`.

### Testing Changes
1. `make dev1` (uninstalls app)
2. Remove Spacemap from System Settings → Privacy & Security → Accessibility
3. Make code changes
4. `make dev2` (builds, installs, launches)
5. Grant permission when prompted

## Known Limitations / Gotchas

1. **yabai path auto-detected:** Checks `/opt/homebrew/bin/yabai` (ARM) then `/usr/local/bin/yabai` (Intel) via `FileManager`
2. **Homebrew-specific:** Brew formula only, no other package managers
3. **SwiftUI performance:** Each HUD open creates a new NSHostingView. The state is cached during a drag, but the view is recreated.
4. **Icon strip flicker:** On space change, `CellView` rerenders and re-fetches icons via `NSWorkspace.shared.icon(forFile:)` which is potentially expensive
5. **Drag resolution:** Window drag detection uses frontmost app name matching, which can be ambiguous for multi-window apps. Falls back to click proximity.
6. **Test suite:** 183 unit tests across 9 files (`Tests/spacemapTests/`). Run with `make test` or `swift test`.
7. **Socket health check:** Periodic `fcntl(fd, F_GETFD)` check + file existence check. Restarts on failure.

## Potential Extension Points

### Appearance
- ~~Custom cell colors, backgrounds, or opacity~~ ✅ Theme files with rect1/rect2/rect3
- Custom fonts/sizes for space numbers
- Rounded corners, borders, shadow customization
- Animations for cell focus/hover

### Behavior
- Customizable cell size (currently hardcoded 80x50)
- Grid gap/padding config
- Multi-monitor awareness (spaces per display)

### Features
- Show window titles on hover
- ~~Keyboard navigation within HUD (arrows + enter)~~ ✅ Arrow keys + vim keys with grid-aware wrapping
- Pin HUD to always show (like a dashboard)
- Window thumbnail previews instead of rectangles
- Filter/hide specific apps from the grid

### Integration
- Support for other window managers besides yabai ( Parallel to yabai? Or macOS native Spaces? )
- Scripting / CLI interface to trigger HUD from scripts
- Notifications / system alerts
- Better multi-monitor support

### Build / Dev
- Linting / formatting (SwiftFormat)
- Homebrew formula improvements

## Tasks & Roadmap

### Recently Completed
- CLI options (--version, --help, --config, --trigger, --show-menu, --settings)
- Settings menu item (⌘+,)
- Hotkey rapid-press fix
- Automatic symlink creation (/usr/local/bin/spacemap)
- HUD active space highlighting
- Launch at Login toggle with state indicator
- Show Space Numbers toggle
- Move to Applications first-launch prompt
- Config file auto-generation and self-healing
- Fixed auto-hide timeout
- Screen Recording permissions link in menubar
- Cell opacity / inactive space dimming
- Thumbnail cell style (ScreenCaptureKit, experimental)
- File-based theme system (.smthemes files in ~/.config/spacemap/themes/)
- Grid-aware keyboard navigation (arrow keys + vim keys with wrapping)
- Dynamic yabai path detection (ARM + Intel)
- Xcode project generation (`scripts/generate-xcodeproj.py`, 4 targets)
- Unit test suite: 183 tests across 9 files (`Tests/spacemapTests/`)
- GitHub Actions CI: swift test + build on push/PR
- GitHub Actions Release: 3 DMG variants + checksums on tag push
- Dependabot for GitHub Actions
- Architecture-specific builds (ARM64, x86_64, universal)
- Theme bug fix: `dropTarget` case sensitivity in `.smthemes` parsing

See [TASKS.md](./TASKS.md) for planned features, bug fixes, and known issues.

## Questions

1. **Electron app?** It is pure Swift with SwiftUI
2. **Accessibility of the config?** The config file uses a simple key=value format, but there's no validation or schema. Would a JSON or YAML config be better?
3. **Hotkey parsing limitations?** The hotkey parser only supports a subset of keys (see `ConfigReader.keyCodeFor`). Keys like F13-F20, media keys, etc., are not supported. Is this by design?
