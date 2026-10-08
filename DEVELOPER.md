# Spacemap - Developer Guide

Technical deep-dive, debugging, and configuration details for contributors.

## Core Architecture

### Data Flow
1. **App launches** → `App.swift` checks yabai, sets up menubar, hotkey monitor, socket listener, Sparkle updater
2. **Hotkey pressed** → `HUDWindowController.show()` fetches yabai data, builds grid state
3. **Grid renders** → SwiftUI `GridView` → `CellView` for each cell
4. **Live updates** → yabai `space_changed` signal → socket message → `HUDWindowController.refresh()`
5. **Drag-and-drop** → `WindowDragHandler` CGEventTap correlates mouse to cell, moves window via yabai
6. **Update check** → Sparkle fetches appcast at launch (if enabled), shows update dialog or downloads silently

### Key Components
| File | Responsibility |
|------|----------------|
| `App.swift` + `ApplicationLifecycleService.swift` | Entry point, menubar, settings window, yabai/accessibility checks |
| `HUDWindowController.swift` + `HUDInput`/`HUDDisplay`/`HUDStateSync` | NSPanel lifecycle, auto-hide timer, state management |
| `GridView.swift` | SwiftUI grid container, cell layout, theme application |
| `CellView.swift` | Per-cell rendering (rects/icons/thumbnails), space names display |
| `GridLayout.swift` | Pure geometry (cell/gap/padding, slot frames, hit-test); guards: `cols > 0`, spaces clamped 0–16, zero-size frames return nil/empty |
| `YabaiClientImpl.swift` + `YabaiService.swift` | yabai CLI wrapper, signal management, space/window queries (10s timeout, async pipe drain) |
| `Config.swift` (facade) + `ConfigLoader`/`TOMLParser`/`ConfigValues` | Grouped TOML load/save/parse; invalid fields self-heal individually after `config.toml.bak` backup |
| `HotkeyMonitor.swift` + `HotkeyService`/`HotkeyHandler` | Global CGEventTap for normal/pinned/glyph-strip hotkeys; fails open on Accessibility revocation |
| `SocketListener.swift` | Unix domain socket server for yabai signals (mode 0600, non-blocking clients) |
| `WindowDragHandler.swift` + `WindowDragService` | Drag-and-drop detection via CGEventTap |
| `ConfigurationModels.swift` / `ThemeModels.swift` / `YabaiModels.swift` | Data structures (GridConfig, YabaiSpace, AppTheme) |
| `GlyphStrip.swift` + `GlyphStripPanel.swift` | Menu-bar strip model (pure, testable) + panel/view (AppKit) |
| `SettingsView.swift` + per-category `SettingsGrid`/`SettingsSpaceNames`/`SettingsAppearance`/`SettingsBehavior`/`SettingsGlyphStrip`/`SettingsAdvanced` | Permanent settings sidebar and category-specific live-save forms |
| `ThumbnailCache.swift` + `ThumbnailCompositor`/`ThumbnailRequestBuilder` | ScreenCaptureKit thumbnail capture per space (macOS 14+) |
| `IconCache.swift` | Caches app icons by name to avoid repeated NSWorkspace lookups |

## Configuration System

### Config File Location
`~/.config/spacemap/config.toml` — read on every HUD open. Invalid fields self-heal individually after backing up to `config.toml.bak`.

