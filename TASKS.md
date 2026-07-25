# Spacemap Roadmap

A living list of planned features, known bugs, and future improvements for the project. Items are categorized by priority and status.

## ✅ Completed

- **CLI Options**: `--version`, `--help`, `--config`, `--trigger`, `--show-menu`, `--settings`
- **Settings Window**: Full settings UI with live-save, space name editor, hotkey recorder
- **Hotkey Rapid-Press Fix**: `isToggling` guard in `HUDWindowController`
- **Symlink Creation**: Automated `/usr/local/bin/spacemap` symlink at launch via `ensureSymlink()`
- **HUD Active Space Highlighting**: Live refresh timer calls `refreshState` for active space highlighting
- **Launch at Login**: Toggle with state indicator and first-launch prompt
- **Show Space Numbers Toggle**: Per-cell space number display
- **Show Space Names Toggle**: Per-cell custom name display
- **Show Icon Strip Toggle**: Per-cell app icon strip at bottom
- **Hide Menu Bar Icon Toggle**: Run headless, use hotkey or CLI
- **Move to Applications Prompt**: First-launch prompt to move app to /Applications
- **Config File Self-Heal**: Auto-generates on first launch, self-heals missing keys, handles BOM/CR/LF
- **Auto-Hide Timeout Fix**: Fixed HUD not hiding and hotkey double-trigger
- **Yabai Mandatory Check**: Prevents launch if yabai is not running; shows critical alert
- **MRU Spaces Detection**: Warns user and offers to disable macOS MRU spaces
- **Accessibility Permission Request**: Polls every 2s until granted, registers hotkey automatically
- **Cell Opacity / Inactive Dimming**: Inactive spaces dimmed in the grid
- **Window Previews / Thumbnails**: ScreenCaptureKit-based per-space thumbnail capture (experimental)
- **App Icon**: Bundled `.icns` file for macOS app bundle
- **Space Naming System**: Config-based `SPACE_NAMES=1:Name,2:Name` with settings UI editor
- **Menubar Improvements**: Hotkey symbols shown, Cmd+R restart, Screen Recording permissions link
- **Config Validation**: Validates keys/values on load, logs warnings for invalid entries
- **DMG Assets**: DMG installer with /Applications symlink
- **HUD Pinning**: Implemented via `AUTO_HIDE_TIMEOUT=0` (never auto-hide)
- **File-based Theme System**: `.smthemes` files in `~/.config/spacemap/themes/`, editable text files, auto-seeded on first launch
- **Grid-aware Keyboard Navigation**: Arrow keys + vim keys (hjkl) with row/column wrapping
- **Dynamic yabai Path**: Auto-detects ARM (`/opt/homebrew/bin/yabai`) or Intel (`/usr/local/bin/yabai`) via FileManager
- **Xcode Project Generation**: `scripts/generate-xcodeproj.py` with 4 architecture targets
- **Unit Test Suite**: 150 tests across 6 files
- **GitHub Actions CI/CD**: CI (swift test + build), Release (3 DMGs + checksums), Dependabot
- **Architecture-specific Builds**: ARM64, x86_64, universal DMGs via `create-dmg`
- **Theme Bug Fix**: `dropTarget` case-insensitive matching in `.smthemes` parsing
- **Extracted Pure Functions**: `parseConfig()`, `parseThemeContent()`, `CellView.appColor()`, etc.
- **i18n Localization**: 14 languages (en, es, de, it, fr, zh-Hans, hi, ar, pt, bn, ru, ja, ko, tr)
- **Homebrew Tap**: `wiggly-sheets/homebrew-spacemap` with arch-conditional cask, auto-updated on release
- **DMG Fix**: Arch DMGs always contain `Spacemap.app` regardless of arch
- **F13-F20 Hotkeys + Hyper/Capslock/Fn Modifiers**: Full keyboard support in config parser
- **HUD Dual-Layering Fix**: `show()` tears down orphaned panel; `refreshState()` guards on `isVisible`
- **Simple Cell Style**: Plain empty cells with no window rendering
- **Config Backup**: Backs up to `.bak` before any config overwrite (self-heal or first-load normalize)
- **Settings Normalization**: UI_SCALE and ICON_SCALE normalized to 0.0–1.0 with effective scale mapping (GridView)
- **CI DMG Verification**: Release workflow mounts each DMG and verifies architecture with `lipo -archs`
- **Rendering Math Tests**: 8 unit tests for scale mapping (min/max/midpoint/monotonicity)
- **Info.plist Version Injection**: Makefile sed replaces hardcoded 1.0.0 with VERSION file at build time
- **Show Extra Windows**: `SHOW_EXTRA_WINDOWS` toggle to display utility/floating windows (sublayer=normal)
- **Custom HUD Position Memory**: Custom positions persist when switching presets; stored in `CUSTOM_HUD_X`/`CUSTOM_HUD_Y`
- **Simplified HUD_POSITION Config**: Now writes `HUD_POSITION=custom` with separate coordinate keys
- **on/off Boolean Config**: Writes `on`/`off` for booleans; accepts all formats (`true`, `false`, `1`, `0`, `yes`, `no`, `on`, `off`)
- **Debug/Advanced Settings Section**: Socket Health Interval moved to dedicated section
- **Settings UI Reorganization**: Reordered Behavior section, moved Space Names under Grid, fixed layout labels
- **Multi-Monitor HUD Modes**: Unified or separate HUDs, each configurable for all displays or only the focused-space display, with a startup check for macOS separate Spaces

