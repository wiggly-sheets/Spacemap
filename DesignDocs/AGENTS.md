# Spacemap - AGENTS.md

Whenever you are working in this repo, be as concise as possible with your answers. Sacrifice grammar for concision, but don’t sacrifice clarity.

## Project Overview

**Spacemap** is a native macOS utility that visualizes yabai workspaces in a floating 2D grid overlay. Think of it as a "mission control" for your tiling window manager.

### What It Does
- Shows a HUD overlay (toggle with hotkey) displaying your yabai desktops in a configurable grid
- Live-updates as you switch spaces via yabai
- Lets you click cells to jump to spaces
- Supports five display styles: colored rectangles, Hybrid rectangles with centered app icons, app icons, plain, or thumbnails (ScreenCaptureKit)
- Window drag-and-drop between cells (drag a window onto a cell to move it)
- Menubar and/or Dock presence for manual show/hide (`presence`: dock, menuBar, both, none)

## Quick Reference for Agents
- **File size**: a new concern gets a new extension file (or a new file for a new type), never more lines in the file that happens to be closest. `Tests/spacemapTests/SourceSizeTests.swift` fails the build when any Swift file in `Sources/` or `Tests/` passes 500 lines; split it, don't raise the limit.
- **Entry point**: `Sources/spacemap/App.swift` – sets up menubar, hotkey monitor, socket listener, Sparkle updater.
- **HUD controller**: `Sources/spacemap/HUDWindowController.swift` – manages NSPanel, show/hide, auto-hide timer, state refresh.
- **Sparkle updater**: `App.swift` initializes `SPUStandardUpdaterController` with `startingUpdater: false`; `start()` called after config load. Keys generated via `.build/artifacts/sparkle/Sparkle/bin/generate_keys`.
- **UI**: `GridView.swift` (container) + `CellView.swift` (per-cell rendering) with `CellView+Layout/Icons/Thumbnails.swift` for cell chrome, icons and thumbnail cells.
- **Data**: `YabaiClientImpl.swift` with extension files (`YabaiClientImpl+Trust/Process/Snapshots/Signals/SpaceCommands/WindowCommands/GridState/Displays/Decoding.swift`), plus `YabaiService.swift` protocol – auto-detects yabai (`/opt/homebrew/bin/yabai` or `/usr/local/bin/yabai`) for spaces/windows, 10s command timeout with async pipe drain; `ConfigStore.swift` (+ `ConfigLoader`/`TOMLConfigCodec` + `ConfigSchema`) – reads `~/.config/spacemap/config.toml`.
- **Themes**: `ThemeStore.swift` – loads `.smthemes`/`.toml` files from `~/.config/spacemap/themes/`; 20 iTerm2 themes are bundled read-only, the Theme Library installs more from the `spacemap-themes` index, and edited themes save as separate `(Edited)` TOML copies. `ThemeCodec.swift` holds the pure parse/render/hex rules; the store takes its directory by injection and `SpacemapServices` owns the one instance.
- **Hotkey**: `HotkeyMonitor.swift` (+ `HotkeyService`/`HotkeyHandler`) – global CGEventTap for normal, pinned, and glyph-strip bindings; every HUD-only action binds through the single `[hudKeys]` map; fails open on revocation; fn preserved.
- **Drag‑and‑drop**: `WindowDragHandler.swift` with `WindowDragHandler+TapLifecycle/DragFlow/WindowLookup/Delivery.swift` – second CGEventTap for window drag detection.
- **Signals**: `SocketListener.swift` with extension files (`SocketListener+Bind/Clients/Nonce/Framing.swift`) – Unix domain socket (mode 0600) for yabai `space_changed` events.
- **Models**: `ConfigurationModels+Appearance/Behavior/GlyphStrip/Keys/SpacemapConfig.swift` / `ThemeModels.swift` / `YabaiModels.swift` – data structs (SpacemapConfig, YabaiSpace, AppTheme with rect1/rect2/rect3, etc.).
- **Settings**: `SettingsView.swift` (+ per-category `SettingsGrid`/`SettingsSpaceNames`/`SettingsAppearance`/`SettingsBehavior`/`SettingsGlyphStrip`/`SettingsAdvanced`) + `SettingsDraft.swift` + `SettingsWindowController.swift` – permanent category sidebar with live-save detail forms. Every control binds one field of `SettingsDraft`, which owns the whole `SpacemapConfig` and writes it through a 0.5 s debounce (flushed on pane switch, window close, quit, and before a preset apply or import).
- **Glyph strip**: `GlyphStrip.swift` (pure model) with placement, colours, backgrounds and render layout in `GlyphStrip+Placement/Colours/Backgrounds/RenderLayout.swift` + `GlyphStripPanelController` in `GlyphStripPanel.swift`, with placement, layout, drag and input extensions in `GlyphStripPanelPlacement/Layout/Drag/Input.swift`; AppKit views in `GlyphStripPanelWindow.swift`, `GlyphStripStatusView.swift` (hover, drawing, mouse and drag in `GlyphStripStatusView+Hover/Drawing/Mouse/Drag.swift`), `GlyphStripView.swift` – menu-bar index+glyph strip, theme-driven, notch anchors or free placement, horizontal or vertical layouts, optional fullscreen hiding, session-only hotkey toggle.
- **Thumbnails**: `ThumbnailCache.swift` with `ThumbnailCache+Refresh/Requests/Captures.swift` – ScreenCaptureKit capture, per-space caching (macOS 14+).
- **Build**: Use `make run` to build, install, launch. `make dev1`/`make dev2` for dev cycle.
- **Config**: Stored at `~/.config/spacemap/config.toml`; reloads on HUD open, Settings applies hotkeys/update-mode/socket-health immediately (no restart).
- **Permissions**: Accessibility (Device Control & Access on macOS 27) for hotkeys and window dragging; Screen Recording for thumbnail cells. Advanced shows status, deep links and a drag helper; `SystemPermissions.swift` owns the checks.
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
├── HUDInput.swift         # Keyboard tap, key routing, typed space jumps
├── HUDInput+*.swift       # Panel drag, navigation, number/letter entry, keyboard, trust
├── HUDDisplay.swift       # HUD panel presentation and visibility
├── HUDDisplay+*.swift     # Render, positioning, presentation, screens
├── GridView.swift         # SwiftUI grid container
├── CellView.swift         # Individual cell rendering (rects/icons/thumbnails)
├── CellView+*.swift       # Cell layout colours, icons, thumbnail cells
├── YabaiClientImpl.swift   # Shells out to yabai binary for data/manipulation
├── YabaiClientImpl+*.swift # Trust, process, snapshots, signals, space/window commands
├── YabaiService.swift       # Protocol seam for yabai access (mockable)
├── ConfigStore.swift   # Config entry point over ConfigLoader/TOMLConfigCodec/ConfigSchema
├── TOMLDocumentParser.swift # TOML text to a nested dictionary
├── TOMLConfigDecoder.swift  # Dictionary to SpacemapConfig with repair flags
├── ConfigSchema+*.swift # Key tables (grid/appearance/behavior/table) plus writer and parser helpers
├── HotkeyMonitor.swift   # Global CGEventTap for normal/pinned/glyph-strip hotkeys
├── WindowDragHandler.swift # Detects window drag-and-drop over HUD
├── WindowDragHandler+*.swift # Tap lifecycle, drag flow, window lookup, delivery
├── SocketListener.swift   # Unix domain socket server for yabai signals
├── SocketListener+*.swift # Bind/retry, clients, nonce rotation, framing
├── ConfigurationModels+*.swift # SpacemapConfig, GlyphStripConfig, hotkeys, profiles
├── ThemeModels.swift        # AppTheme (9 roles incl rect1/rect2/rect3)
├── YabaiModels.swift        # YabaiSpace, YabaiWindow, GridState
├── GlyphStrip.swift         # Menu-bar strip model (pure, testable)
├── GlyphStrip+*.swift       # Strip placement, colours, backgrounds, render layout
├── GlyphStripPanel.swift    # Strip controller: state, refresh, menu-bar item
├── GlyphStripPanelPlacement.swift # Panel lifecycle, frames, strip geometry
├── GlyphStripPanelLayout.swift    # Segment/run layout and drawing inputs
├── GlyphStripPanelDrag.swift      # Strip drag + screen placement persistence
├── GlyphStripPanelInput.swift     # Clicks, hover, space/window drag-drop
├── GlyphStripPanelWindow.swift    # Panel, glass container, VoiceOver elements
├── GlyphStripStatusView.swift     # Compact menu-bar strip view + drawing layer
├── GlyphStripStatusView+*.swift   # Hover, drawing, mouse, drag
├── GlyphStripView.swift           # Floating strip view (clicks, drag, drawing)
├── ThumbnailCache.swift   # ScreenCaptureKit capture, per-space caching (macOS 14+)
├── ThumbnailCache+*.swift # Refresh loop, capture requests, ScreenCaptureKit calls
├── IconCache.swift         # App icon cache to avoid repeated NSWorkspace lookups
├── ThemeStore.swift        # Loads .smthemes/.toml themes, seeds built-ins, saves TOML
├── ThemeCodec.swift        # Pure theme parse, hex format, TOML render
├── SettingsView.swift     # Fixed settings sidebar + category-specific live-save forms
├── SettingsDraft.swift    # Debounced edit session over the whole config
├── SettingsGrid.swift / SettingsSpaceNames.swift / SettingsAppearance.swift
│   ├── SettingsBehavior.swift / SettingsGlyphStrip.swift / SettingsThemeEditor.swift
│   ├── SettingsAdvanced.swift / SettingsSubsection.swift
├── SettingsWindowController.swift # AppKit window wrapper for SettingsView
└── Info.plist            # App bundle metadata
```

### Key Data Flow

1. **App launches** → `App.swift` sets up menubar, hotkey monitor, and socket listener
2. **Hotkey pressed** → `HUDWindowController.show()` is called
3. **Show fetches data** → `YabaiClientImpl.querySpaces()` / `queryWindows()` (shells to `/opt/homebrew/bin/yabai`)
4. **Builds state** → `YabaiClientImpl.buildGridState()` assembles `GridState` with config
5. **Renders grid** → SwiftUI `GridView` → `CellView` for each cell
6. **Live updates** → yabai signal triggers → socket message → `HUDWindowController.refresh()`
7. **Drag-and-drop** → `WindowDragHandler` uses CGEventTap to track mouse, yabai to move window

### External Dependencies
- **yabai** (installed at `/opt/homebrew/bin/yabai`) - tiling window manager
- **skhd** (optional) - hotkey daemon; the HUD handles its own key bindings, skhd is only needed for yabai-level bindings outside the HUD

### Configuration
Reads from `~/.config/spacemap/config.toml` on every HUD open (no restart needed):
```bash
[grid]
cols = 8
rows = 2
cellStyle = "rects"