### Config Keys (TOML tables; `ConfigValues` clamps numerics at the model boundary)
| Key | Type | Default | Range | Description |
|-----|------|--------|--------|-------------|
| `cols` / `rows` | Int | 8 / 2 | > 0 | Grid columns / rows |
| `cellStyle` | String | `rects` | `rects‖hybrid‖icons‖thumbnails‖simple` | Window display style. `hybrid` adds centered app icons to rectangles; `thumbnails` requires macOS 14+ and Screen Recording permission |
| `hotkey` | Hotkey | `ctrl+space` | modifiers+key | Toggle hotkey (applies immediately from Settings) |
| `pinnedHotkey` | Hotkey | `none` | modifiers+key or `none` | Optional persistent-HUD toggle |
| `glyphStripHotkey` | Hotkey | `none` | modifiers+key or `none` | Glyph-strip show/hide; session-only, never persisted |
| `uiScale` / `iconScale` | Double | 0.5 / 0.5 | 0.0–1.0 | HUD scale (effective: 0.5×–4.0×) / icon size (effective: 0.2×–1.0×) |
| `theme` / `mode` | String | `default` / `auto` | theme names / `light‖dark‖auto` | Color theme / appearance |
| `backgroundAlpha` | Double | 0.3 | 0.0–1.0 | HUD background transparency |
| `hudShadow` | Bool | true | — | HUD panel shadow |
| `autoHideTimeout` | Int | 5 | ≥ 0 | Seconds before HUD hides (0=never) |
| `showMode` | String | `all` | `all‖active` | Show all or active-only spaces |
| `multiMonitorHUDMode` | String | `unified` | `unified‖separate` | Use one combined HUD or one HUD per display |
| `unifiedHUDVisibility` | String | `active` | `all‖active` | In unified mode, show the combined HUD everywhere or only on the focused-space display |
| `separateHUDVisibility` | String | `all` | `all‖active` | In separate mode, show every HUD or only the focused-space HUD |
| `displayNavigationWrap` | String | `within` | `within‖between` | Keep keyboard navigation on one display or wrap across displays |
| `maxSpaces` | Int | 16 | 1–16 (oversize clamps, undersize resets) | Max spaces to display |
| `showSpaceNumbers` | Bool | `true` | — | Show space number in top-left of each cell |
| `showSpaceNames` | Bool | `true` | — | Show custom space names in center of each cell |
| `showIconStrip` | Bool | `true` | — | Show app icon strip at bottom of each cell |
| `showMultiAppIcons` | Bool | `false` | — | Show one icon per window (true) or one per unique app (false) |
| `hideMenuBarIcon` | Bool | `false` | — | Hide menubar icon (run headless) |
| `menuBarDisplayMode` / `menuBarNearbyCount` | String / Int | `icon` / 3 | `icon‖dots‖current‖nearby‖all` / 1–16 | Menu-bar preview mode and nearby count |
| `useVimKeys` / `useArrowKeys` / `useExtendedKeys` | Bool | false / false / true | — | hjkl / arrows / extended navigation keys |
| `jumpToSpaceEnabled` | Bool | `false` | — | Number-key space jumps (multi-digit supported) |
| `hudPosition` / `customHUDX` / `customHUDY` | String / Double | `center` / 0.5 / 0.5 | `center‖top‖bottom‖custom` / 0–1 | HUD placement + custom coordinates |
| `spaceNames` + `spaceNameProfiles` | Map / profiles | — | — | `[spaceNames.names]` quoted-number keys + named profile sets |
| `socketHealthInterval` | Int | 60 | > 0 | Socket health check interval (seconds) |
| `showExtraWindows` | Bool | false | — | Display utility/background window records |
| `showHUDOnSpaceChange` | Bool | false | — | Auto-show HUD on yabai space change |
| `updateMode` | String | `notify` | `auto‖notify‖off` | Sparkle update check behavior. `auto` downloads and installs; `notify` prompts; `off` disables |
| `focusSpaceOnWindowDrop` | WindowDropFocusMode | `never` | `never‖always‖modifier` | Focus the destination space after a successful window drop |
| `focusSpaceOnWindowDropModifier` | WindowDropFocusModifier | `command` | `command‖fn‖option‖control‖shift` | Modifier required when drop focus is `modifier` (fn preserved) |
| `[glyphStrip]` | — | — | — | Strip keys in REFERENCE.md; numerics clamped (`iconSize`/`indexSize` 6–24, `backgroundOpacity` 0.01–1, `glassAmount` 0–1, `cornerRadius` 0–40, `margin` 0–40, `iconSpacing`/`indexPadding` 0–20, `yOffset` -10–10, `xOffset` ±4000, `hoverPadding` 0–12, `hoverCornerRadius` 0–20, `maxIconsPerSpace` 0–16) |
| `[appFont]` | `updateMode` | `manual` | `manual‖auto` | Glyph-font update policy |

### Space Naming Support
TOML names plus named profiles:
```toml
[spaceNames.names]
"1" = "Desktop"
"2" = "Dev"

[spaceNameProfiles]
activeIndex = 0

[spaceNameProfiles.0]
name = "Default"

[spaceNameProfiles.0.names]
"1" = "Desktop"
```
- Space numbers displayed in top-left corner; name (if exists) in cell center
- Profiles edited in Settings → Space Names (own section below the names form); switched there or from the menu bar
- Active profile index out of range repairs to 0; empty profile list repairs to Default

### Thumbnail Cache (macOS 14+)
`ThumbnailCache` uses ScreenCaptureKit to capture per-space thumbnails.

- Singleton: `ThumbnailCache.shared`
- `captureActiveSpace(spaceIndex:)` — captures the active display, excluding Spacemap's own windows, and caches the `CGImage` keyed by space index
- `thumbnail(forSpace:)` — returns cached `CGImage?` for a cell; `nil` until space is visited
- Requires **Screen Recording** permission
- `@available(macOS 14.0, *)` — all callers must use `#available` guards

### Theme System
Available themes with hex color values (9 roles: background, focused, text, dropTarget, cellBg, cellBgFocused, rect1, rect2, rect3):
| Theme | background | focused | text | dropTarget | cellBg | cellBgFocused | rect1 | rect2 | rect3 |
|-------|------------|---------|------|------------|--------|---------------|-------|-------|-------|
| default | 0xf2f2f7 | 0x007aff | 0x333333 | 0x007aff | 0xe5e5ea | 0xd1d1d6 | 0x007aff | 0x5ac8fa | 0x34c759 |
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
- `SettingsView.swift` — fixed, always-visible category sidebar plus one live-save detail form per selected category
- `SettingsWindowController.swift` — AppKit window wrapper for SwiftUI view
- Menubar → Settings (⌘,) opens window
- Changes auto-save via `onChange` handlers on every control
- Sends `settingsChanged` notification on save — observed by AppDelegate to restart both hotkey monitors

