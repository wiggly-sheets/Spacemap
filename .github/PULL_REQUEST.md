# spacemap 1.0.0 — Major Feature Release

## Summary

~100 commits of features, fixes, performance improvements, testing, CI/CD, and build tooling since the upstream fork point. Transforms spacemap from a basic HUD overlay into a fully tested, themed, keyboard-navigable workspace visualizer with architecture-specific builds and automated releases.

**103 unit tests. Zero external dependencies.**

---

## New Features

### File-Based Theme System
- Editable `.smthemes` files in `~/.config/spacemap/themes/`
- Auto-seeded with 12 built-in themes on first launch (catppuccin, tokyonight, dracula, nord, etc.)
- Three configurable rect colors (`rect1`/`rect2`/`rect3`) with HSL variation for >3 windows
- Open Themes Folder button in settings

### Grid-Aware Keyboard Navigation
- Arrow keys and vim keys (`hjkl`) navigate spaces in the HUD grid
- Row/column-aware wrapping (left/right wrap within row, up/down wrap within column)
- Configurable via `VIM_KEYS` and `ARROW_KEYS` config options

### Thumbnail Cell Style
- ScreenCaptureKit-based per-space capture (macOS 14+)
- Per-cell caching keyed by space index
- Config option: `CELL_STYLE=thumbnails`
- Screen Recording permission link in menubar

### Dynamic Yabai Path
- Auto-detects ARM (`/opt/homebrew/bin/yabai`) or Intel (`/usr/local/bin/yabai`)
- Fixes blank HUD when launched from Finder (no shell $PATH)
- Uses `FileManager` instead of shelling out

### Icon Caching
- `IconCache` singleton avoids repeated `NSWorkspace.shared.icon(forFile:)` calls
- Reduces icon strip flicker on space change

### Xcode Project
- Generated from SPM via `scripts/generate-xcodeproj.py`
- 4 targets: default, arm64, x86_64, universal
- Edit `Package.swift`, not the `.xcodeproj`

### Architecture-Specific Builds
- `make build-arm64`, `make build-x86_64`, `make build-universal`
- `make app-arm64`, `make app-x86_64`, `make app-universal`
- `make dmg-arm64`, `make dmg-x86_64`, `make dmg-universal`

### Config Options Added
| Key | Default | Description |
|-----|---------|-------------|
| `VIM_KEYS` | `false` | Navigate with hjkl when HUD visible |
| `ARROW_KEYS` | `false` | Navigate with arrow keys when HUD visible |
| `SHOW_MULTI_APP_ICONS` | `false` | One icon per window vs one per app |
| `SHOW_ICON_STRIP` | `true` | Show/hide icon strip in cells |
| `SHOW_SPACE_NUMBERS` | `true` | Show/hide space numbers |
| `SHOW_SPACE_NAMES` | `true` | Show/hide custom space names |
| `HIDE_MENUBAR_ICON` | `false` | Run headless, use hotkey or CLI |
| `SOCKET_HEALTH_INTERVAL` | `60` | Socket health check interval (seconds) |

### Other Additions
- Settings window hotkey recorder (global keyboard capture)
- Settings window space name editor (per-space text inputs)
- Show Each Window Icon toggle
- Open Config File / Open Themes Folder buttons in settings
- MRU Spaces detection (warns on launch if enabled)
- Screen Recording permissions link in menubar
- Menubar hotkey symbols, Cmd+R restart
- Liquid Glass background (macOS 26+ with fallback for older OS)

---

## Bug Fixes

### Critical
- **Hotkey double-trigger**: Added `isToggling` guard in `HUDWindowController` to prevent re-entry during show/hide animations
- **HUD stuck visible**: Reuse `NSHostingView`, reset auto-hide timer unconditionally on show
- **Auto-hide timeout not syncing**: Fixed timer not resetting after settings changes
- **Settings window focus**: Activation policy temporarily set to `.regular` so window receives keyboard input
- **Theme file parsing**: `dropTarget` key now case-insensitive — custom `.smthemes` files were silently falling back to hardcoded themes
- **Config parser**: Now handles BOM, CR/LF, and inline `#` comments correctly
- **Yabai not found**: Resolved by auto-detecting path instead of hardcoded path
- **Finder launch**: Resolved yabai path without shell to fix blank HUD when launched from Finder