[behavior.hotkey]
keyKind = "keyCode"
keyCode = 49
modifiers = ["ctrl"]

[advanced]
socketHealthInterval = 60
```

## Important Technical Details

### CGEventTap (Not NSEvent)
Uses `CGEvent.tapCreate` at `cgSessionEventTap` / `headInsertEventTap` for global hotkey capture. This requires Accessibility permissions.

### Binary Running vs App Bundle
macOS grants Accessibility to the `.app` bundle, not the raw binary. Running the binary directly will fail the trust check. Always use `make run` or `open /Applications/Spacemap.app`.

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
- **hybrid:** Uses rects unchanged with a proportionally scaled app icon centered in each rectangle
- **icons:** One icon per yabai window, positioned from yabai geometry
- **thumbnails:** ScreenCaptureKit display capture per cell (requires macOS 14+, Screen Recording permission)
- **simple:** Empty cells with no window content

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
make help       # List every target (default)
make build       # swift build -c release
make app         # Build and assemble the universal .app bundle
make app-arm     # Build and assemble the arm64 .app bundle
make app-intel   # Build and assemble the x86_64 .app bundle
make install     # Install to /Applications
make run         # Install and launch
make dev1        # Uninstall (then remove Accessibility in System Settings)
make dev2        # Reinstall, relaunch, re-grant permissions
make test        # Run unit tests via swift test
make config      # Create default config
make permissions # Show permission fix instructions
make clean       # Remove build artifacts
make archive     # Build signed archive for release
make dmg         # Build the arm64 and the x86_64 DMG
make dmg-arm     # Build ARM64 DMG
make dmg-intel   # Build Intel DMG
make dmg-universal # Build universal DMG
make release-artifacts # Build the DMGs and write checksums.txt
make release VERSION=x.y.z  # Bump version, commit, tag locally, print the push command (no push)
```

