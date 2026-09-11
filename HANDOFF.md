# Spacemap repository-audit fix handoff

## Goal and current state

Finish the deep repository audit requested by the user, fix every confirmed issue on the feature branch, validate the complete app, and commit the work locally. Do not push unless the user explicitly asks.

- Repository: `/Users/Zeb/Developer/spacemap`
- Feature branch: `codex/repo-audit-fixes`
- Base when work began: `main` / `origin/main` at `9e8df7c`
- Worktree: intentionally contains a large set of **uncommitted** audit fixes. Preserve it; do not reset, checkout, clean, or discard files.
- The background reviewers were stopped when this handoff was written. Run one final diff review after completing the remaining items.
- Read `DesignDocs/AGENTS.md` before continuing. It requires an Unreleased changelog update and tests.

The primary user-reported bug was: if Accessibility permission is removed while Spacemap is running, keystrokes can remain intercepted/lost until permission is restored. The implementation now fails open per event, but installed/live macOS verification still requires explicit permission from the user before changing Accessibility settings or replacing the installed app.

## Implemented work

### Accessibility, keyboard taps, and hotkeys

- `HotkeyMonitor` checks `AXIsProcessTrusted()` inside every event-tap callback. If trust was revoked, it disables the tap immediately and returns the event to macOS.
- `HUDInput` uses the same fail-open behavior and hides/notifies the HUD on revocation.
- Both taps now reconcile missing, invalid, and disabled taps instead of remaining dead.
- Reopening the HUD while permission is still denied resets the per-presentation revocation notification, so it is hidden again instead of remaining unusable.
- Pinned HUDs consume only recognized HUD key-down actions; unrelated keys and key-up events pass through.
- Matching global-hotkey repeats remain consumed so they cannot leak into the foreground app, but only the initial press triggers the HUD.
- Media-key releases and repeat packets no longer trigger shortcuts.
- One shared `HotkeyService` now owns the normal/pinned monitor pair; restarts stop every previous monitor.
- Accessibility, recovery-policy, repeat, pinned pass-through, and monitor-ownership regressions were added.

### HUD, rendering, themes, and window dragging

- Separate-display grids use their supplied space indices for rendering, sizing, clicking, and drag targets.
- Theme resolution is shared and now reloads on HUD config/presentation reload so edited `.smthemes` files are observed.
- Application colors use deterministic FNV-1a hashing and real saturation/lightness variation.
- Pinned state has one source of truth in `HUDInput`.
- Focused-window state is persisted/cleared safely with presentation-generation guards.
- Drag event callbacks no longer run yabai commands synchronously and always pass mouse events through.
- Drag taps recover after timeout/user disable but do not recreate themselves after `stop()`.
- Each mouse-down requests a fresh focused-window/window snapshot on the yabai queue. A drag waits for that snapshot rather than moving a stale window in a pinned HUD.
- Queued drops are generation-checked and ignored after hide/stop; the HUD controller also verifies visibility.

### Settings, config, and lifecycle

- Settings update-mode changes save immediately.
- The hotkey recorder has cancellation, repeated-start protection, monitor cleanup, bare-Escape cancellation, modified-Escape support, and a shared coordinator so the two recorders cannot listen simultaneously.
- Exact custom scale, alpha, socket interval, and grid geometry values are represented instead of silently snapping to presets.
- Settings window frame autosave/restore is stable.
- App reopen uses the shared `SettingsService`.
- About-window reuse now consults `SettingsService`'s owned controller instead of sending an undefined selector to `AppDelegate`.
- Settings diagnostics use the injected `YabaiService`.
- Invalid numeric, enum, hotkey, modifier, and space-name entries mark the config for repair and are rewritten while valid mixed entries are preserved.
- First-launch prompts delegate to `CLIToolsService`, which already has explicit login/update choices.
- All CLI/first-launch alerts temporarily activate the app and restore the previous activation policy.
- Delayed MRU/separate-Spaces warnings do not demote the app while a Settings/About window is visible.
- Runtime config changes selectively restart hotkeys/socket/updater/signals.
- Yabai signal registration is queued off the main thread and coalesces stale requests.

