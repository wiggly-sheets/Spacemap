# Spacemap Roadmap

A living list of planned features, known bugs, and future improvements for the project. Items are categorized by priority and status.

## ✅ Completed

### Core Features & CLI

- **CLI Options**: `--version`, `--help`, `--config`, `--trigger`, `--space <selector>`, `--show-menu`, `--settings`
- **Settings Window**: Permanent System Settings-style sidebar with highlighted categories, separate live-save detail forms, space-name editor, and hotkey recorder
- **Launch at Login**: Toggle with state indicator and first-launch prompt
- **Move to Applications Prompt**: First-launch prompt to move app to /Applications
- **TOML-only Config**: Uses grouped Settings-aligned TOML at `~/.config/spacemap/config.toml`
- **Config File Self-Heal**: Auto-generates on first launch and repairs missing or invalid fields
- **Config Validation**: Validates TOML keys and values on load
- **Config Backup**: Backs up to `.bak` before any config overwrite (self-heal or first-load normalize)

### HUD & Display

- **HUD Active Space Highlighting**: Live refresh timer calls `refreshState` for active space highlighting
- **HUD Pinning**: Implemented via `AUTO_HIDE_TIMEOUT=0` (never auto-hide)
- **HUD Dual-Layering Fix**: `show()` tears down orphaned panel; `refreshState()` guards on `isVisible`
- **Cell Opacity / Inactive Dimming**: Inactive spaces dimmed in the grid
- **Simple Cell Style**: Plain empty cells with no window rendering
- **Multi-Monitor HUD Modes**: Unified or separate HUDs, each configurable for all displays or only the focused-space display, with a startup check for macOS separate Spaces

### Space Display Options

- **Show Space Numbers Toggle**: Per-cell space number display with consistent scaled insets at every HUD size
- **Show Space Names Toggle**: Per-cell custom name display
- **Show Icon Strip Toggle**: Per-cell app icon strip at bottom
- **Hide Menu Bar Icon Toggle**: Run headless, use hotkey or CLI
- **Menu Bar Workspace Previews**: Current, nearby, all-space, and compact dot-grid modes with live yabai layout updates

### Hotkeys & Navigation

- **Hotkey Rapid-Press Fix**: `isToggling` guard in `HUDWindowController`
- **F13-F20 Hotkeys + Fn Modifier**: Extended keyboard support in the config parser
- **Grid-aware Keyboard Navigation**: Arrow keys + vim keys (hjkl) with row/column wrapping
- **Auto-Hide Timeout Fix**: Fixed HUD not hiding and hotkey double-trigger

### System Integration

- **Symlink Creation**: Automated `/usr/local/bin/spacemap` symlink at launch via `ensureSymlink()`
- **Yabai Mandatory Check**: Prevents launch if yabai is not running; shows critical alert
- **MRU Spaces Detection**: Warns user and offers to disable macOS MRU spaces
- **Accessibility Permission Recovery**: Continuously monitors permission and event-tap health, restoring hotkeys after runtime revocation/re-grant
- **Dynamic yabai Path**: Auto-detects ARM (`/opt/homebrew/bin/yabai`) or Intel (`/usr/local/bin/yabai`) via FileManager
- **Menubar Improvements**: Hotkey symbols shown, Cmd+R restart, Screen Recording permissions link

### Theming & Customization

- **Space Naming System**: Config-based `SPACE_NAMES=1:Name,2:Name` with settings UI editor
- **File-based Theme System**: `.smthemes` files in `~/.config/spacemap/themes/`, editable text files, auto-seeded on first launch
- **Theme Bug Fix**: `dropTarget` case-insensitive matching in `.smthemes` parsing

### Window Features

- **Window Previews / Thumbnails**: ScreenCaptureKit-based all-space capture with HUD exclusion, deterministic window assignment, bounded concurrency, and atomic cache refreshes
- **Hybrid Cell Style**: Rectangle layout with a proportionally scaled app icon centered in every window rectangle
- **Icon Cell Layout**: One icon per yabai window with geometry-aware placement, including duplicate-app windows and correct split ordering
- **Show Extra Windows**: `SHOW_EXTRA_WINDOWS` toggle to display nonstandard utility/background window records
- **Conditional Focus After Window Drop**: Never, always, or only while holding a selected modifier

### Settings UI Improvements

- **Settings Normalization**: UI_SCALE and ICON_SCALE normalized to 0.0–1.0 with effective scale mapping (GridView)
- **Simplified HUD_POSITION Config**: Now writes `HUD_POSITION=custom` with separate coordinate keys
- **Custom HUD Position Memory**: Custom positions persist when switching presets; stored in `CUSTOM_HUD_X`/`CUSTOM_HUD_Y`
- **Debug/Advanced Settings Section**: Socket Health Interval moved to dedicated section
- **Settings UI Reorganization**: Five separate sidebar categories (Grid, Space Names, Appearance, Behavior, Debug/Advanced) with a permanently visible selected category
- **Native Hotkey Recorder**: Clear button plus regular, F13–F20, and media-key recording

### Distribution & Builds

- **App Icon**: Bundled `.icns` file for macOS app bundle
- **DMG Assets**: DMG installer with /Applications symlink
- **Xcode Project Generation**: `scripts/generate-xcodeproj.py` with 4 architecture targets
- **Architecture-specific Builds**: ARM64, x86_64, universal DMGs via `create-dmg`
- **CI DMG Verification**: Release workflow mounts each DMG and verifies architecture with `lipo -archs`
- **Info.plist Version Injection**: Makefile sed replaces hardcoded 1.0.0 with VERSION file at build time
- **Homebrew Tap**: `wiggly-sheets/homebrew-spacemap` with arch-conditional cask, auto-updated on release
- **DMG Fix**: Arch DMGs always contain `Spacemap.app` regardless of arch

