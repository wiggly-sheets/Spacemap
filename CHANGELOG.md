# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0]

### Added
- Optional always-visible glyph strip in the menu bar row, showing each yabai space's index plus a sketchybar-app-font glyph per window. A new **Glyph Strip** settings pane and `[glyphStrip]` config table control contents (`showSpaceNumbers`, `showLayoutSuffix`, `showAppIcons`, `dedupeAppsPerSpace`, `maxIconsPerSpace`), appearance (`iconSize`, `indexSize`, `iconSpacing`, `indexPadding`, `highlightCurrentSpace`, `backgroundMaterial`, `glassAmount`, `useThemeTint`, `shape`, `backgroundOpacity` solid-only 0.01...1.0, `cornerRadius`, `margin`, `yOffset`), decoration (`showDisplaySeparators`, `showAddSpaceButton`, `showPlaceholders`, `borderEnabled`, `theme`), click bindings (`leftClickAction`, `rightClickAction`, `middleClickAction`) and `position` (new `custom` value with `xOffset`). The former bare `[behavior] glyphStrip = true` boolean is still read and migrated on the next config repair.
- Space-name profiles: named sets of space names with an active index, edited in a dedicated Settings section and switchable from Settings or the menu bar. Out-of-range indexes repair to 0; an empty list repairs to Default.
- Session-only glyph-strip show/hide hotkey (`[behavior.glyphStripHotkey]`, default unbound). It flips an in-memory flag that starts visible every launch and is never written to config.

### Changed
- The glyph strip's palette is now theme-driven with no per-element colour keys: the current space, the add button and the hover highlight use the theme's `focused` role, resting glyphs use `text`, and the solid material fills with `cellBg`. Per-element colour keys (`currentSpaceColor`, `dimmedColor`, `indexColor`, `iconColor`, `hoverColor`, `backgroundColor`, `separatorColor`, `placeholderColor`, `addColor`) are removed; the legacy `backgroundStyle` key is migrated to `backgroundMaterial` + `shape` (none → none, pill → solid + pill, bar → solid + bar, roundedRect → solid + roundedRect, liquidGlass → liquidGlass + roundedRect).
- `yOffset` (default `0.0`, clamped -10...10): nudge the glyph strip vertically in screen-reading terms, so a positive value moves it down into the screen interior. Deliberately not clamped back into the menu bar row, since the panel is ordered at `.statusBar` level.
- Liquid glass now uses a continuous `glassAmount` slider (0...1, default 0.5) mirroring System Settings > Appearance > Liquid Glass — 0 is ultraclear, centre is default, 1 is opaque/tinted — driving the native glass `tintColor` alpha plus a fill overlay (view alpha stays 1.0). The old `glassStyle` key (`blurred`/`transparent`) still decodes to 0.5/0.15.
- `indexPadding` (default `6.0`, clamped 0...20): the gap between a space's index number and its first app glyph or placeholder. Distinct from `iconSpacing`, which tracks icons within a run and before `+N` overflow.
- Show gated controls only where they apply: the Glass Amount slider only for liquidGlass while Theme Tint is on, Background Opacity only for solid, Corner Radius only for roundedRect.
- Solid fills span the full panel height while the glass mask keeps a 2pt vertical inset; with material `none` the outline follows the selected shape, and shape `none` draws no outline even with the border on.
- Glyph verticals share one baseline with a 1pt drop; icon-font runs lift 1.5pt to sit with system digits, and the `+` add button draws bold at `indexSize + 2`.
- Clicks hit the full slot while the hover pill stays glyph-sized (symmetric `hoverPadding` growth on both axes).
- Preserved the `fn` modifier end to end (`maskSecondaryFn` record/serialize/match) across hotkeys and drop-focus modifiers.