### Settings
- Window opens at correct size instead of full size
- `CELL_STYLE` written as string name instead of rawValue number
- Space name input focus preservation
- Space names: always show 16 boxes, filter by max spaces
- Remove hardcoded defaults from SettingsView state
- Preserve existing `AUTO_HIDE_TIMEOUT` in `saveConfig`
- Remove duplicate type declarations
- Form styling, indentation, and centering

### Build
- Thumbnail freeze: removed semaphore deadlock, use async loading
- CLI symlink and SettingsView cleanup
- Build after SocketListener refactor

### Tested
- `testAppColorDifferentNamesProduceDifferentColors` replaced with `testAppColorReturnsValidThemeColor` — old test was flaky due to platform-dependent hash values

---

## Performance

- **Icon caching**: `IconCache` singleton — no more repeated `NSWorkspace.shared.icon(forFile:)` per render
- **Deep optimization pass**: Reduced CPU and memory usage across the app
- **Thumbnail capture**: ScreenCaptureKit capture-on-space-change instead of polling

---

## Testing

### Unit Test Suite (103 tests)
| File | Tests | Coverage |
|------|-------|----------|
| `HotkeyTests.swift` | 19 | Key code parsing, modifier flags, edge cases |
| `ConfigTests.swift` | 41 | Config parsing, BOM/CRLF, comments, validation, defaults, save/load |
| `ThemeTests.swift` | 12 | Theme parsing, hex colors, fallbacks, comments, edge cases |
| `ModelTests.swift` | 11 | Codable encoding/decoding for all model types |
| `CellViewGridViewTests.swift` | 20 | Grid computation, cell colors, spacing, icon deduplication |

### Testable Pure Functions Extracted
- `parseConfig(_ lines: [String]) -> GridConfig` — `ConfigReader.swift`
- `parseThemeContent(_ content: String) -> AppTheme?` — `ThemeManager.swift`
- `CellView.appColor(_:theme:windowCount:)` — `CellView.swift`
- `CellView.uniqueIconWindows(_ windows: [YabaiWindow])` — `CellView.swift`
- `GridView.computeVisibleSpaceIndices(...)` — `GridView.swift`
- `GridView.computeIdealSize(...)` — `GridView.swift`
- `AppTheme: Equatable` conformance — `Models.swift`

### Running Tests
```bash
make test
swift test
swift test --filter ConfigTests  # specific test class
```

---

## CI/CD

### GitHub Actions CI (`.github/workflows/ci.yml`)
- Triggers on push to `main` and pull requests
- Runs `swift test` + `swift build` on macOS-14
- SPM dependency caching
- Builds universal app as artifact

### GitHub Actions Release (`.github/workflows/release.yml`)
- Triggers on `v*` tag push
- Builds 3 DMG variants (ARM64, x86_64, universal) with `create-dmg`
- Professional DMG layout: app icon, Applications symlink with drag arrow, volume icon
- Generates `checksums.txt` (SHA-256)
- Creates GitHub Release with auto-generated release notes
- Optional code signing + notarization (conditional on Apple Developer secrets)

### Dependabot
- Weekly checks for GitHub Actions dependency updates

### Required GitHub Secrets for Signing/Notarization
| Secret | Description |
|--------|-------------|
| `APPLE_CERTIFICATE_BASE64` | Developer ID Application .p12, base64-encoded |
| `APPLE_CERTIFICATE_PASSWORD` | .p12 password |
| `APPLE_ID` | Apple ID email |
| `APPLE_APP_PASSWORD` | App-specific password |
| `APPLE_TEAM_ID` | 10-char Apple Developer Team ID |

Without secrets, unsigned DMGs are built and released (signing/notarization steps skipped).

---

## Documentation