## 🚀 High Priority

### Features

| Task | Description | Status |
|------|-------------|--------|
| **Icon Caching** | Cache app icons via `IconCache` singleton to avoid re-fetching on every render | ✅ Done |
| **Dynamic yabai Path** | Auto-detect yabai location (`/opt/homebrew/bin/yabai` or `/usr/local/bin/yabai`) for Intel Mac support | ✅ Done |

### Bug Fixes

| Task | Description | Status |
|------|-------------|--------|
| **Drag-and-Drop Ambiguity** | Falls back to click proximity for multi-window apps | 🔄 Open |
| **Icon Strip Flicker** | Re-fetching icons via `NSWorkspace` causes flicker on space change | ✅ Fixed (IconCache) |
| **Hotkey Limited Key Support** | Missing support for F13-F20/media keys in config parser | ✅ Fixed |

---

## 🛠 Medium Priority

### Features

| Task | Description | Status |
|------|-------------|--------|
| **Theme Files (.smthemes)** | Expose themes as editable files in `~/.config/spacemap/themes/`. Default greyscale theme, import/export | ✅ Done |
| **Drag-to-Swap** | Swap windows between spaces via drag-and-drop within the HUD | 🔄 Planned |
| **Custom Cell Colors** | Allow per-space/app custom colors in config | 🔄 Planned |
| **Grid Gap/Padding Customization** | Add config options for spacing between cells | 🔄 Planned |
| **Multi-Monitor Awareness** | Unified cross-display grid or one HUD per display | ✅ Done |

### Performance

| Task | Description | Status |
|------|-------------|--------|
| **CPU/Memory Optimization** | Profile and reduce resource usage, especially in background | 🔄 Planned |
| **Reduced SwiftUI Rerenders** | Optimize HUD recreations during drag-and-drop | 🔄 Planned |

---

## 🌌 Low Priority

### Features

| Task | Description | Status |
|------|-------------|--------|
| **i18n Localization** | Spanish, German, Italian, French, and other major languages | ✅ Done (14 languages) |
| **Hotkey Conflicts UI** | Show menubar conflicts with other apps | 🔄 Planned |
| **Keyboard Navigation** | Arrow-key and vim-key navigation within HUD (currently handled via skhd) | ✅ Done |

### Integration

| Task | Description | Status |
|------|-------------|--------|
| **Native Spaces Support** | Drop yabai dependency for native macOS Spaces | 🔄 Planned |
| **Other WM Support** | Add support for aerospace/rectangle/etc. | 🔄 Planned |
| **Raycast Extension** | Raycast extension to toggle HUD, change config (cell style, theme, grid size, etc.) from Raycast UI | 🔄 Planned |

### Build & CI

| Task | Description | Status |
|------|-------------|--------|
| **Unit Tests** | 150 tests across 6 files (HotkeyTests, ConfigTests, ThemeTests, ModelTests, CellViewGridViewTests, SpaceNavigatorTests) | ✅ Done |
| **GitHub Actions / CI** | `ci.yml` (swift test + build on push/PR), `release.yml` (3 DMGs + checksums on tag), Dependabot | ✅ Done |
| **Xcode Project** | Generated from SPM, 4 targets (default, arm64, x86_64, universal) via `scripts/generate-xcodeproj.py` | ✅ Done |
| **Architecture Builds** | ARM64, x86_64, universal DMGs via `create-dmg` | ✅ Done |
| **Homebrew Formula Updates** | Homebrew tap with arch-conditional cask, auto-updated on release | ✅ Done |

---

## 🐛 Known Bugs

| Bug | Description | Status |
|-----|-------------|--------|
| **Config Corruption** | Corrupt config overrides all settings with defaults | ✅ Fixed (backups to .bak before overwrite) |

---

## 🧪 Experimental Ideas

| Idea | Description | Status |
|------|-------------|--------|
| **HUD Pinning** | Separate hotkey for temporary (timed) vs permanent HUD display | 💡 Concept |
| **Window Rules** | Move windows between spaces via regex matches | 💡 Concept |
| **Space Templates** | Predefined app layouts for quick setup | 💡 Concept |