### Fixed
- Size the glyph strip's hover highlight to the glyphs it covers on both axes, and stop hover arming from anywhere in the 37.5pt menu bar row. The highlight is now the segment's glyph box grown by `hoverPadding` (default `1`, radius `4`) while clicks hit the full slot, so it sits on the glyphs rather than 1.5pt off and a few points too large.
- Draw every glyph segment at its own slot's horizontal position. Segment 0's first run was drawn 3pt right of its slot, and a segment with no runs spent no leading pad at all — the pad was applied per run — so every later segment drifted 3pt further left of the frame the panel sized itself from. The pen now spends the leading pad once per segment, before its runs.
- Honour `highlightCurrentSpace = false` for real. The flag only swapped the focused space's colour for the dimmed one, so the current space stayed visually distinct; it now resolves to byte-identical styling — colour, alpha and fill — so nothing marks it out, and hovering it behaves like hovering any other segment.
- Show spaces from every display on the one strip, in global-index order, matching the SketchyBar config this replaces (which set `ignore_association = true` for exactly this). Spaces are never renumbered per display and indexes are never assumed contiguous.
- Stop the glyph strip inventing spaces that do not exist. It iterated a fixed `1...maxSpaces` range, so every index past the last space yabai reported got a ghost segment. It now iterates the spaces yabai actually returned, which are global and not necessarily contiguous: real indexes are rendered in order, indexes that no longer exist are simply absent, display separators compare consecutive *rendered* spaces rather than `index + 1`, and click actions carry the real yabai index.
- Give adjacent app glyphs room to breathe with a new `iconSpacing` key (default `3.0`, clamped 0...20). The gap is applied between two app glyphs and before the `+N` overflow, and the panel measures its frame from the same gap array it draws with, so content cannot be clipped or leave a gap.
- Space the empty-space placeholder off the index with `indexPadding` and the `+N` overflow off the last icon with `iconSpacing`, so neither glues to its neighbour.
- Place the glyph strip beside the notch instead of inside it: `leftOfNotch` and `rightOfNotch` had their anchors inverted, so the strip started at the notch edge and extended into the camera housing. Both now anchor the strip's *outer* edge to the notch and are verified against the real notch geometry.
- Order the glyph strip front on every refresh instead of only after its panel already existed, so it is no longer created-but-never-shown until some later settings change.
- Track the glyph strip with an always-active tracking area, so hover and the hover pill work while Spacemap is not the active app.
- Anchor the glyph strip to the notch with `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` and a new `margin` key, instead of the far screen edges, and recompute on display and resolution changes.
- Honour each Material+Shape combo: `none` draws nothing, `solid` fills the strip with `cellBg` at `backgroundOpacity` (Settings slider 1...100%), and `liquidGlass` masks native glass to `shape` (`none` draws no shape; `pill`, `roundedRect` at `cornerRadius`, `bar`).
- Take the first click on the glyph strip without requiring Spacemap to be active, log failed yabai commands triggered from the strip instead of swallowing them, and report a font that exists but cannot be parsed.
- Drain yabai subprocess output without losing data when the system is under load.
- Time out every yabai command after 10s (SIGTERM then SIGKILL) and create the signal socket mode 0600 with non-blocking clients.
- Guard grid math at the boundaries: `cols > 0`, spaces clamped 0...16, zero-size display/cell frames return nil/empty instead of garbage.
- Clamp all glyph-strip numerics at the model boundary so a hand-edited TOML cannot produce a degenerate layout.
- Keep separate-display HUD cells aligned with their display-specific click and drag targets.
- Keep pinned HUD input state and focused-window drag fallback synchronized across refreshes.
- Keep window-drag event taps responsive and recover after macOS disables them.
- Resolve HUD themes once per render and keep application colors stable across launches.
- Release HUD and global-hotkey capture immediately when Accessibility is revoked, and let unrelated keys pass through pinned HUDs.
- Keep one owned pair of hotkey monitors, apply changed bindings without retaining old shortcuts, and trigger media shortcuts only on key-down.
- Apply update-mode and socket-health changes without requiring an app restart.
- Present and activate the real first-launch choices for login and update preferences.
- Preserve prior Sparkle appcast entries while replacing a duplicate current version.
- Preserve custom Settings values, coordinate hotkey recordings, restore window placement, and repair invalid configuration values.
- Reuse the owned About window instead of messaging an undefined app-delegate selector.
- Keep socket clients and yabai commands from blocking app input, shutdown, or state refreshes.
- Refresh full menu-bar previews for workspace topology changes and keep menu titles synchronized with hotkey changes.
- Package every localization with valid Unicode text, and reject release tags that disagree with the app version.
- Compare complete grid state instead of treating states with the same focused space as equal.

### Removed
- Removed unused icon and thumbnail cache facade modules.
- Removed unused duplicate Settings and configuration owner types.
- Removed unused duplicate menu-bar owner types.

## [1.0.39] - 2026-08-15