### Xcode
Open `Package.swift` in Xcode. The package is the only build definition; there is no generated `.xcodeproj`.

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
4. **Icon strip flicker:** Fixed via `IconCache` (64 icons, LRU); `CellView` no longer re-fetches through `NSWorkspace` per render
5. **Drag resolution:** Window drag detection uses frontmost app name matching, which can be ambiguous for multi-window apps. Falls back to click proximity.
6. **Test suite:** 944 tests across 106 files (`Tests/spacemapTests/` + `MockYabaiService.swift`). Run with `make test` or `swift test`.
7. **Socket health check:** Periodic `fcntl(fd, F_GETFD)` check + file existence check. Restarts on failure.

## Potential Extension Points

### Appearance
- ~~Custom cell colors, backgrounds, or opacity~~ ✅ Theme files with rect1/rect2/rect3, per-style glass and opacity
- ~~Custom fonts/sizes for space numbers~~ ✅ HUD font panel, `hudFontName`/`hudFontSize`
- Rounded corners, borders, shadow customization
- Animations for cell focus/hover

### Behavior
- Customizable cell size (currently hardcoded 80x50)
- Grid gap/padding config
- Multi-monitor awareness (spaces per display)

### Features
- Show window titles on hover
- ~~Keyboard navigation within HUD (arrows + enter)~~ ✅ Arrow keys + vim keys with grid-aware wrapping
- ~~Pin HUD to always show (like a dashboard)~~ ✅ Pinned hotkey + `AUTO_HIDE_TIMEOUT=0`
- ~~Window thumbnail previews instead of rectangles~~ ✅ Thumbnail cell style (ScreenCaptureKit)
- Filter/hide specific apps from the grid