### Socket, yabai process execution, menu bar, packaging, and release

- Unix clients are nonblocking and time out, the socket is mode `0600`, and stalled clients do not block later commands.
- Yabai subprocess stdout/stderr are drained while running, with command and pipe-drain timeouts.
- Full workspace previews subscribe to geometry and topology changes; dot previews avoid geometry work.
- Menu-bar status items are removed through `NSStatusBar`, and the displayed shortcut title updates live.
- `GridState` equality compares complete semantic state.
- All app/architecture/install targets copy and verify 14 `.lproj` bundles.
- 638 invalid lowercase `\u` escapes in Apple strings files were converted to valid `\U` escapes.
- `CFBundleDevelopmentRegion` is now `en`.
- Release CI runs tests; verifies tag/`VERSION`/plist consistency, bundle versions/localizations, architectures, assets, and appcast structure.
- Appcast generation now preserves complete prior items and avoids duplicating the current version.

### Removed dead modules

- `ConfigClerk.swift`
- `SettingsHandler.swift`
- `IconCacheService.swift`
- `ThumbnailCacheService.swift`
- `MenubarManager.swift`
- `MenubarService.swift`

No live source references remained when checked.

## Remaining confirmed work

Address these before the final full test/build/commit:

1. **Fix DispatchSource descriptor ownership in `SocketListener.swift`.**
   A final review found that sources are cancelled and their file descriptors are also closed immediately. A pending handler can then run against a newly reused descriptor. Every descriptor owned by a `DispatchSourceRead` should be closed exactly once in that source's cancellation handler, after pending handlers are finished. Apply this to both accepted clients and the server source. Do not reintroduce a test-side leak: `stalledClientSocket` is the separate connecting descriptor and must still be closed by the test.

2. **Make appcast history fail closed on fetch failure.**
   `.github/scripts/generate-appcast.sh` currently treats a failed/empty `curl` as “no history” and successfully emits a one-item feed. A transient GitHub Pages outage could permanently truncate history. Use `curl -fL`, validate the fetched XML, and either use a separately validated checked-in fallback or exit nonzero. Add a regression where an unavailable `file://`/HTTP source fails rather than publishing a truncated feed. Preserve first-release behavior deliberately if needed.

3. **Fix the definite localization-key mismatch and audit missing keys.**
   `MenubarHandler` requests `Open Accessibility Permissions (for hotkeys)` while all localization tables contain the singular key `Open Accessibility Permissions (for hotkey)`. Make the source key match the tables or update every table. A reviewer also found roughly 21 literal `NSLocalizedString` keys absent from the English/all tables (About, update/CLI prompts, full yabai message, preview accessibility labels). Decide whether to add real translations or document intentional English fallback; do not claim complete UI translation without checking.

4. **Consider deleting the final unused deprecated yabai facade.**
   `Sources/spacemap/YabaiClient.swift` has no production callers; only `Tests/spacemapTests/YabaiClientTests.swift` calls it, producing many deprecation warnings. The equivalent instance behavior is covered in `YabaiClientImplTests`. If a fresh `rg` confirms this, delete both legacy facade and facade-only tests, retain/move any unique assertions, and update the changelog.

5. **Clean the remaining obvious test warnings/false test.**
   - `MenuBarPreviewRendererTests.testImageReturnsNilForIconMode` currently builds state but has no assertion; call `image(for:)` and assert nil.
   - Remove the unused local in `GridLayoutTests.testAllModeShowsAllSpaces`.
   - Update the deprecated tuple-style `DragState.dragging` pattern in `WindowDragHandlerTests`.

6. **Re-review the newest follow-up changes.**
   The final follow-up reviewer was interrupted to conserve usage. Pay special attention to `WindowDragHandler`, `HUDInput`, `ApplicationLifecycleService`, `CLIToolsService`, `SettingsGrid`, `ConfigValues`, and `TOMLConfigDecoder`.