### Fixed
- Let Settings record and match media-key hotkeys.
- Prevent duplicate normal and pinned HUD hotkey bindings.


## [1.0.38] - 2026-08-08

### Fixed
- Made the HUD's typed space number use the active theme's text color.

## [1.0.37] - 2026-08-08

### Changed
- Redesigned the README with a visual project overview, install guide, feature tour, configuration reference, and troubleshooting flow.

### Fixed
- Keep menu-bar workspace dots responsive by skipping unnecessary window-geometry queries.
- Release HUD keyboard capture and hide the HUD immediately when Accessibility permission is revoked.
- Made CI icon-preload tests independent of the runner's installed apps.


## [1.0.36] - 2026-08-08

### Fixed
- Restored Settings form layout and full window sizing instead of collapsed, unformatted content.

## [1.0.35] - 2026-08-08

### Fixed
- Prevented HUD cells from applying UI scale twice; restored centered sizing and HUD keyboard navigation wiring.
- Preserve one shared HUD controller across lifecycle, hotkey, menu bar, and deep-link paths.
- Keep Settings windows alive and activate the app when opening them.
- Restored HUD window-drag hover/drop handling and custom panel-position persistence.

### Changed
- Decomposed TOML parsing, thumbnail request/compositing, and HUD coordinate transforms behind focused modules.
- Removed unused composition modules, centralized menu-bar preview signal policy, and consolidated command-line tool operations.
- Split model declarations into configuration, theme, and yabai domain files.
- Refactored Config.swift from 685-line monolith to 36-line thin facade delegating to ConfigLoader/TOMLParser. Removed duplicated TOML lexer/serialization code and the duplicated hotkey() nested function.
- Added ConfigValuesProtocol, TOMLParserProtocol, and ConfigLoaderProtocol protocol interfaces for all config modules.
- Added protocol-based unit tests (ConfigFacadeTests) verifying Config facade delegation to ConfigLoader/TOMLParser.
- Added ConfigValues init(from: GridConfig) and ConfigLoader.save(_ config: GridConfig, to path:) for GridConfig ↔ ConfigValues conversion.

## [1.0.34] - 2026-08-07

### Added
- Added space jumps using number keys.

## [1.0.33] - 2026-08-05

### Changed
- Icon strips now order app icons by on-screen window position (left-to-right, then top-to-bottom) instead of yabai's raw window order.

## [1.0.32] - 2026-08-01

### Added
- Added optional number-key space jumps, including multi-digit space numbers and HUD feedback.
- Added Appearance setting to draw HUD panel shadow; default enabled.
- Added live yabai process and socket diagnostics to Advanced settings.
- Added a `spacemap(1)` manual page generated with scdoc and linked automatically alongside the CLI.

### Fixed
- Adaptive menu-bar workspace dots now keep refreshing after space changes.

## [1.0.31] - 2026-07-30

### Fixed
- The About window License tab now gives its scrollable MIT License text a stable visible layout.

## [1.0.30] - 2026-07-30

### Fixed
- Background-only app records with no Accessibility window reference are no longer treated as visible windows merely because their owner is a regular macOS app.

## [1.0.29] - 2026-07-30

### Fixed
- Icon strips now retain floating and extra windows accepted by the same display filter used by rectangle and hybrid views.

## [1.0.28] - 2026-07-30

### Added
- Added a polished Finder DMG with a gray-and-black grid background, installation instructions, and a drag-to-Applications arrow.
- Added a native About Spacemap window with app identity, version, copyright, Help, and Check for Updates actions.
- Added macOS 26 adaptive app-icon support while retaining the legacy `.icns` fallback.

### Changed
- Changed the app bundle and URL-scheme identifiers from `com.jsheffie.spacemap` to `com.zm.spacemap` for the independently maintained fork.
- Capitalized the packaged executable as `Spacemap` while retaining lowercase `spacemap` for the command-line symlink.
- Moved About Spacemap above Settings and redesigned its native window with About, Contributors, License, and Software Used tabs.

### Fixed
- Fixed release builds using the previous Git tag instead of the version declared in `VERSION`.

## [1.0.27] - 2026-07-29

### Fixed
- Keyboard input is released immediately if Accessibility permission is revoked while the HUD is visible.

## [1.0.26] - 2026-07-29

### Changed
- The visible HUD now consumes keyboard input after handling its own navigation and Settings shortcuts, preventing keystrokes from reaching other apps.