### Categories
- **Grid** — layout, display topology, cell rendering, and window visibility
- **Space Names** — name visibility, per-space text, and named profiles (separate section below the names form)
- **Appearance** — themes, appearance mode, transparency, and scaling
- **Behavior** — normal, pinned, and glyph-strip hotkeys, positioning, navigation, drag/drop focus, menu bar, and updates
- **Glyph Strip** — always-visible menu-bar strip: contents, appearance (glass slider shown tint-on-only, opacity solid-only, corner radius roundedRect-only), click bindings, and placement (`[glyphStrip]`)
- **Debug/Advanced** — socket health interval

The sidebar is a fixed pane rather than a collapsible `NavigationSplitView`. Selecting a row replaces the detail form; categories are not anchors in one continuous scrolling form.

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
- Unix domain socket at `/tmp/spacemap_<username>.socket` (created mode 0600, clients set non-blocking, cancel handler closes fd)
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
- One owned monitor each for normal, pinned, and glyph-strip bindings; changed bindings apply without retaining old shortcuts, media shortcuts fire on key-down only
- Fails open when Accessibility is revoked: HUD/pinned input releases immediately and unrelated keys pass through
- Continuously checks permission and event-tap health every second, automatically removing stale taps and restoring hotkeys after permission is re-granted
- fn key preserved end to end: recorded as `maskSecondaryFn`, serialized as `fn`, accepted in drop-focus modifiers

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

## Sparkle Automatic Updates

### Overview
Spacemap uses [Sparkle 2](https://sparkle-project.org) for automatic updates. DMG releases are signed with EdDSA (ed25519) keys generated by Sparkle's `generate_keys` tool.

### Keys
The **public key** is embedded in the app's `Info.plist` (`SUPublicEDKey`). GitHub Actions signs DMGs with the matching private-key secret.

`SPARKLE_PUBLIC_KEY` is the base64 public key. `SPARKLE_PRIVATE_KEY` must be the matching base64-encoded 32-byte Ed25519 seed accepted by Sparkle's `sign_update` tool—not a PEM wrapper. The release workflow derives the public key from the private secret and fails before building if they do not match.

**Important:** If you regenerate keys, update both GitHub Secrets and the local key files. For the existing PEM private key, the seed suitable for `SPARKLE_PRIVATE_KEY` can be derived without printing it: `openssl pkey -in sparklesigner.pem -outform DER | tail -c 32 | base64`.

### Appcast
Hosted at `https://wiggly-sheets.github.io/Spacemap/appcast.xml` via GitHub Pages serving the `docs/` branch. Generated by `.github/scripts/generate-appcast.sh` during the release workflow.

### Update Modes
| Mode | Behavior |
|------|----------|
| `auto` | Checks periodically, downloads and installs automatically |
| `notify` | Checks periodically, shows dialog with release notes |
| `off` | Disables update checking entirely |

First-launch prompt asks the user to choose. Setting is stored in `~/.config/spacemap/config.toml` as `updateMode`.

### Info.plist Keys
| Key | Value |
|-----|-------|
| `SUFeedURL` | `https://wiggly-sheets.github.io/Spacemap/appcast.xml` |
| `SUPublicEDKey` | EdDSA public key (base64) |

### Release Workflow
1. Run `make release RELEASE=x.y.z` — bumps Info.plist + VERSION, commits, tags, pushes
2. Tag pushed → `release.yml` runs
3. Builds 3 DMG variants (ARM64, x86_64, universal)
4. Signs universal DMG with EdDSA key from GitHub Secret
5. `generate-appcast.sh` creates `appcast.xml` with enclosure signature
6. Pushes to `docs/` branch → GitHub Pages serves it
7. `softprops/action-gh-release` creates GitHub release with DMGs

### Development Notes
- Sparkle requires `com.apple.security.cs.disable-library-validation` entitlement for ad-hoc signed development builds
- `startingUpdater: false` + `sparkleUpdaterController.startUpdater()` for idempotent init
- Framework embedded at `Contents/Frameworks/Sparkle.framework`, rpath includes `@executable_path/../Frameworks`
- Keys must be generated by Sparkle's tool (`generate_keys`), not raw `openssl` — different base64 format

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
| `make release RELEASE=x.y.z` | Bump version, commit, tag, push (triggers release) |

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
 yabai is auto-detected: `/opt/homebrew/bin/yabai` (ARM) or `/usr/local/bin/yabai` (Intel). No manual symlink needed. Every yabai command runs with a 10s timeout (SIGTERM then SIGKILL) and async pipe drains, so slow/loaded yabai can neither wedge a refresh nor drop output.

### Config Reloading
Config reloads on every HUD open; hotkey, update-mode, and socket-health changes apply immediately from Settings (one owned monitor pair, no retained stale bindings, no restart).
