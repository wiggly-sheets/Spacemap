📋 Spec Compliance Review Results
All design specifications are being followed correctly:

- ✅ YabaiClient Extraction (Done): All 8 acceptance criteria met
- ✅ WindowDragHandler Extraction (Proposed): All 6 acceptance criteria met
- ✅ HUD Decomposition (Proposed): All 6 acceptance criteria met
- ✅ Config Refactoring (Proposed): All 9 acceptance criteria met
  🐛 Critical Bugs Found
  🔴 High Severity Issues:

1. CellView.swift:307 & 326 - abs(Int.min) crash risk when app name hashes to Int.min
2. HUDInput.swift:236-256 & WindowDragHandler.swift:62-74 - Use-after-free via unretained CGEventTap (no deinit cleanup)
3. SocketListener.swift:123 - Unchecked read() return value causing unexpected refreshes
4. App.swift:503-509 - Notification observer leak firing for every window close event
5. YabaiClientImpl.swift:31 - Silent failure when yabai is not installed (falls back to non-existent path)
6. TOMLParser.swift:22,35 - Silent config parse failures discarding user configuration
7. ConfigLoader.swift:91 - Force unwrap in serialization (technically unsafe)
8. HUDDisplay.swift:178 - Inconsistent notification name usage
   ##� Architecture Issues Found
   🏗️ Major Structural Problems:
9. God Objects:

- App.swift (895 lines) - handles launch, CLI, menubar, deep links, Sparkle, hotkeys, signals, settings, updates
- SettingsView.swift (922 lines) - contains all settings UI for 5 categories plus sub-views

2. Tight Coupling & Encapsulation Violations:

- HUDWindowController directly accesses sub-component internals (dragState, cellFrames, etc.)
- Hardcoded singletons (ThemeManager, IconCache, ThumbnailStore, etc.) create hidden dependencies
- Config static globals (silentMode) create testability problems

3. Separation of Concerns Violations:

- HUDInput mixes keyboard handling with panel drag monitoring
- HUDDisplay mixes rendering with config persistence (savePanelPosition)
- ConfigLoader mixes I/O, parsing, serialization, and backup

4. Testability Issues:

- Multiple modules impossible to test due to hardcoded system dependencies (FileManager, Process, NSWorkspace, etc.)
- No protocols for system services to enable mocking
- Global state pollution (Config.silentMode affects all tests)
  🧪 Test Coverage Gaps
  🔍 Untested Critical Paths:

1. YabaiClientImpl: Error handling when yabai is not installed or not executable
2. C: Config file corruption/missing file scenarios and backup logic
3. H: Rapid hotkey presses and HUD show/hide race conditions
4. W: Invalid drag operations (dragging to invalid cells, multi-window app ambiguity)
5. S: Socket connection failures and health check failures
6. T: ThumbnailCache functionality (ScreenCaptureKit-dependent, macOS 14+)
7. E: Edge cases in grid calculations (0 spaces, 0 windows, single space scenarios)
8. M: ThemeManager file loading and theme application logic
   🎯 Priority Recommendations
   Immediate Fixes (Critical):
9. Replace abs(Int.min) with .magnitude in CellView.swift
10. Add deinit methods to clean up CGEventTap in HUDInput and WindowDragHandler
11. Check read() return value in SocketListener.swift
12. Store and remove notification observers in App.swift
13. Improve yabai path detection error handling in YabaiClientImpl.swift
14. Return parse errors instead of nil in TOMLParser.swift
15. Replace force unwrap with safe access in ConfigLoader.swift
16. Use defined Notification.Name in HUDDisplay.swift
    Architectural Improvements (High):
17. Break down App.swift and SettingsView.swift into smaller, focused components
18. Convert hardcoded singletons to dependency-injected services
19. Reduce mutable properties in HUDInput and use constructor injection
20. Extract config persistence logic from HUDDisplay
21. Replace static globals with injectable services (Config, ThemeManager, etc.)
22. Add protocols for system services to enable unit testing