## [1.0.25] - 2026-07-29

### Changed
- Enlarged menu-bar workspace dots and let wide grid layouts use more horizontal space for legibility.

## [1.0.24] - 2026-07-29

### Changed
- Expanded focus-after-window-drop behavior to Never, Always, or While Holding Modifier, with Command, Fn, Option, Control, and Shift choices.

## [1.0.23] - 2026-07-29

### Added
- Added configurable menu-bar workspace previews for the current space, nearby spaces, or every active space, using live yabai window geometry.
- Added a compact menu-bar dot-grid mode that mirrors the configured workspace layout and highlights the focused space.

### Changed
- Menu-bar preview settings now stay hidden while the menu-bar icon itself is disabled.
- The all-spaces menu-bar preview now renders every space at full size in one horizontal row.
- Miniature menu-bar windows now have visible separation between adjacent panes.

## [1.0.22] - 2026-07-29

### Changed
- Replaced the JSONC config with TOML-only configuration at `~/.config/spacemap/config.toml`.
- Organized TOML settings into the same Grid, Space Names, Appearance, Behavior, and Advanced sections used by Settings.
- Removed obsolete config aliases, older-yabai classification compatibility, redundant macOS 13 availability branches, and stale config decoding infrastructure.

## [1.0.21] - 2026-07-29

### Added
- Added an off-by-default setting to show the HUD automatically whenever yabai changes spaces.
- Added `spacemap --space <selector>` for power-user and skhd navigation that focuses yabai spaces and shows the HUD, supporting indices 1–16, directional selectors, and labels.

### Fixed
- Yabai space-change signals now use macOS's system netcat so Homebrew netcat installations cannot break HUD updates.
- Exit-only CLI commands now run before AppKit startup, and `--trigger` toggles the existing HUD through its socket instead of launching a transient second HUD.


## [1.0.20] - 2026-07-29

### Added
- Added a Hybrid cell style that preserves rectangle rendering while centering a larger, proportionally scaled app icon in every window rectangle.

### Changed
- Moved space-number labels closer to the top-left while preserving proportional insets across HUD sizes.
- Moved Show Extra Windows into Debug/Advanced settings while preserving its explanatory help text.

### Fixed
- Hybrid cells, icon strips, and thumbnails now combine yabai window metadata with cached macOS app activation policy, retaining regular app windows even when AX fields disappear while Show Extra Windows controls utility/background records.
- Global hotkeys now recover without an app restart after Accessibility permission changes, event-tap invalidation, system disablement, or delayed tap creation.


## [1.0.19] - 2026-07-29

### Changed
- Thumbnail cell style now refreshes every visible space when the HUD opens instead of updating only the focused space after navigation.
- Thumbnail capture now renders directly at the cell's backing resolution, limits concurrent window captures, and debounces duplicate refresh events.
- Thumbnail cells observe atomic cache updates directly instead of rebuilding HUD panels, and each cell draws its thumbnail only once.
- Icon-style cells now render every yabai window, use yabai geometry for correct spatial placement, give one window the full cell, and divide two-window layouts into exact spatial halves.

### Fixed
- Thumbnail captures now exclude the Spacemap HUD and deterministically compose each space from its own yabai windows.
- Startup prewarming and atomic full-cache generations prevent mismatched, partially loaded, or stale space thumbnails.
- Thumbnail capture now rejects yabai's non-accessible helper-window records while including unmanaged on-screen overlays such as Raycast on the currently visible space.
- Space-number labels now keep a consistent scaled inset from cell edges at every HUD size.

## [1.0.18] - 2026-07-27

### Fixed
- Deep-link parsing now handles opaque `spacemap:action` URLs consistently across supported macOS versions.


## [1.0.17] - 2026-07-27

### Added
- Added `spacemap://` deep links for toggling or pinning the HUD, opening Settings or the menu-bar menu, and revealing the config file or themes folder.

## [1.0.16] - 2026-07-25

### Added
- Added an optional pinned HUD hotkey that toggles a permanently visible HUD independently of the normal timed hotkey.
- First-launch CLI installation now creates `/usr/local/bin` when possible and offers an explicit administrator-authorized fallback when macOS protects that location.
- Repository security policy documenting supported versions, vulnerability reporting, and expected disclosure handling.
- Repository support policy documenting where to ask for help and what information to include.
- Dropping a window onto an empty grid slot now creates any missing yabai spaces before moving the window there.

