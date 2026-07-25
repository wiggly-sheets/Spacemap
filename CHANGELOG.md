# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]


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
- Release checklist in AGENTS.md
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
