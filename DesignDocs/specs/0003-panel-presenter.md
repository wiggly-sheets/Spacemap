# Spec 0003 — ScreenContext and PanelPresenter

Status: Approved (architecture review, candidate 3 — Worth exploring)
Blocks: candidate 9 (glyph strip policy fold consumes ScreenContext's menu-bar row)

## Context

The HUD and the glyph strip each hand-roll the same panel machinery:

- Panel creation: `GlyphStripPanelController.makePanel` and `HUDDisplay.makePanel` use the same style mask, clear background, nonactivating panel.
- Fades: both guard `NSApp.isRunning` and re-order the panel on completion.
- Quartz-to-AppKit frame flip: duplicated (`appKitFrame` vs inline in HUDDisplay).
- Drag-and-persist: two schemes — the strip stores x/y offsets in config; the HUD stores a normalized fraction plus a screen key in UserDefaults.
- Screen knowledge: notch rows, safe-area/dock detection (`safeScreenFrame`), fullscreen detection (`hasFullscreenAppInFront`), and menu-bar row math live only inside `GlyphStripPanel.swift` (2887 lines). The HUD cannot reach them.

`HUDGeometry` (36 lines) is already shared by both panels — the seam half-exists.

## Decision

Two new modules; each panel surface keeps only its content geometry.

### ScreenContext

Owns five jobs, pure functions where possible:

1. Screen lookup (which screen a position/point belongs to; fallback when a stored screen identity is gone).
2. Quartz-to-AppKit frame flip.
3. Menu-bar row math (segment row for menu-bar-anchored strip placement).
4. Safe-area/dock detection (`safeScreenFrame`).
5. Fullscreen detection (`hasFullscreenAppInFront`).

Menu-bar row math is screen geometry, not strip policy — it lives here, not in GlyphStrip (candidate 9 consumes it from here).

### PanelPresenter

Owns panel lifecycle:

- Make panel (style mask, clear background, nonactivating panel).
- Fade present/hide (guard `NSApp.isRunning`, re-order on completion).
- Drag-and-persist: one persistence scheme for both surfaces — fraction of screen plus screen identity, written to config.toml (ADR 0002). The strip's x/y offset keys die; the HUD's UserDefaults position dies. No migration code (ADR 0001): positions reset once; the user re-drags the HUD once.

### Behavior rules

- Fullscreen hiding: ScreenContext exposes `hasFullscreenAppInFront` now; the HUD adopts hiding as a separate later change. Restructure first, behavior second.
- Both surfaces keep their own content geometry (strip segment layout, HUD grid sizing).

## Migration

1. Extract ScreenContext from `GlyphStripPanel.swift` (deepest owner), test the pure functions directly.
2. Extract PanelPresenter (panel factory, fades, drag-and-persist).
3. HUD consumes both; `HUDGeometry` folds into ScreenContext.

## Tests

- ScreenContext: direct pure-function tests (quartz flip, safe area, menu-bar row). Fullscreen detection requires live AX/window-list access — verified by manual on-device run, not unit tests (no seam added for it).
- PanelPresenter: via injected panel factory, mirroring the existing `HUDDisplay.screenFramesOverride` pattern.
- The 6 existing strip panel tests (repaint counting, wedge latch, quartz frame, menu-bar row) port to the new seams.

## Out of scope

- HUD fullscreen-hiding adoption (follow-up change).
- Menu-bar click targeting redesign.
- ThumbnailCache, IconCache.
- Glyph strip model/policy split (candidate 9).