### Changed
- Settings sidebar categories now have roomier vertical spacing and larger click targets.
- Menu bar actions now use native SF Symbols for faster visual scanning, including Settings, CLI installation, updates, restart, permissions, and Quit.
- Settings category headings and sidebar labels now use larger, more prominent typography.
- Clarified the SwiftPM ignore guidance so `Package.resolved` is no longer presented as an ignored file in this repository.
- The canonical config file is now `~/.config/spacemap/spacemap.jsonc`; existing `config` files migrate automatically.
- Config loading now supports schema-backed JSON with JSONC comments, while still accepting legacy `key=value` files during migration.
- Hotkey parsing and triggering now support common media keys such as play/pause, next, previous, mute, volume, and brightness.
- Hotkey recorder now uses a more native inline control with a clear button to disable the current binding.
- Hotkey recorder now captures media keys directly and presents the selected binding in a native-style inline control.
- Settings window styling now leans more on native form chrome, lighter headers, and system background treatment.
- Settings view now uses segmented controls for small choice sets and tighter native-style footnote helpers.
- Settings window now uses a System Settings-style sidebar to group controls by section.
- Behavior settings can now optionally focus a destination space after a window is dropped there; the option defaults to off.
- Settings sidebar is now permanently visible, highlights the selected category, and uses full-row category buttons that reliably navigate the settings form.
- Each settings sidebar category now opens a distinct detail view instead of scrolling through one continuous form.
- User, contributor, developer, support, reference, roadmap, and agent documentation now describe the category-based Settings interface consistently.
- Moved the Command-Line Tool installer below the permission shortcuts in the menu-bar menu.

### Fixed
- CLI installation now validates its destination and never removes an unrelated file or symlink at `/usr/local/bin/spacemap`.
- JSON/JSONC config self-healing now runs on every load and preserves valid fields while repairing missing, mistyped, or out-of-range values.
- Hotkey recording now captures events delivered to the active Settings window and cleans up event monitors when the recorder disappears.


## [1.0.15] - 2026-07-25

### Fixed
- Release builds now ad-hoc sign and strictly verify every app bundle when a Developer ID certificate is unavailable, keeping Sparkle updates installable.

## [1.0.14] - 2026-07-25

### Added
- Configurable multi-monitor HUD modes: per-display overlays or a unified display map.
- Unified-grid visibility preference for showing the complete grid on the active display or every display.
- Separate-HUD visibility preference for showing all displays or only the display with yabai's focused space.
- Keyboard-navigation display wrapping preference: stay within the focused display or wrap across displays.

### Fixed
- Cross-display navigation now leaves a display at its grid-wrap edge instead of cycling through that display's spaces.
- Release automation now verifies the Sparkle public/private key pair before signing, preventing improperly signed updates from being published.
- Startup now warns when macOS “Displays have separate Spaces” is disabled.
- HUD reuses a prewarmed grid snapshot so active-space highlighting and app icons appear with the panel instead of a moment later.

### Changed
- Shifted in-cell space numbers slightly inward for more comfortable padding from the top-left edge.


## [1.0.13] - 2026-07-25

### Added
- `ConfigReader.keyCodeToSymbolicString(_:)` helper for keyCode→symbolic string conversion
- `ConfigReader.hotkeyToString(keyCode:modifiers:)` overload for raw keyCode/modifier encoding

### Changed
- `navigateSpace` now respects visible cells (active showMode, 16-space cap) instead of raw indices
- `ThemeManager.hex()` is now `static`
- `SettingsView.hotkeyStringFrom()` delegates to `ConfigReader.hotkeyToString()` (code dedup)
- `isMRUSpacesEnabled` check deferred to background queue so it no longer blocks startup
- yabai alert informative text now includes GitHub link

### Fixed
- Keyboard space navigation now skips empty placeholder cells, wraps correctly in incomplete rows and columns, and updates the HUD optimistically while focus changes are pending.
- `isYabaiRunning()` cache protected with `NSLock` to prevent data races
- `SettingsWindowController` no longer uses deprecated `setFrameUsingName`/`setFrameAutosaveName` pair
- `findBestGridLayoutIndexFor` dead conditional `layouts.isEmpty ? 0 : 0` simplified to `0`
- `ThumbnailCache` captures at 1x display size instead of 2x (perf/memory)
- `CellView` computed `filteredWindows` once instead of calling `windowFilter` twice per render
- `LAUNCH_AT_LOGIN` removed from SettingsView config save (handled by ServiceManagement, not file)


