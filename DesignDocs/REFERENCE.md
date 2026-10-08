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

## Config Keys Reference (TOML tables in `~/.config/spacemap/config.toml`)

| Table | Key | Default | Description |
|-----|-----|---------|-------------|
| `[grid]` | `cols` / `rows` | 8 / 2 | Grid dimensions (must be > 0) |
| `[grid]` | `maxSpaces` | 16 | Max spaces to display, clamped 1–16 |
| `[grid]` | `cellStyle` | `rects` | `rects`, `hybrid`, `icons`, `thumbnails`, or `simple` |
| `[grid]` | `showMode` | `all` | `all` or `active` spaces |
| `[grid]` | `multiMonitorHUDMode` | `unified` | `unified` (one grid) or `separate` (one grid per display) |
| `[grid]` | `unifiedHUDVisibility` | `active` | In `unified` mode: `all` or `active` display |
| `[grid]` | `separateHUDVisibility` | `all` | In `separate` mode: `all` or `active` display |
| `[grid]` | `displayNavigationWrap` | `within` | Keyboard navigation: `within` one display or `between` displays |
| `[grid]` | `showSpaceNumbers` / `showSpaceNames` | true / true | HUD-cell labels (strip has its own `[glyphStrip]` key) |
| `[grid]` | `showIconStrip` / `showMultiAppIcons` | true / false | Per-cell app icons; per-window (true) or per-app (false) |
| `[appearance]` | `theme` / `mode` | `default` / `auto` | Color theme; `light`, `dark`, or `auto` |
| `[appearance]` | `backgroundAlpha` | 0.3 | HUD transparency 0–1 |
| `[appearance]` | `hudShadow` | true | Draw HUD panel shadow |
| `[appearance]` | `uiScale` / `iconScale` | 0.5 / 0.5 | HUD scale / icon size, 0–1 |
| `[behavior]` | `hotkey` / `pinnedHotkey` | ctrl+space / none | Toggle hotkeys (applied immediately from Settings) |
| `[behavior]` | `glyphStripHotkey` | none | Show/hide hotkey for the glyph strip; session-only, never persisted |
| `[behavior]` | `hudPosition` | `center` | `center`, `top`, `bottom`, `custom` (+ `customHUDX`/`customHUDY` 0–1) |
| `[behavior]` | `autoHideTimeout` | 5 | Seconds before HUD hides (0 = never/pinned) |
| `[behavior]` | `useArrowKeys` / `useVimKeys` / `useExtendedKeys` | false / false / true | Keyboard navigation; fn key preserved as a modifier |
| `[behavior]` | `jumpToSpaceEnabled` | false | Number-key space jumps (multi-digit supported) |
| `[behavior]` | `focusSpaceOnWindowDrop` (+ `...Modifier`) | `never` (`command`) | `never`, `always`, or `modifier` (`command‖fn‖option‖control‖shift`) |
| `[behavior]` | `showHUDOnSpaceChange` | false | Auto-show HUD on yabai space change |
| `[behavior]` | `hideMenuBarIcon` / `updateMode` | false / `notify` | Headless menubar; Sparkle `auto‖notify‖off` |
| `[behavior]` | `menuBarDisplayMode` (+ `menuBarNearbyCount`) | `icon` (3) | `icon‖dots‖current‖nearby‖all`; nearby count clamped 1–16 |
| `[spaceNames]` | `showSpaceNames`; names in `[spaceNames.names]` | true | Per-space names plus `[spaceNameProfiles]` sets (see Settings) |
| `[glyphStrip]` | — | — | Full key table below |
| `[advanced]` | `socketHealthInterval` | 60 | Socket health check seconds (> 0); `showExtraWindows` lives here too |
| `[appFont]` | `updateMode` | `manual` | Bundled glyph-font update policy (`manual‖auto`) |

## Development Workflow

1. `make dev1` (uninstalls app)
2. Remove Spacemap from System Settings → Privacy & Security → Accessibility
3. Make code changes
4. `make dev2` (rebuilds, reinstalls, launches)
5. Grant Accessibility permission when prompted

## Core Data Structures (`ConfigurationModels.swift` / `ThemeModels.swift` / `YabaiModels.swift`)

### `GridConfig`
Stores parsed configuration values.

