# Config Refactoring

**Status:** Proposed
**Date:** 2026-08-04
**Author:** Architecture Review

## Summary

Split the 685-line monolithic `Config` singleton into three focused modules: `ConfigValues` (pure value type), `TOMLParser` (parsing/serialization), and `ConfigLoader` (file I/O, caching, backup). This improves testability from integration-test-only to unit-testable, separates concerns, and eliminates the duplicated hotkey parsing logic in Config's nested `hotkey()` function.

## Motivation

- Config is a 685-line static singleton mixing TOML parsing, file I/O, defaults, validation, and hotkey logic
- The nested `hotkey()` function duplicates `Hotkey`'s modifier parsing — a tight coupling that breaks if Hotkey's internals change
- Config's static singleton interface makes it impossible to mock for unit testing
- Understanding configuration loading requires jumping through Config's massive `parsedObject → normalizedTOMLObject → decodedTOMLConfig` pipeline
- The `saveConfig` path, `createDefaultConfigFile` side effects, and `backupConfig` logic are untested

## Decomposition

### New Modules

| Module | File | Interface | Depth |
|---|---|---|---|
| `ConfigValues` | `Sources/spacemap/ConfigValues.swift` | Pure struct with optionals + `toGridConfig()` | Deep: ~200 lines behind 1 method |
| `TOMLParser` | `Sources/spacemap/TOMLParser.swift` | `parse(_ data: String) -> ConfigValues` | Deep: ~600 lines behind 1 method |
| `ConfigLoader` | `Sources/spacemap/ConfigLoader.swift` | `load(path:) -> ConfigValues`, `save(_ values: ConfigValues, to path:)`, `createDefaultConfigFile()` | Deep: ~100 lines behind 3 methods |
| `Config` | `Sources/spacemap/Config.swift` | Thin facade: `load()`, `saveConfig()`, `parseConfig()` — delegates to ConfigLoader/TOMLParser | Thin: ~50 lines |

### ConfigValues Struct

```swift
struct ConfigValues {
    // All GridConfig fields as optionals
    var cols: Int?
    var rows: Int?
    var cellStyle: CellStyle?
    var hotkey: HotkeyConfig?
    var pinnedHotkey: HotkeyConfig?
    var socketHealthInterval: Int?
    var uiScale: Double?
    var autoHideTimeout: Int?
    var theme: String?
    var showMode: ShowMode?
    var multiMonitorHUDMode: MultiMonitorHUDMode?
    var unifiedHUDVisibility: SeparateHUDVisibility?
    var separateHUDVisibility: SeparateHUDVisibility?
    var displayNavigationWrap: DisplayNavigationWrap?
    var maxSpaces: Int?
    var backgroundAlpha: Double?
    var mode: ThemeMode?
    var iconScale: Double?
    var showSpaceNumbers: Bool?
    var showSpaceNames: Bool?
    var showIconStrip: Bool?
    var showMultiAppIcons: Bool?
    var hideMenuBarIcon: Bool?
    var menuBarDisplayMode: MenuBarDisplayMode?
    var menuBarNearbyCount: Int?
    var spaceNames: [Int: String]?
    var useVimKeys: Bool?
    var useArrowKeys: Bool?
    var hudPosition: HUDPosition?
    var customHUDX: Double?
    var customHUDY: Double?
    var showExtraWindows: Bool?
    var focusSpaceOnWindowDrop: WindowDropFocusMode?
    var focusSpaceOnWindowDropModifier: WindowDropFocusModifier?
    var showHUDOnSpaceChange: Bool?
    var updateMode: UpdateMode?

    func toGridConfig() -> GridConfig
}
```

### TOMLParser

- `parse(_ data: String) -> ConfigValues` — parses TOML string, returns ConfigValues with optionals filled where present
- Handles all sections: `[grid]`, `[appearance]`, `[behavior]`, `[behavior.hotkey]`, `[behavior.pinnedHotkey]`, `[behavior.hudPosition]`, `[advanced]`, `[spaceNames.names]`
- Delegates hotkey parsing to `Hotkey` module (eliminates Config's duplicated `hotkey()` function)
- Ignores unknown keys gracefully

### ConfigLoader

- `load(path:) -> ConfigValues` — reads file, parses with TOMLParser, handles missing file (create default), handles invalid TOML (backup + replace with defaults)
- `save(_ values: ConfigValues, to path:)` — serializes ConfigValues to TOML, writes to file, creates backup before overwrite
- `createDefaultConfigFile()` — generates default TOML config file
- Backup logic is internal to `save` and `load` (not a separate method)

### Config (thin facade)

- Keeps `load()`, `saveConfig()`, `parseConfig()`, `parseHotkey()` as convenience wrappers
- Delegates all work to ConfigLoader/TOMLParser
- Maintains backward compatibility for existing callers

## Implementation Order

1. **ConfigValues** — pure struct, no dependencies, easy to test
2. **TOMLParser** — depends on ConfigValues, can be tested with string inputs
3. **ConfigLoader** — depends on both, tested with temp file fixtures
4. **Config facade** — thin wrapper, minimal risk
5. **Delete old Config.swift** — replace with facade, remove duplicated hotkey() logic

## Testing Strategy

| Module | Test Type | Approach |
|---|---|---|
| `ConfigValues` | Pure unit tests | Test `toGridConfig()` with partial/complete optionals |
| `TOMLParser` | Pure unit tests | Test with string inputs, verify optionals populated correctly |
| `ConfigLoader` | Temp file fixture tests | Test load/save/backup/createDefault with temp directories |
| `Config` (facade) | Integration tests | Verify backward compatibility with existing callers |

## Files Changed

### New Files
- `Sources/spacemap/ConfigValues.swift`
- `Sources/spacemap/TOMLParser.swift`
- `Sources/spacemap/ConfigLoader.swift`
- `Tests/spacemapTests/ConfigValuesTests.swift`
- `Tests/spacemapTests/TOMLParserTests.swift`
- `Tests/spacemapTests/ConfigLoaderTests.swift`

### Modified Files
- `Sources/spacemap/Config.swift` — reduced to thin facade

### Deleted Files
- None (Config.swift is refactored, not deleted)

## Constraints

- No external dependencies added (zero-dependency project)
- Must maintain macOS 13+ target
- Must maintain Swift 5.9 compatibility
- All existing tests must continue to pass
- Config facade must maintain backward compatibility for existing callers
- No ADR conflicts (no existing ADRs in the project)

## Acceptance Criteria

1. Config.swift is under 100 lines (facade only)
2. TOMLParser has no direct file I/O
3. ConfigLoader has no parsing logic (delegates to TOMLParser)
4. ConfigValues has no side effects (pure struct)
5. TOMLParser delegates hotkey parsing to Hotkey module (no duplication)
6. All new modules have protocol-based unit tests
7. ConfigLoader temp file tests cover load/save/backup/createDefault
8. All existing tests continue to pass
9. Config facade backward compatibility verified