## [1.0.12] - 2026-07-25

### Fixed
- Release artifacts are built in the GitHub Actions workspace so they are available to the GitHub Release upload action.

## [1.0.11] - 2026-07-25

### Added
- `make release RELEASE=x.y.z` target for one-command releases
- `scripts/generate-changelog.sh` auto-moves `[Unreleased]` to versioned entry on release
- CHANGELOG gate in `make release` ensures entries exist before tagging
- Release checklist in DesignDocs/AGENTS.md
- `VERSION` file as fallback for version derivation

### Changed
- Revised installation guidance and refreshed the project icon in the README.

### Fixed
- Sparkle updater double-start bug — `updater.start()` replaced with idempotent `startUpdater()`
- Sparkle `sign_update` download URL updated to Sparkle 2.9.4 (2.7.1 was 404)
- SettingsView redundant config saves on every mode change
- Empty version strings in Info.plist when git tags missing
- VERSION derivation falls back to Info.plist when no tags or VERSION file exist


## [1.0.10] - 2026-07-24

### Changed
- Renamed the application and bundle consistently to `Spacemap` / `Spacemap.app` across the app, installer, documentation, and release workflow.

### Fixed
- Release automation now uses stable build-cache paths and publishes appcasts with the correct repository URL and app-bundle capitalization.


## [1.0.9] - 2026-07-24

### Added
- Sparkle automatic-update support, including update preferences and manual “Check for Updates” controls.
- Appcast publishing as part of the GitHub release workflow.

### Changed
- First-launch prompts now appear in a clearer order: yabai, Applications folder, launch at login, then updates.

### Fixed
- Sparkle is embedded and loaded correctly, with working framework rpaths, signing, feed URLs, and appcast generation.


## [1.0.8] - 2026-07-24

### Fixed
- The app returns to its background-only activation policy after the Settings window closes, preventing a lingering Dock icon.


## [1.0.7] - 2026-07-23

### Fixed
- Icon strips now scale to fit their cells instead of overflowing when many apps are visible.


## [1.0.6] - 2026-07-21

### Fixed
- **Auto-version from git tag**: Makefile now derives `VERSION` from `git describe --tags --abbrev=0` automatically. Info.plist version is replaced at build time regardless of current value. Release flow: `git tag v1.0.6 && git push`

---

## [1.0.5] - 2026-07-21

### Added
- **Show Extra Windows toggle**: `SHOW_EXTRA_WINDOWS` config option to display utility/floating windows (sublayer=normal). Default off — only shows sublayer=below windows
- **Custom HUD position memory**: Custom HUD positions now persist correctly when switching between presets (Center/Top/Bottom/Custom). Last dragged position stored in `CUSTOM_HUD_X`/`CUSTOM_HUD_Y`
- **Simplified HUD_POSITION config**: Now writes `HUD_POSITION=custom` instead of `HUD_POSITION=x,y` for cleaner config. Custom coordinates stored in separate `CUSTOM_HUD_X`/`CUSTOM_HUD_Y` keys
- **Debug/Advanced settings section**: Socket Health Interval moved to a new Debug/Advanced section at the bottom of Settings
- **on/off boolean values**: Config now writes `on`/`off` for boolean values (was `true`/`false`). Parsing accepts all: `true`, `false`, `1`, `0`, `yes`, `no`, `on`, `off`

### Changed
- **Settings UI reorder**: Behavior section reordered to: Hotkey → HUD Position → Auto-hide Timeout → Navigate with Arrow Keys → Navigate with Vim Keys → Hide Menu Bar Icon → Socket Health Interval (Debug/Advanced)
- **Space Names section moved**: Now appears directly below Grid section with proper title header
- **Auto-hide timeout display**: Label format changed to "Auto-hide Timeout (s) (0 = disabled): [value] [+/-]" with aligned mechanism
- **Grid layout label fix**: Fixed typo showing "4×(r))" instead of "4×2"
- **Show Icon Per Window**: Renamed from "Show Each Window Icon"

---

## [1.0.4] - 2026-07-21

### Added
- Info.plist version injection from VERSION file at build time (all app targets)
- Merged FAQ into README, combined API_SUMMARY + CHEAT_SHEET into REFERENCE.md