| Property | Type | Source Config Key |
|----------|------|-------------------|
| `cols` | `Int` | `cols` |
| `rows` | `Int` | `rows` |
| `cellStyle` | `CellStyle` | `cellStyle` |
| `hotkey` | `HotkeyConfig` | `[behavior.hotkey]` |
| `pinnedHotkey` | `HotkeyConfig` | `[behavior.pinnedHotkey]` |
| `glyphStripHotkey` | `HotkeyConfig` | `[behavior.glyphStripHotkey]` (session-only toggle) |
| `uiScale` | `Double` | `uiScale` |
| `theme` | `String` | `theme` |
| `autoHideTimeout` | `Int` | `autoHideTimeout` |
| `showMode` | `ShowMode` | `showMode` |
| `multiMonitorHUDMode` | `MultiMonitorHUDMode` | `multiMonitorHUDMode` |
| `unifiedHUDVisibility` | `SeparateHUDVisibility` | `unifiedHUDVisibility` |
| `separateHUDVisibility` | `SeparateHUDVisibility` | `separateHUDVisibility` |
| `displayNavigationWrap` | `DisplayNavigationWrap` | `displayNavigationWrap` |
| `maxSpaces` | `Int` | `maxSpaces` |
| `backgroundAlpha` | `Double` | `backgroundAlpha` |
| `hudShadow` | `Bool` | `hudShadow` |
| `mode` | `ThemeMode` | `mode` |
| `iconScale` | `Double` | `iconScale` |
| `showSpaceNumbers` | `Bool` | `showSpaceNumbers` |
| `showSpaceNames` | `Bool` | `showSpaceNames` |
| `showIconStrip` | `Bool` | `showIconStrip` |
| `showMultiAppIcons` | `Bool` | `showMultiAppIcons` |
| `hideMenuBarIcon` | `Bool` | `hideMenuBarIcon` |
| `glyphStrip` | `GlyphStripConfig` | `[glyphStrip]` |
| `menuBarDisplayMode` | `MenuBarDisplayMode` | `menuBarDisplayMode` |
| `menuBarNearbyCount` | `Int` | `menuBarNearbyCount` |
| `spaceNames` | `[Int: String]` | `[spaceNames.names]` |
| `spaceNameProfiles` / `activeSpaceNameProfileIndex` | `[SpaceNameProfile]` / `Int` | `[spaceNameProfiles]` |
| `useVimKeys` / `useArrowKeys` / `useExtendedKeys` | `Bool` | `useVimKeys` / `useArrowKeys` / `useExtendedKeys` |
| `jumpToSpaceEnabled` | `Bool` | `jumpToSpaceEnabled` |
| `hudPosition` / `customHUDX` / `customHUDY` | `HUDPosition` / `Double` | `hudPosition` / `customHUDX` / `customHUDY` |
| `showExtraWindows` | `Bool` | `showExtraWindows` |
| `showHUDOnSpaceChange` | `Bool` | `showHUDOnSpaceChange` |
| `updateMode` | `UpdateMode` | `updateMode` |
| `appFont` | `AppFontConfig` | `[appFont]` |
| `socketHealthInterval` | `Int` | `socketHealthInterval` |
| `focusSpaceOnWindowDrop` | `WindowDropFocusMode` | `focusSpaceOnWindowDrop` |
| `focusSpaceOnWindowDropModifier` | `WindowDropFocusModifier` | `focusSpaceOnWindowDropModifier` |

## Settings Categories

The Settings window keeps a permanent 180-point sidebar and renders one independent detail form at a time.

| Category | Scope |
|----------|-------|
| Grid | Layout, multi-monitor behavior, cell style, and visible window metadata |
| Space Names | Name visibility, per-space values, and named profiles (switchable from Settings or the menu bar) |
| Appearance | Theme, appearance mode, transparency, and scale |
| Behavior | Normal, pinned, and glyph-strip hotkeys, HUD placement, timeout, navigation, drop focus, menu bar, and updates |
| Glyph Strip | Always-visible menu-bar space strip: contents, appearance, click bindings, and placement |
| Debug/Advanced | Socket health interval |

Sidebar rows are full-width buttons. The selected row is highlighted and exposed to accessibility as selected; there is no sidebar-collapse control.