### Integration
- Support for other window managers besides yabai ( Parallel to yabai? Or macOS native Spaces? )
- ~~Scripting / CLI interface to trigger HUD from scripts~~ ✅ CLI flags, deep links, yabai signal socket
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
- File-based theme system (.smthemes and .toml files in ~/.config/spacemap/themes/, plus the in-app editor)
- Grid-aware keyboard navigation (arrow keys + vim keys with wrapping)
- Dynamic yabai path detection (ARM + Intel)
- Unit test suite: ~588 tests across 35 files when this entry was written (since grown to 944 tests across 106 files, below)
- Glyph strip: theme-driven menu-bar index+glyph strip (material/shape/glass style, per-style variant and opacity, optional match-HUD appearance, notch anchors or free placement, horizontal/vertical/stacked layouts, position lock, fullscreen hiding)
- Space-name profiles with menu-bar switching; fn modifier preserved across hotkeys/drop-focus
- Hardening: yabai 10s timeout + async pipe drain, socket mode 0600, release tag/appcast checks
- GitHub Actions CI: swift test + build on push/PR
- GitHub Actions Release: 3 DMG variants + checksums on tag push
- Dependabot for GitHub Actions
- Architecture-specific builds (ARM64, x86_64, universal)
- Theme Library: 20 bundled iTerm2 themes (read-only), one-click install/remove/apply, catalog fetched from the `spacemap-themes` index and refreshed daily
- Theme Editor: clone, edit, and save themes; originals stay untouched as `(Edited)` copies are written; external file edits reload the theme list
- Custom HUD font and size via the native font panel (`hudFontName`/`hudFontSize`); the glyph strip can match the HUD appearance
- HUD entrance styles (`fade`, slide from each edge, `scale`) and motion styles (`natural`, `springy`, `fast`)
- Per-style glass variants and opacities (clear/regular/tinted) for the HUD, space cells, and strip
- Space reordering: drag a space number in the strip or HUD to swap contents or move spaces; drag an app icon to move its windows
- Glyph strip menu-bar mode (`displayMode = menuBarItem`), auto-resize (`autoResizeMaxLength`), split padding, layout letters
- Config presets under `~/.config/spacemap/presets/` with import/export from Settings > Advanced and `spacemap --config-preset NAME`
- Every HUD key action configurable via the `[hudKeys]` table; the old arrow/vim/extended-key toggles are gone
- CLI: `--status`, `--print-config`, `--update`, `--update-font` (beyond the earlier `--version/--help/--config/--trigger/--space/--show-menu/--settings`)
- Pre-2.0 config key aliases removed from the parser (no migration code — see DesignDocs/adr/0001)
- Local installs and the CLI symlink target standardized on `/Applications`
- Test suite: 944 tests across 106 files, aligned to testing standards
- Theme bug fix: `dropTarget` case sensitivity in `.smthemes` parsing

See [TASKS.md](./TASKS.md) for planned features, bug fixes, and known issues.

## Questions

1. **Electron app?** It is pure Swift with SwiftUI
2. **Accessibility of the config?** The TOML config is grouped to match the Settings categories and self-heals invalid fields.
3. **Hotkey parsing limitations?** The hotkey parser supports regular keys, F13–F20, media keys, and modifiers including fn (see `Hotkey.swift`). Unlisted keys are not supported. Is this by design?