---

## [1.0.3] - 2026-07-20

### Added
- **Settings normalization**: UI_SCALE and ICON_SCALE normalized to 0.0–1.0; effective scale mapping in GridView (`0.5 + uiScale × 3.5` for UI, `0.2 + iconScale × 0.8` for icons)
- **CI DMG architecture verification**: Release workflow mounts each DMG and checks `lipo -archs`
- **Rendering math tests**: 8 unit tests for scale mapping (min/max/midpoint/monotonicity)

### Fixed
- CustomStepper `currentIndex` fallback uses closest match instead of 0 on floating-point mismatch
- Default config values updated: `uiScale: 0.5`, `iconScale: 0.5` (midpoint)
- UI_SCALE and ICON_SCALE validation now accepts 0.0–1.0

---

## [1.0.2] - 2026-07-18

### Fixed
- DMG app name unified: all arch DMGs contain `Spacemap.app` regardless of architecture
- Release workflow calls `make _dmg` directly instead of depending on intermediate targets

---

## [1.0.1] - 2026-07-17

### Added
- **Config backup**: Backs up to `.bak` before any config overwrite (self-heal or first-load normalize)
- **i18n localization**: 14 languages (en, es, de, it, fr, zh-Hans, hi, ar, pt, bn, ru, ja, ko, tr)
- **Homebrew tap**: `wiggly-sheets/homebrew-spacemap` with arch-conditional cask, auto-updated on release
- **F13-F20 hotkeys + Hyper/Capslock/Fn modifiers**: Full keyboard support in config parser

### Fixed
- HUD dual-layering: `show()` tears down orphaned panel; `refreshState()` guards on `isVisible`
- Launch at Login menu item matching uses `tag: 1001` instead of string comparison (localization-safe)

---

## [1.0.0] - 2026-01-19

### Added
- Space naming system with dynamic configuration in settings window
- Settings window with scrollable, resizable UI
- Hotkey recorder with global keyboard capture
- Launch at login toggle with state indicator
- Config file self-healing (auto-generates missing keys)
- CLI options: `--version`, `--help`, `--config`, `--trigger`, `--show-menu`, `--settings`
- Live auto-hide timeout with configurable delay
- Hotkey rapid-press protection (`isToggling` guard)
- Symlink creation (`/usr/local/bin/spacemap`) at launch
- Active space live highlighting via polling
- **File-based theme system**: `.smthemes` files in `~/.config/spacemap/themes/`, editable text files with rect1/rect2/rect3 colors, auto-seeded on first launch
- **Grid-aware keyboard navigation**: Arrow keys and vim keys (hjkl) with row/column wrapping, configurable via `VIM_KEYS` and `ARROW_KEYS`
- **Dynamic yabai path**: Auto-detects ARM (`/opt/homebrew/bin/yabai`) or Intel (`/usr/local/bin/yabai`) via FileManager, fixes blank HUD when launched from Finder
- **Default macOS greyscale theme**: Light grey cells with blue accent, replaces old black default
- **Window rect color palettes**: Themes define 3 base rect colors (`rect1`/`rect2`/`rect3`), HSL variation for >3 windows per space
- **Open Config File / Open Themes Folder buttons**: In Settings Appearance section
- **Icon caching**: `IconCache` singleton avoids re-fetching `NSWorkspace.shared.icon(forFile:)` on every render
- **Show Each Window Icon toggle**: `SHOW_MULTI_APP_ICONS` config option to show one icon per window or one per unique app in icon strip
- **Thumbnail cell style**: ScreenCaptureKit-based per-space capture, cached per cell index (macOS 14+)
- **Show Icon Strip toggle**: Config option `SHOW_ICON_STRIP` to show/hide app icon strip in cells
- **Show Space Numbers toggle**: Config option `SHOW_SPACE_NUMBERS` to show/hide space numbers
- **Show Space Names toggle**: Config option `SHOW_SPACE_NAMES` to show/hide custom space names
- **Hide Menu Bar Icon toggle**: Config option `HIDE_MENUBAR_ICON` to run headless
- **Cell opacity / inactive dimming**: Inactive spaces dimmed in the grid
- **MRU Spaces detection**: Warns user on launch if macOS MRU spaces is enabled, offers to disable
- **Screen Recording permissions link**: Added to menubar menu for easy access
- **Menubar hotkey symbols**: Show configured hotkey symbols in Show/Hide Map menu item
- **Menubar restart shortcut**: Cmd+R to restart Spacemap from menubar
- **Settings window hotkey recorder**: Global keyboard capture for setting hotkey in settings UI
- **Settings window space name editor**: Per-space text inputs in settings UI
- **Xcode project**: Generated from SPM via `scripts/generate-xcodeproj.py`, 4 targets (default, arm64, x86_64, universal)
- **Unit test suite**: 103 tests across 5 files — hotkey parsing, config parsing, theme loading, model encoding, grid computation, cell view logic
- **GitHub Actions CI**: `ci.yml` runs `swift test` + `swift build` on push/PR (macOS-14)
- **GitHub Actions Release**: `release.yml` builds 3 DMG variants + `checksums.txt` on tag push
- **Dependabot**: Weekly GitHub Actions dependency updates
- **Architecture-specific builds**: `make build-arm64`, `make build-x86_64`, `make build-universal`, DMG variants