### `GlyphStripConfig`

Read from the `[glyphStrip]` table. A legacy bare `glyphStrip = true` boolean is still honoured and migrated on the next config repair. Numeric keys are clamped at the model boundary, so a hand-edited TOML cannot produce a degenerate layout.

| Key | Type | Default |
|-----|------|---------|
| `enabled` | `Bool` | `false` |
| `showSpaceNumbers` | `Bool` | `true` |
| `showLayoutSuffix` | `Bool` | `true` |
| `showAppIcons` | `Bool` | `true` |
| `dedupeAppsPerSpace` | `Bool` | `true` |
| `maxIconsPerSpace` | `Int` | `8` (0 = unlimited, then a `+N` overflow indicator) |
| `iconSize` | `Double` | `11.0`, clamped 6...24 |
| `indexSize` | `Double` | `11.0`, clamped 6...24 |
| `highlightCurrentSpace` | `Bool` | `true` |
| `backgroundMaterial` | `GlyphStripBackgroundMaterial` | `.none` |
| `glassAmount` | `Double` | `0.5`, clamped 0...1; continuous Liquid Glass tint, 0 = ultraclear, centre default, 1 = opaque/tinted (liquidGlass only; Settings slider shown tint-on-only) |
| `useThemeTint` | `Bool` | `true` (liquidGlass only; false = neutral pure `.headerView` frost, no fill overlay) |
| `shape` | `GlyphStripShape` | `.none` (no outline even with `borderEnabled`; otherwise the border follows the shape) |
| `backgroundOpacity` | `Double` | `0.35`, clamped 0.01...1.0 (solid only; Settings slider 1...100%) |
| `cornerRadius` | `Double` | `20.0`, clamped 0...40 (roundedRect only; capped to half strip height) |
| `margin` | `Double` | `6.0`, clamped 0...40; gap between the strip and the notch edge |
| `yOffset` | `Double` | `0.0`, clamped -10.0...10.0; vertical nudge, positive moves the strip down, 0 is centered |
| `hoverPadding` | `Double` | `1.0`, clamped 0...12; gap grown around the hovered segment's glyphs on both axes (symmetric) |
| `hoverCornerRadius` | `Double` | `4.0`, clamped 0...20; corner radius of the hover highlight, independent of `cornerRadius` |
| `iconSpacing` | `Double` | `3.0`, clamped 0...20; extra advance inserted between two adjacent app glyphs and before `+N` overflow |
| `indexPadding` | `Double` | `6.0`, clamped 0...20; advance between a space's index number and its first app glyph or placeholder |
| `showDisplaySeparators` | `Bool` | `true` |
| `showAddSpaceButton` | `Bool` | `true` (drawn bold at `indexSize + 2`) |
| `showPlaceholders` | `Bool` | `true` |
| `leftClickAction` | `GlyphStripAction` | `.focusSpace` |
| `rightClickAction` | `GlyphStripAction` | `.destroySpace` |
| `middleClickAction` | `GlyphStripAction` | `.none` |
| `position` | `GlyphStripPosition` | `.leftOfNotch` (`custom` enables `xOffset`; drag switches to `custom` and persists) |
| `xOffset` | `Int` | `0`, clamped -4000...4000; points right of the menu bar row's left edge (custom only) |
| `borderEnabled` | `Bool` | `true` (hairline outline; with material `.none` it follows `shape`, and `shape` `.none` draws nothing) |
| `theme` | `String` | `""` (follow main HUD) |

The strip's show/hide hotkey (`[behavior.glyphStripHotkey]`, default unbound) is session-only: it flips an in-memory flag that starts visible every launch and is never written to config. A disabled strip stays hidden until re-enabled.

Appearance is theme-driven: the strip resolves a fixed role palette against its theme — the current space, the add button and the hover highlight use `focused`, resting glyphs use `text`, and the solid material fills with `cellBg`. There are no per-element colour keys, and legacy colour keys from older configs are dropped on the next repair.

`iconSpacing` separates adjacent app glyphs and the `+N` overflow indicator, so a run of icons breathes. `indexPadding` covers the one boundary it does not: the gap between a space's index number and its first icon or placeholder, which is separate because the two gaps answer different things — one tracks icons within a run, the other separates the label from the run. Neither is applied around the display separator or the `+` button. Both also apply to the initials fallback drawn when the bundled font has no ligature for an app. The panel sizes its frame from the same gap array it draws with, so the content can never be clipped or leave a gap.

