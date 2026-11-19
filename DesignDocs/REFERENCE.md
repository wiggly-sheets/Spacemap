# Spacemap Reference

## Quick Commands

| Command | Description |
|---------|-------------|
| `make help` | List every target (default) |
| `make run` | Build, install, and launch the app |
| `make dev1` | Uninstall the app (use before code changes) |
| `make dev2` | Reinstall and launch after code changes |
| `make build` | Build release binary only |
| `make app` | Build and assemble the universal .app bundle |
| `make app-arm` | Build and assemble the arm64 .app bundle |
| `make app-intel` | Build and assemble the x86_64 .app bundle |
| `make app-universal` | Build and assemble the universal .app bundle |
| `make clean` | Remove build artifacts |
| `make config` | Create default config file if missing |
| `make distconfig` | Overwrite config with defaults |
| `make dmg` | Build the arm64 and the x86_64 DMG |
| `make dmg-arm` | Build ARM64 DMG |
| `make dmg-intel` | Build Intel DMG |
| `make dmg-universal` | Build universal DMG |
| `make test` | Run unit tests via swift test |
| `make release-artifacts` | Build the DMGs and write `checksums.txt` |
| `make release VERSION=x.y.z` | Bump version, commit, tag locally, print the push command (no push) |
| `make install-cli` | Install CLI symlink to `/usr/local/bin/spacemap` |
| `make uninstall-cli` | Remove CLI symlink |
| `make permissions` | Show instructions for fixing Accessibility permission |

The old names `app-arm64`, `app-x86_64`, `dmg-arm64` and `dmg-x86_64` still work.

Only one instance runs per user. Launching the binary or CLI symlink again exits immediately; `--settings` is sent over the live socket first (falling back to a `spacemap://` deep link) and `--show-menu` uses the `spacemap://` deep link. The bundle declares `LSMultipleInstancesProhibited` and the app also has a runtime guard.

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
| `spacemap --status` | Print app path, config path, running state, and yabai availability; exit |
| `spacemap --print-config` | Print the resolved TOML without launching the app |
| `spacemap --update` | Forward an update check to the running app |
| `spacemap --update-font` | Forward a glyph-font update to the running app |
| `spacemap --config-preset NAME` | Apply a preset from `~/.config/spacemap/presets/` (switch saves edits into the outgoing preset first) |

## Key File Locations

| File | Purpose |
|------|---------|
| `~/.config/spacemap/config.toml` | User configuration (reloads on HUD open; Settings applies hotkeys immediately) |
| `~/.config/spacemap/presets/` | One complete config.toml per preset, applied from Settings > Advanced or `--config-preset` |
| `/Applications/Spacemap.app` | Local `make run` install |
| `/usr/local/bin/spacemap` | CLI symlink (if installed) |
| `$TMPDIR/spacemap_<username>.socket` (`NSTemporaryDirectory()`) | Unix domain socket for yabai signals |
| `Console.app` | View logs (filter by "spacemap") |

## Config Keys Reference (TOML tables in `~/.config/spacemap/config.toml`)

