# Spec 0002 — EventTapHost: one module for all CGEventTaps

Status: approved (architecture review candidate 2, grilling settled)
Date: 2026-11-18
Scope: `HotkeyMonitor.swift` / `HotkeyTapRouter`, `WindowDragHandler.swift`, `HUDInput.swift`

## Problem

Three CGEventTaps (hotkey router, window drag, HUD settings-key monitor) each hand-roll install, teardown, one-second health timers, and revocation recovery. The copies have drifted: `HotkeyTapRouter.keyEventDecision` normalizes the hardware fn flag for function keys; `HUDInput.hotkeyMatches` does not, and it compares raw `hotkey.modifiers` against an inline copy of the relevant-flags mask — so a HUD binding carrying any non-relevant flag can never match, and function-key bindings behave differently global vs in-HUD.

## Design

One `EventTapHost` module owns the machinery all three taps duplicate:

- install (tap create via injected `EventTapFactory`, source add `.commonModes`, enable)
- teardown, per placement: tap-thread taps tear down with source-removed-first then per-thread perform-block (disable, invalidate, release, stop); main-loop taps tear down with disable-before-detach. The two orderings exist for different real reasons (comments in today's code) and must NOT unify.
- the 1-second health timer and the revocation state machine (`waitForPermission / remove / install / reinstall / reenable / none` — today duplicated byte-equivalent in `HotkeyMonitor.recoveryAction` and `HUDInput.keyboardTapRecoveryAction`)
- failure counting (`tapCreationAttempts` / `tapCreationFailureCount`, log on first and every 30th failure) — these stay visible for tests.

Consumers implement `EventTapConsumer`: event mask, placement (`tapThread` or `main`), listen-only flag, `handle(event)`. Retain discipline: weak-box context for tap-thread and listen-only consumers, as today; HUD keeps its strong-self release discipline.

Consumer-owned behaviour that stays in the consumer, unchanged:

- Hotkey router: binding snapshot under lock, key/media dispatch decisions, `isRecording` gate, private-thread placement.
- Drag handler: generation counter and stale-recovery guard, hover teardown, `CGPreflightListenEventAccess() || AXIsProcessTrusted()` trust provider, listen-only pass-through.
- HUD input: visibility gating, consume decision, accessibility-revoked notification, relaunch on revocation — relaunch moves behind an injected hook (default `SystemPermissions.relaunch`) so tests can install a HUD tap without restarting the test host.

`PermissionProbe` stays a separate module; the host and consumers keep funnelling through it.

## fn normalization fix

One shared matcher (on `Hotkey`) intersects both sides with `relevantModifierFlags`, drops `.maskSecondaryFn` from the event side only for function keys when the binding lacks it, then compares. `HotkeyTapRouter.keyEventDecision` and `HUDInput.hotkeyMatches` both route through it. `Hotkey.bindingIdentity` (used by settings identity checks) is the inverse direction and stays as is.

## Migration order

Hotkey router first (deepest test coverage), then drag, then HUD (inline callback + strong retain is the hairiest). Existing suites (`HotkeyTests` 784 lines, `WindowDragHandlerTests` 941, `HUDInputTests` 361) keep passing at each step; extend with a fn-parity regression: a HUD binding with a non-relevant extra flag must match once normalized, and a function-key binding without fn must match when hardware fn is held.

## Out of scope

media key handling, drag generation-counter redesign, `AccessibilityHealthMonitor` backstop, skhd compatibility, YabaiService.

## Non-goals / invariants preserved

Fail-open revocation policy unchanged: taps released, app keeps running, re-install when permission returns. All event marshalling to main stays `DispatchQueue.main.async`. Sources stay `.commonModes`; timers stay main-runloop `.common`.