`position` is notch-aware. `auxiliaryTopLeftArea` is the unobscured strip to the **left** of the notch, so its `maxX` is the notch's left edge; `auxiliaryTopRightArea` is symmetric. `leftOfNotch` puts the strip's **right** edge `margin` short of that left edge, and `rightOfNotch` puts its **left** edge `margin` past the right edge, so the strip always sits *beside* the camera housing rather than inside it. `center` centres the strip on the midpoint of the notch gap. AppKit reports empty auxiliary rects on displays without a notch, so the two notch positions fall back to the corresponding screen edge and `center` falls back to the row's midpoint. `custom` places the strip `xOffset` points right of the row's left edge. The strip is always clamped inside the menu bar row and centred vertically in it.

`yOffset` is a vertical nudge in screen-reading terms: positive moves the strip **down**, into the screen interior and away from the menu bar's top edge, and negative moves it up. Unlike `x`, it is deliberately **not** clamped back into the menu bar row. The panel is ordered at `.statusBar` level, so a user who asks to nudge the strip down gets it moved — clamping would silently ignore the one thing the key is for. The panel is only a few points tall, so the worst a large offset does is overlap the first row of menu bar items.

The hover highlight is the segment's glyph **content box** — its slot trimmed by `segmentPadding` on each side, which is the empty space either side of the glyphs inside that slot — grown by `hoverPadding` on both axes and rounded at `hoverCornerRadius`. It is sized to the glyphs rather than to the 37.5pt menu bar row: the height is the segment's resolved text line box (from the real `indexSize`/`iconSize` metrics) plus twice `hoverPadding`, so the pill sits on the glyphs instead of filling the row, and it composites on top of whichever material is active. `hoverPadding` is a gap grown from the content box rather than an inset from the slot because growing only ever moves the highlight's edges outward, whereas an inset would shrink it on both axes and start clipping glyph edges once it passed `segmentPadding`. Hit-testing uses the full slot, while the highlight stays glyph-sized: a click lands anywhere in the segment, but the pill only covers the glyphs.

The notch gap is typically around 200pt wide on a 14" MacBook Pro (208pt at the default scaled resolution), so a full strip rarely fits inside it. `center` will therefore be partly occluded by the camera housing on most displays — prefer `leftOfNotch` or `rightOfNotch`.

`backgroundMaterial` selects what sits behind the glyphs: `none` draws nothing, `solid` fills the strip with the theme's `cellBg` at `backgroundOpacity`, and `liquidGlass` puts native glass behind the glyphs, masked to the configured shape and stroked with a theme-derived hairline. The solid fill spans the full panel height; the glass mask keeps a 2pt vertical inset so it never touches the menu bar edges. With material `.none` the border still follows the selected `shape` (`pill`/`roundedRect`/`bar`); `shape` `.none` draws no outline at all. `glassAmount` (0...1, default 0.5) drives the tint like the System Settings > Appearance > Liquid Glass slider: 0 is ultraclear (no tint), the centre is the default, 1 is opaque/tinted. There is no public blur radius API, so the amount modulates the glass `tintColor` alpha (`0.08 + 0.30*t`, unset at/below 0.02) plus a `cellBg` fill overlay (`0.10 + 0.55*t`); view alpha stays 1.0. Tint-off is pure neutral frost: the pre-26/`NSVisualEffectView` fallback uses `.headerView` at full opacity (never translucent, so no warm menu bar bleeds through) with an achromatic mid-gray hairline instead of the theme-blended stroke. The pre-26 tint-on fallback uses saturated `.popover` at/above centre, lighter `.menu` below. `shape` picks the outline the material is drawn in: `pill` is a capsule with fully rounded ends, `roundedRect` is a rounded rectangle at `cornerRadius` (capped to half the strip height), and `bar` is one continuous bar with square ends. The same shape masks the glass layer. The hover highlight always composites on top at a fixed subtle tint, in the theme's `focused` colour.