| Table | Key | Default | Description |
|-----|-----|---------|-------------|
| `[grid]` | `cols` / `rows` | 8 / 2 | Grid dimensions 1–32; oversize clamps to 32, undersize resets to the default |
| `[grid]` | `maxSpaces` | 16 | Max spaces to display, clamped 1–16 |
| `[grid]` | `cellStyle` | `rects` | `rects`, `hybrid`, `icons`, `thumbnails`, or `simple` |
| `[grid]` | `showMode` | `all` | `all` or `active` spaces |
| `[grid]` | `multiMonitorHUDMode` | `unified` | `unified` (one grid) or `separate` (one grid per display) |
| `[grid]` | `unifiedHUDVisibility` | `active` | In `unified` mode: `all` or `active` display |
| `[grid]` | `separateHUDVisibility` | `all` | In `separate` mode: `all` or `active` display |
| `[grid]` | `displayNavigationWrap` | `within` | Keyboard navigation: `within` one display or `between` displays |
| `[grid]` | `showSpaceNumbers` / `showSpaceNames` | true / true | HUD-cell labels (strip has its own `[glyphStrip]` key) |
| `[grid]` | `showIconStrip` / `showMultiAppIcons` | true / false | Per-cell app icons; per-window (true) or per-app (false) |
| `[grid]` | `hudIconSource` | `native` | Cell icons: `native` macOS images or `sbarFont` app-font glyphs |
| `[grid]` | `hudIconStripSeparate` | `false` | Give the HUD icon strip its own icon source |
| `[grid]` | `hudIconStripSource` | `native` | Strip icons when `hudIconStripSeparate` is true |
| `[appearance]` | `hudFontName` | `""` | HUD font family; empty means system |
| `[appearance]` | `hudFontSize` | `12` | Space-number point size, clamped 8...48 |
| `[appearance]` | `hudTextColor` | `""` | Optional hex override for HUD text. Empty follows the theme |
| `[appearance]` | `theme` / `mode` | `default` / `auto` | Color theme; `light`, `dark`, or `auto` |
| `[appearance]` | `backgroundAlpha` | 0.3 | Shared HUD opacity 0–1 when `matchBackgroundOpacity` is on |
| `[appearance]` | `backgroundStyle` | `glass` | `glass` or `solid`; solid at zero opacity hides the fill |
| `[appearance]` | `glassStyle` | `regular` | Glass sub-type: `clear` (native light material), `regular` (frosted), or `tinted` (accent over a chosen material) |
| `[appearance]` | `glassClearVariant` / `glassRegularVariant` / `glassTintedVariant` | 11 / 5 / 2 | Private `NSGlassEffectView._variant` finish per style, 0–21, freely chosen in Settings. Variant numbers and the probe approach follow [JulianWindeck/liquid-glass](https://github.com/JulianWindeck/liquid-glass) |
| `[appearance]` | `glassTintedMaterial` | `clear` | Material under the tint: `clear` or `regular` |
| `[appearance]` | `glassClearOpacity` / `glassRegularOpacity` / `glassTintedOpacity` | 0.05 / 0.35 / 0.35 | Per-glass-style opacity 0–1. Glass clamps to its floor (clear 0.35, regular 0.40, tinted 0.45) so it never becomes a hole. Used when `matchBackgroundOpacity` is off |
| `[appearance]` | `solidOpacity` | 0.35 | Solid HUD fill opacity 0–1 (no blur; zero is fully transparent) |
| `[appearance]` | `matchBackgroundOpacity` | false | Link all HUD styles to `backgroundAlpha`; the glass floor still applies |
| `[appearance]` | `hudShadow` | true | Draw HUD panel shadow |
| `[appearance]` | `hudCornerRadius` | 10 | Outer HUD panel corner radius, 0–60; space cells are unaffected |
| `[appearance]` | `spacesMatchBackground` | true | Clear cells, so the panel material shows through. When off, the cell layer below applies |
| `[appearance]` | `spacesBackgroundStyle` | `glass` | Cell layer: `none`, `solid`, or `glass` (only read when not matching) |
| `[appearance]` | `spacesGlassStyle` | `clear` | Cell glass sub-type: `clear`, `regular`, or `tinted` |
| `[appearance]` | `spacesGlassClearVariant` / `spacesGlassRegularVariant` / `spacesGlassTintedVariant` | 11 / 5 / 2 | Cell glass finish per style, 0–21 |
| `[appearance]` | `spacesGlassTintedMaterial` | `clear` | Material under a tinted cell fill |
| `[appearance]` | `spacesOpacity` | 0.5 | Cell fill or glass opacity 0–1 |
| `[appearance]` | `spacesCornerRadius` | 4 | Cell corner radius 0–60 for the custom cell layer |
| `[appearance]` | `uiScale` / `iconScale` | 0.5 / 0.5 | HUD scale / icon size, 0–1 |
| `[behavior]` | `hotkey` / `pinnedHotkey` | ctrl+space / none | Toggle hotkeys (applied immediately from Settings) |
| `[behavior]` | `glyphStripHotkey` | none | Show/hide hotkey for the glyph strip; session-only, never persisted |
| `[behavior]` | `hudMoveSpaceBackHotkey` / `hudMoveSpaceForwardHotkey` | none | Legacy HUD-only hotkeys that move the focused space one slot left or right. They still decode and are matched before `[hudKeys]`; edit the `moveSpaceBack`/`moveSpaceForward` actions instead |
| `[behavior]` | `hudNewSpaceHotkey` / `hudDeleteSpaceHotkey` / `hudCycleLayoutHotkey` | none | Legacy HUD-only hotkeys to create a space, delete the focused space, or cycle BSP, stack and float. They still decode and are matched before `[hudKeys]`; edit the `newSpace`/`deleteSpace`/`cycleLayout` actions instead |
| `[behavior]` | `hudPosition` | `center` | `center`, `top`, `bottom`, `custom` (table: `kind`, `x`/`y` fractions 0–1, optional `screen` display identity) |
| `[behavior]` | `autoHideTimeout` | 5 | Seconds before HUD hides (0 = never/pinned) |
| `[behavior]` | `useArrowKeys` / `useVimKeys` / `useExtendedKeys` | — | **Removed** — replaced by per-action `[hudKeys]` bindings |
| `[hudKeys]` | `<command> = ["<hotkey>", ...]`, e.g. `newSpace = ["a"]` | vim keys + arrows for movement, action keys for first/last/recent/close/new/delete/layouts; move-space and cycle-layout unbound | One command map for every HUD key action. Each command is a TOML string array, and each string is a hotkey in the same form the Hotkey parser accepts elsewhere (`"a"`, `"escape"`, `"ctrl+left"`, `"cmd+shift+a"`). An empty list (`newSpace = []`) leaves the command unbound. Commands: `left`/`right`/`up`/`down`, `first`, `last`, `recent`, `close`, `newSpace`, `newSpaceAndFocus`, `deleteSpace`, `layoutBSP`, `layoutStack`, `layoutFloat`, `cycleLayout`, `moveSpaceBack`, `moveSpaceForward` |
| `[behavior]` | `jumpToSpaceEnabled` | false | Number-key space jumps (multi-digit supported) |
| `[behavior]` | `focusSpaceOnWindowDrop` (+ `...Modifier`) | `never` (`command`) | `never`, `always`, or `modifier` (`command‖fn‖option‖control‖shift`) |
| `[behavior]` | `showHUDOnSpaceChange` | false | Auto-show HUD on yabai space change |
| `[behavior]` | `showBSPLayoutBadge` / `showStackLayoutBadge` / `showFloatLayoutBadge` | true | Which layout letters the HUD badge draws. Read only when `showSpaceLayout` is on |
| `[behavior]` | `hudAnimationsEnabled` / `hudAnimationStyle` / `hudEntranceStyle` | `Bool` / `HUDAnimationStyle` / `HUDEntranceStyle` | `true` / `natural` / `fade`; timing styles `natural`, `springy`, `fast`; entrances `fade`, `slideFromLeft`, `slideFromRight`, `slideFromTop`, `slideFromBottom`, `scale`. Off makes HUD and strip fades instant |
| `[behavior]` | `showHUDInteractionFeedback` | true | Draw typed-number and action notices over the HUD. Off hides the overlays only; actions still run |
| `[behavior]` | `spaceDropMode` | `content` | What a space drag does: `content` swaps the windows between spaces (any yabai build), `spaces` reorders the spaces themselves (needs a yabai build with space-move support) |
| `[behavior]` | `spaceDragFocus` | `stay` | Focus after rearranging spaces: `stay`, `destination`, or `source` |
| `[behavior]` | `windowDragFocus` | `destination` | Focus after moving an app icon to another space: `stay`, `destination`, or `source` |
| HUD drag | — | — | Drag a cell to rearrange spaces; drag an app icon to move its windows. Deduped icons move every window of the app, one-icon-per-window moves only that window |
| `[behavior]` | `showThumbnailWallpaper` | true | Draw the desktop wallpaper behind thumbnail cells. Off leaves the desktop transparent behind the windows |
| `[behavior]` | `presence` / `updateMode` | `menuBar` / `notify` | Where Spacemap appears: `dock`, `menuBar`, `both`, or `none`. `none` and `menuBar` use an accessory policy, so no Dock icon. Sparkle `auto‖notify‖off`; `off` disables automatic checks and downloads but keeps manual "Check for Updates" working |
| `[behavior]` | `menuBarDisplayMode` (+ `menuBarNearbyCount`) | `icon` (3) | `icon‖dots‖current‖nearby‖all`; nearby count clamped 1–16 |
| `[spaceNames]` | `showSpaceNames` / `namingMode`; names in `[spaceNames.names]` | true / `custom` | Per-space names plus `[spaceNameProfiles]` sets (see Settings). `namingMode = "auto"` names each space after the app of its leftmost visible window in the HUD cells, strip labels, and fuzzy name jumps; typed names stay saved for `custom` |
| `[glyphStrip]` | `enabled` / `theme` | false / inherits app | Enable the strip; empty theme follows the app theme |
| `[glyphStrip]` | `displayMode` | `floating` | `floating` panel or `menuBarItem` status item. Menu-bar mode keeps contents, clicks, hover and drags; drops shape, glass, free placement and vertical layouts |
| `[glyphStrip]` | `padding` / `lockPadding` | 4 / true | One padding for every side; unlock to use `horizontalPadding` and `verticalPadding` (0–40) |
| `[glyphStrip]` | `showSpaceNumbers` / `spaceLabelStyle` | true / `numbers` | Label run contents: the space number, the name from the active name profile, or both. A nameless space keeps its number; names shorten to 12 characters |
| `[glyphStrip]` | `showLayoutSuffix` / `showAppIcons` / `dedupeAppsPerSpace` / `maxIconsPerSpace` | true / true / true / 8 | Painted contents; layout letters follow `showBSPLayoutBadge` / `showStackLayoutBadge` / `showFloatLayoutBadge` |
| `[glyphStrip]` | `iconSize` / `indexSize` / `iconSpacing` / `indexPadding` / `autoResizeMaxLength` | 11 / 11 / 3 / 6 / 0 | Glyph metrics; auto-resize 0 is off, otherwise a width or height target |
| `[glyphStrip]` | `backgroundMaterial` / `shape` / `cornerRadius` / `borderEnabled` | none / none / 20 / true | Floating-strip backdrop. Menu-bar mode ignores these |
| `[glyphStrip]` | `glassStyle` / `matchHUDAppearance` / `matchBackgroundOpacity` | regular / false / false | Appearance inheritance and per-style opacity |
| `[glyphStrip]` | `glassClearVariant` / `glassRegularVariant` / `glassTintedVariant` / `glassTintedMaterial` | 11 / 5 / 2 / clear | Private glass finish per style, 0–21 |
| `[glyphStrip]` | `glassClearOpacity` / `glassRegularOpacity` / `glassTintedOpacity` / `solidOpacity` / `backgroundOpacity` | 0.05 / 0.35 / 0.35 / 0.35 / 0.35 | Per-material opacity; glass keeps its floor |
| `[glyphStrip]` | `position` / `orientation` / `verticalLayout` / `customX` / `customY` / `customScreen` / `lockPosition` | leftOfNotch / horizontal / inline / 0.5 / 0.5 / "" / false | Placement; free placement only for `position = "custom"`, stored as the same screen fraction plus display identity the HUD uses |
| `[glyphStrip]` | `hoverPadding` / `hoverCornerRadius` / `verticalPadding` / `margin` | 1 / 4 / 4 / 6 | Spacing and hover highlight |
| `[glyphStrip]` | `leftClickAction` / `rightClickAction` / `middleClickAction` | focusSpace / destroySpace / none | Segment click bindings |
| `[advanced]` | `socketHealthInterval` | 60 | Socket health check seconds (> 0); `showExtraWindows` lives here too. The Advanced pane also shows live Accessibility and Screen Recording status with request buttons and System Settings deep links |
| `[appFont]` | `updateMode` | `auto` | Glyph-font update policy (`manual` or `auto`); fonts are downloaded, not bundled |

## Development Workflow

1. `make dev1` (uninstalls app)
2. Remove Spacemap from System Settings → Privacy & Security → Accessibility
3. Make code changes
4. `make dev2` (rebuilds, reinstalls, launches)
5. Grant Accessibility permission when prompted

## Core Data Structures (`ConfigurationModels.swift` / `ThemeModels.swift` / `YabaiModels.swift`)

### `SpacemapConfig`
Stores the resolved configuration: decode, defaults, repair, and encode all walk the key table in `ConfigSchema.swift`.

| Property | Type | Source Config Key |
|----------|------|-------------------|
| `cols` | `Int` | `cols` |
| `rows` | `Int` | `rows` |
| `cellStyle` | `CellStyle` | `cellStyle` |
| `hotkey` | `HotkeyConfig` | `[behavior.hotkey]` |