7. **Run the complete validation matrix and commit.**
   Nothing has been committed yet. Do not push.

## Validation already completed

After the newest follow-up fixes:

- `HUDInputTests` + `WindowDragHandlerTests`: 34 passed.
- `SettingsTests`: 10 passed.
- In the preceding combined run, before an already-fixed test-only `NSApp` crash stopped xctest:
  - `ApplicationLifecycleServiceTests`: 4 passed.
  - `ConfigLoaderTests`: 12 passed.
  - `HUDInputTests`: 8 passed at that point (now 9 passed separately).
  - `HotkeyTests`: 19 passed.
- `ConfigLoader` all-invalid and mixed-invalid space-name repair tests passed.
- The About-window test crash was caused by XCTest not initializing `NSApplication`; the test now initializes `NSApplication.shared` and all 10 Settings tests pass.

Before the last root follow-ups, the I/O lane also reported:

- Socket tests: 8 passed.
- Yabai tests: 21 passed, one environment-dependent skip.
- Menu/model focused tests: 64 passed.
- Production release build passed.
- `make app` passed and verified 14 packaged locales.
- A German lookup from the packaged bundle returned `Einstellungen...`.
- All localization files and `Info.plist` parsed successfully.
- Release workflow YAML parsed and `git diff --check` passed.

Those build/package checks must be rerun after the newest changes.

One attempted test with a fresh `/private/tmp` SwiftPM scratch directory failed only because the sandbox could not resolve GitHub to fetch Sparkle. Use the repository's populated `.build` directory unless dependency refresh is explicitly approved.

## Required final commands

Use writable module caches:

```sh
env CLANG_MODULE_CACHE_PATH=/private/tmp/spacemap-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/spacemap-swiftpm-cache \
    swift test --disable-sandbox

env CLANG_MODULE_CACHE_PATH=/private/tmp/spacemap-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/spacemap-swiftpm-cache \
    swift build -c release --product Spacemap --disable-sandbox

make app
make --no-print-directory verify-localizations BUNDLE=Spacemap.app
bash -n .github/scripts/*.sh
git diff --check
git status --short
```

Also:

- Parse every `Sources/spacemap/Resources/*.lproj/Localizable.strings` with `plutil -lint`.
- Parse `Sources/spacemap/Info.plist`.
- Validate `.github/workflows/release.yml` with an available YAML parser.
- Re-run local appcast preservation, duplicate-version, retention-limit, malformed/fetch-failure tests.
- Confirm `rg` finds no references to deleted types and no lowercase `\\u[0-9a-fA-F]{4}` strings escapes.
- Inspect the final source diff, especially the very large localization mechanical change.

## Suggested local commit grouping

Git metadata writes require the existing repository approval/escalation. Stage only task files.

1. `Fail open keyboard taps when Accessibility is revoked`
2. `Keep HUD rendering and window dragging current`
3. `Repair Settings and configuration lifecycles`
4. `Harden socket, yabai, packaging, and release checks`
5. `Remove unused service facades and clean regressions`

Adjust grouping where files overlap, but keep commits coherent. Verify the branch is still `codex/repo-audit-fixes`, inspect each staged diff, commit locally, and leave the branch unpushed.

## Optional live macOS verification (ask first)

Do not modify the installed app or Accessibility permission without explicit user approval. If approved, validate with a stable installed build identity:

1. Start Spacemap with Accessibility granted and confirm normal and pinned shortcuts.
2. Show/pin the HUD, then revoke Accessibility while Spacemap remains running.
3. Type ordinary and formerly bound keys in another app; no key should be swallowed, delayed, or intercepted, and the HUD should hide.
4. Regrant Accessibility without restarting; the global shortcut should recover through the health reconciliation loop.
5. Confirm pinned HUD unrelated keys pass through and held shortcuts do not leak repeats into the foreground app.

Report unit/build/package results separately from this live check if live permission mutation is not authorized.