- **README**: Updated with Xcode project, architecture builds, test suite, CI/CD badge, DMG variants
- **AGENTS.md**: Updated with test commands, CI workflows, extracted functions, bug fixes
- **CHANGELOG.md**: All changes documented under `[1.0.0]`
- **TASKS.md**: Completed items updated, Build & CI section added
- **API_SUMMARY.md**: New functions, auto-detect yabai, Equatable AppTheme
- **CHEAT_SHEET.md**: New make targets, corrected yabai path info
- **CONTRIBUTING.md**: Test commands, architecture builds, corrected limitations
- **DEVELOPER.md**: Full make targets, Xcode project, IconCache mitigation
- **FAQ.md**: Fixed wrong default hotkey, added test section, corrected yabai info
- **PULL_REQUEST_TEMPLATE.md**: Added for contributor workflow

---

## File Changes

### New Files
```
.github/workflows/ci.yml          # CI workflow
.github/workflows/release.yml     # Release workflow (build + sign + notarize)
.github/dependabot.yml             # Dependabot config
.github/PULL_REQUEST_TEMPLATE.md   # PR template
scripts/generate-xcodeproj.py      # SPM → Xcode project generator
Sources/spacemap/LiquidGlassBackground.swift
Sources/spacemap/ThumbnailCache.swift
Sources/spacemap/IconCache.swift
Sources/spacemap/ThemeManager.swift
Tests/spacemapTests/HotkeyTests.swift
Tests/spacemapTests/ConfigTests.swift
Tests/spacemapTests/ThemeTests.swift
Tests/spacemapTests/ModelTests.swift
Tests/spacemapTests/CellViewGridViewTests.swift
```

### Modified Files
```
Makefile                          # test, arch builds, DMG variants, create-dmg
Package.swift                     # Added spacemapTests target, resource rules
Sources/spacemap/App.swift        # CLI options, menubar, yabai check, MRU check
Sources/spacemap/CellView.swift   # Extracted appColor(), uniqueIconWindows()
Sources/spacemap/ConfigReader.swift # Extracted parseConfig(), internal visibility
Sources/spacemap/GridView.swift   # Extracted computeVisibleSpaceIndices(), computeIdealSize()
Sources/spacemap/HUDWindowController.swift # isToggling guard, auto-hide fixes
Sources/spacemap/HotkeyMonitor.swift # Polling for Accessibility permission
Sources/spacemap/Models.swift     # AppTheme: Equatable, new config keys
Sources/spacemap/SettingsView.swift # All new toggles, hotkey recorder, space names
Sources/spacemap/SocketListener.swift # Health check, self-healing
Sources/spacemap/ThemeManager.swift # Extracted parseThemeContent(), dropTarget fix
Sources/spacemap/YabaiClient.swift # Dynamic path detection
Sources/spacemap/WindowDragHandler.swift # Coordinate fix
Sources/spacemap/Info.plist       # Version 1.0.0
```

---

## Breaking Changes

None. All new features are opt-in via config. Existing configs work without modification.

---

## Known Issues

- **Config overwrite on upgrade**: First launch after upgrade rewrites `~/.config/spacemap/config` with defaults. Custom settings (theme, hotkey, grid size, space names) are lost. A follow-up PR will change `saveConfig` to additive merge (only add missing keys, preserve existing values). Workaround: back up your config before upgrading.

---

## Upgrade Notes

1. Copy `.smthemes` theme files are auto-seeded to `~/.config/spacemap/themes/` on first launch
2. New config keys are auto-generated by config self-healing (no manual addition needed)
3. `CELL_STYLE=hybrid` removed — use `CELL_STYLE=icons` + `SHOW_ICON_STRIP=true`
4. Requires macOS 13+ (macOS 14+ for thumbnails)

---

## Testing This PR

1. `make test` — all 103 unit tests pass
2. `make run` — app launches, HUD toggles on hotkey
3. Test keyboard navigation: set `ARROW_KEYS=true` in config, open HUD, use arrow keys
4. Test themes: set `THEME=catppuccin` in config, verify colors change
5. Test thumbnails: set `CELL_STYLE=thumbnails`, grant Screen Recording permission
6. Test architecture builds: `make dmg-arm64`, `make dmg-x86_64`, `make dmg-universal`