Glyph verticals: every run draws from one shared baseline at a 1pt drop (`glyphDrop`); icon-font runs lift 1.5pt (`appGlyphLift`) because sketchybar-app-font ink sits low next to system digits. The trailing `+` add button draws bold at `indexSize + 2`.

The strip is theme-driven: every layer resolves to one of the theme's colours (`focused`, `text`, `cellBg`), with no hex codes and no per-element colour keys. Older configs that still carry colour keys have them dropped on the next repair.

`showDisplaySeparators` draws a `│` between spaces on different displays. Every space from every display is rendered on the single strip, in global-index order, and indexes are never renumbered per display — matching the SketchyBar config this replaces, which set `ignore_association = true` so secondary-display spaces still appeared on the main bar.

`highlightCurrentSpace` off does not merely recolour the focused space: it removes the focused state entirely, so the current space resolves to the same colour, alpha and fill as every other space and hovering it behaves like hovering any other segment.

### Enums

- **`CellStyle`** — `.rects`, `.hybrid`, `.icons`, `.thumbnails`, `.simple`
- **`ShowMode`** — `.all`, `.active`
- **`ThemeMode`** — `.light`, `.dark`, `.auto`
- **`UpdateMode`** (Sparkle) — `.auto`, `.notify`, `.off`
- **`AppFontUpdateMode`** (glyph font) — `.manual`, `.auto`
- **`MenuBarDisplayMode`** — `.icon`, `.dots`, `.current`, `.nearby`, `.all`
- **`WindowDropFocusMode`** — `.never`, `.always`, `.modifier`
- **`WindowDropFocusModifier`** — `.command`, `.function` (`fn`), `.option`, `.control`, `.shift`
- **`HUDPosition`** — `.center`, `.top`, `.bottom`, `.custom(x, y)`
- **`GlyphStripBackgroundMaterial`** — `.none`, `.solid`, `.liquidGlass`
- **`GlyphStripShape`** — `.none`, `.pill`, `.roundedRect`, `.bar`
- **`GlyphStripAction`** — `.none`, `.focusSpace`, `.destroySpace`, `.moveWindowHere`, `.toggleFullscreen`, `.floatWindow`, `.balanceWindows`, `.mergeWindows`
- **`GlyphStripPosition`** — `.leftOfNotch`, `.rightOfNotch`, `.center`, `.custom`
- **`MediaKey`** — `play-pause`, `next-track`, `previous-track`, `volume-up/down`, `mute`, `brightness-up/down`

### `YabaiSpace`
`id` (Int), `label` (String), `index` (Int), `display` (Int), `windows` ([Int]), `hasFocus` (Bool)

### `YabaiWindow`
`id` (Int), `app` (String), `frame` (CGRect), `space` (Int), `isHidden` (Bool), `isMinimized` (Bool)

### `GridState`
`config` (GridConfig), `spaces` ([YabaiSpace]), `windows` ([YabaiWindow]), `displayBounds` (CGRect), `focusedIndex` (Int?)

### `AppTheme`
`background`, `focused`, `text`, `dropTarget`, `cellBg`, `cellBgFocused`, `rect1`, `rect2`, `rect3` (all `UInt32` hex). The strip resolves a fixed role palette against its theme (`focused` for current space/add/hover, `text` for resting glyphs, `cellBg` for the solid fill).

## Key Classes