### Changed
- Settings window now scrollable with proper dimensions
- `ThemeMode.automatic` renamed to `.auto` for consistency
- Config serialization uses string names instead of rawValue numbers
- Cell styles (rects, icons, hybrid) now properly serialized
- Auto-hide timer now resets unconditionally on HUD show
- Config parser now handles BOM, CR/LF, and inline comments
- Refactored `CellStyle` from 5 cases to 3: `rects`, `icons`, `thumbnails` (removed `hybrid`; use `icons` + `SHOW_ICON_STRIP=true` instead)
- CellStyle `"icons"` in config now sets `showIconStrip=true` by default
- Improved yabai mandatory check with alert dialog
- Improved Accessibility permission flow with polling
- Extracted testable pure functions: `parseConfig()`, `parseThemeContent()`, `CellView.appColor()`, `CellView.uniqueIconWindows()`, `GridView.computeVisibleSpaceIndices()`, `GridView.computeIdealSize()`
- `AppTheme` now conforms to `Equatable`

### Fixed
- HUD staying visible during space changes
- Hotkey double-trigger on rapid presses
- Settings window opening at full size
- Auto-hide timeout not syncing after settings changes
- Space names UI text field focus preservation
- Yabai not running alert not appearing frontmost
- Spaces MRU warning not appearing on startup
- Window drag-and-drop coordinate system mismatch
- Settings window not receiving keyboard focus (activation policy now set to `.regular` temporarily)
- Space name input field focus preservation
- Theme file parsing: `dropTarget` key case-insensitive matching (custom `.smthemes` files were silently failing, always falling back to hardcoded themes)

---

## [0.2.0] - 2024-03-15

### Added
- Menubar status item for manual show/hide
- Configurable hotkey (default: Ctrl+Page Down)
- Video demo in README
- Homebrew cask distribution support

### Changed
- Updated README with installation instructions
- Improved hotkey configuration flow

---

## [0.1.0] - 2023-06-01

### Added
- Homebrew distribution via `jsheffie/tap`
- Initial public release
- Basic UI scaling support

### Changed
- Repository moved to `jsheffie/spacemap`

---

## [0.0.8] - 2023-03-20

### Added
- Improved README install instructions

### Changed
- Documentation updates

---

## [0.0.7] - 2023-02-15

### Added
- Hybrid cell style (rectangles + app icons)
- Enhanced README documentation

---

## [0.0.6] - 2023-01-20

### Added
- Click-to-change-workspace functionality

---

## [0.0.5] - 2023-01-10

### Added
- Background color and highlight fixes
- Reverted CELL_STYLE config (subsequent fix in 0.0.4)

### Fixed
- Cell visibility and highlight in icons mode
- Background color rendering

---

## [0.0.4] - 2022-12-15

### Added
- CELL_STYLE config option (rects vs icons)
- Icons support with hybrid mode

### Changed
- Cell rendering logic

---

## [0.0.3] - 2022-12-01

### Fixed
- Active cell highlight visibility behind window rects
- Colored outline contrast

---

## [0.0.2] - 2022-11-15

### Added
- Event-driven architecture with yabai signals
- Auto-hide timer reset on space change

### Fixed
- HUD getting stuck on a workspace

---

## [0.0.1] - 2022-11-01

### Added
- Initial commit
- Basic HUD grid overlay
- yabai workspace visualization
- App adaptation from existing sharing (github/intellij-plantuml-plugin)