### Testing & CI/CD

- **Unit Test Suite**: 210 tests across 13 files
- **GitHub Actions CI/CD**: CI (swift test + build), Release (3 DMGs + checksums), Dependabot
- **Rendering Math Tests**: 8 unit tests for scale mapping (min/max/midpoint/monotonicity)

### Code Quality

- **Extracted Pure Functions**: `parseConfig()`, `parseThemeContent()`, `CellView.appColor()`, etc.

### Localization

- **i18n Localization**: 14 languages (en, es, de, it, fr, zh-Hans, hi, ar, pt, bn, ru, ja, ko, tr)

### Features

| Task                         | Description                                                                                                | Status  |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------- | ------- |
| **Icon Caching**       | Cache app icons via`IconCache` singleton to avoid re-fetching on every render                            | ✅ Done |
| **Dynamic yabai Path** | Auto-detect yabai location (`/opt/homebrew/bin/yabai` or `/usr/local/bin/yabai`) for Intel Mac support | ✅ Done |

### Bug Fixes

| Task                                 | Description                                                         | Status               |
| ------------------------------------ | ------------------------------------------------------------------- | -------------------- |
| **Drag-and-Drop Ambiguity**    | Falls back to click proximity for multi-window apps                 | 🔄 Open              |
| **Icon Strip Flicker**         | Re-fetching icons via`NSWorkspace` causes flicker on space change | ✅ Fixed (IconCache) |
| **Hotkey Limited Key Support** | Missing support for F13-F20/media keys in config parser             | ✅ Fixed             |

## 🚀 High Priority

---

## 🛠 Medium Priority

### Features

| Task                                     | Description                                                                                              | Status     |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------- | ---------- |
| **Theme Files (.smthemes)**        | Expose themes as editable files in`~/.config/spacemap/themes/`. Default greyscale theme, import/export | ✅ Done    |
| **Drag-to-Swap**                   | Swap windows between spaces via drag-and-drop within the HUD                                             | 🔄 Planned |
| **Custom Cell Colors**             | Allow per-space/app custom colors in config                                                              | 🔄 Planned |
| **Grid Gap/Padding Customization** | Add config options for spacing between cells                                                             | 🔄 Planned |
| **Multi-Monitor Awareness**        | Unified cross-display grid or one HUD per display                                                        | ✅ Done    |

### Performance

| Task                                | Description                                                 | Status     |
| ----------------------------------- | ----------------------------------------------------------- | ---------- |
| **CPU/Memory Optimization**   | Profile and reduce resource usage, especially in background | 🔄 Planned |
| **Reduced SwiftUI Rerenders** | Optimize HUD recreations during drag-and-drop               | 🔄 Planned |

---

## 🌌 Low Priority

### Features

| Task                          | Description                                                              | Status                 |
| ----------------------------- | ------------------------------------------------------------------------ | ---------------------- |
| **i18n Localization**   | Spanish, German, Italian, French, and other major languages              | ✅ Done (14 languages) |
| **Hotkey Conflicts UI** | Show menubar conflicts with other apps                                   | 🔄 Planned             |
| **Keyboard Navigation** | Arrow-key and vim-key navigation within HUD (currently handled via skhd) | ✅ Done                |

### Integration

| Task                            | Description                                                                                         | Status     |
| ------------------------------- | --------------------------------------------------------------------------------------------------- | ---------- |
| **Native Spaces Support** | Drop yabai dependency for native macOS Spaces                                                       | 🔄 Planned |
| **Other WM Support**      | Add support for aerospace/rectangle/etc.                                                            | 🔄 Planned |
| **Raycast Extension**     | Raycast extension to toggle HUD, change config (cell style, theme, grid size, etc.) from Raycast UI | 🔄 Planned |

### Build & CI

| Task                               | Description                                                                                                             | Status  |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------- |
| **Unit Tests**               | 193 tests across 9 files (CLISymlinkInstallerTests, HotkeyTests, ConfigTests, ThemeTests, ModelTests, CellViewGridViewTests, SpaceNavigatorTests, DeepLinkTests, ThumbnailCacheTests) | ✅ Done |
| **GitHub Actions / CI**      | `ci.yml` (swift test + build on push/PR), `release.yml` (3 DMGs + checksums on tag), Dependabot                     | ✅ Done |
| **Xcode Project**            | Generated from SPM, 4 targets (default, arm64, x86_64, universal) via`scripts/generate-xcodeproj.py`                  | ✅ Done |
| **Architecture Builds**      | ARM64, x86_64, universal DMGs via`create-dmg`                                                                         | ✅ Done |
| **Homebrew Formula Updates** | Homebrew tap with arch-conditional cask, auto-updated on release                                                        | ✅ Done |

---

## 🐛 Known Bugs

| Bug                         | Description                                         | Status                                      |
| --------------------------- | --------------------------------------------------- | ------------------------------------------- |
| **Config Corruption** | Corrupt config overrides all settings with defaults | ✅ Fixed (backups to .bak before overwrite) |

---

## 🧪 Experimental Ideas

| Idea                      | Description                                                    | Status     |
| ------------------------- | -------------------------------------------------------------- | ---------- |
| **HUD Pinning**     | Separate hotkey for temporary (timed) vs permanent HUD display | ✅ Complete |
| **Window Rules**    | Move windows between spaces via regex matches                  | 💡 Concept |
| **Space Templates** | Predefined app layouts for quick setup                         | 💡 Concept |