| File | Key Types | Responsibility |
|------|-----------|----------------|
| `App.swift` + `ApplicationLifecycleService.swift` | `spacemapApp` | Entry point, menubar, settings window, launch checks |
| `HUDWindowController.swift` + `HUDInput`/`HUDDisplay`/`HUDStateSync` | `HUDWindowController` | NSPanel lifecycle, show/hide, auto-hide timer, state refresh |
| `GridView.swift` | `GridView` | SwiftUI grid container, cell layout, theme |
| `CellView.swift` | `CellView` | Per-cell rendering (rects/icons/thumbnails), space names |
| `GridLayout.swift` | `GridLayout` | Pure geometry: cell/gap/padding math, slot frames, hit-test, window→cell transforms (guarded: `cols > 0`, spaces clamped 0–16, zero-size frames return nil/empty) |
| `YabaiClientImpl.swift` + `YabaiService.swift` | `YabaiClientImpl` | yabai CLI wrapper, space/window queries, signal management (10s command timeout, async pipe drain) |
| `Config.swift` (facade) + `ConfigLoader`/`TOMLParser`/`ConfigValues` | `Config` | Config load/save/parse; invalid fields self-heal individually after `config.toml.bak` backup |
| `HotkeyMonitor.swift` + `HotkeyService`/`HotkeyHandler` | `HotkeyMonitor` | Global CGEventTap for hotkey capture (normal, pinned, glyph-strip bindings) |
| `SocketListener.swift` | `SocketListener` | Unix domain socket server for yabai signals (mode 0600, non-blocking clients) |
| `WindowDragHandler.swift` + `WindowDragService` | `WindowDragHandler` | Drag-and-drop detection via CGEventTap |
| `ConfigurationModels.swift` / `ThemeModels.swift` / `YabaiModels.swift` | `GridConfig`, `YabaiSpace`, `AppTheme` | Data structures (split by domain; no `Models.swift`) |
| `GlyphStrip.swift` + `GlyphStripPanel.swift` | `GlyphStrip` | Menu-bar strip model (pure) + panel/view (AppKit) |
| `SettingsView.swift` + `SettingsGrid`/`SettingsSpaceNames`/`SettingsAppearance`/`SettingsBehavior`/`SettingsGlyphStrip`/`SettingsAdvanced` | `SettingsView` | Permanent category sidebar with separate live-save detail forms |
| `SettingsWindowController.swift` | `SettingsWindowController` | AppKit window wrapper for SettingsView |
| `ThumbnailCache.swift` + `ThumbnailCompositor`/`ThumbnailRequestBuilder` | `ThumbnailCache` | ScreenCaptureKit capture, per-space caching (macOS 14+) |
| `IconCache.swift` | `IconCache` | App icon cache to avoid repeated NSWorkspace lookups |
| `ThemeManager.swift` + `ThemeService` | `ThemeService` | Loads `.smthemes` files, seeds built-in themes on first launch |

## Yabai Integration (`YabaiClientImpl.swift`)

Shells out to yabai binary (auto-detected: `/opt/homebrew/bin/yabai` for ARM, `/usr/local/bin/yabai` for Intel). Every command carries a 10s timeout (SIGTERM then SIGKILL) and both pipes drain asynchronously, so a loaded system can neither wedge a refresh nor silently drop output.

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
- One owned monitor each for normal, pinned, and glyph-strip bindings; changed bindings apply without retaining old shortcuts, media shortcuts fire on key-down only
- Fails open when Accessibility is revoked: taps release immediately and unrelated keys pass through pinned HUDs
- Polls every 2s until Accessibility permission granted

### `SocketListener.swift`
- Unix domain server at `/tmp/spacemap_<username>.socket` (created mode 0600, clients non-blocking)
- Listens for yabai signal commands: `0` (refresh), `1` (show), `2` (hide), `3` (settings)
- Periodic health check via `fcntl(fd, F_GETFD)` + file existence

### `WindowDragHandler.swift`
- Second CGEventTap (listenOnly, tailAppend)
- Tracks mouse drag events while HUD visible
- Identifies frontmost window via `NSWorkspace.shared.frontmostApplication`
- Correlates mouse position with cell hit-rectangles

## Theme System

Each theme defines 9 hex colors in `AppTheme` (`background`, `focused`, `text`, `dropTarget`, `cellBg`, `cellBgFocused`, `rect1`, `rect2`, `rect3`). Edit `.smthemes` files in `~/.config/spacemap/themes/`.

Available themes: `default`, `tokyonight`, `catppuccin`, `monokai-dark`, `monokai-light`, `dracula`, `ayu`, `github`, `vscode`, `xcode`, `nord`, `atom-one-dark`

## Signal Integration

- Commands: `0`=refresh, `1`=show, `2`=hide, `3`=settings
- yabai emits `spacemap_space_changed:1` via signal on space change

## UI Scaling

- `UI_SCALE` range: 0.0–1.0
- Effective scale mapping: `0.5 + uiScale * 3.5` (0→0.5x, 1→4.0x)
- `ICON_SCALE` range: 0.0–1.0
- Effective icon scale: `0.2 + iconScale * 0.8` (0→0.2x, 1→1.0x)
