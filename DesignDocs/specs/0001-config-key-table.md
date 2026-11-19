# Spec: Config key table (ConfigSchema)

Settled 2026-11-18 via architecture review grilling. Status: Implemented.

## Problem

Every config key is declared in nine hand-kept lists across six files: `GridConfig` fields, `ConfigValues` optionals, copy assignments, resolve/clamp/repair, TOML decode lines, TOML encode lines, section-flatten lists, settings `@State` seeds, and the settings constructor. A missing line fails silently (Glass Style lost data this way: bound with no save hook). 93 fields today.

## Design

One KeyPath-based `Field` table in a new `ConfigSchema.swift`; decode, encode, defaults, section flattening, and repair all walk it.

- `Field<T>`: `WritableKeyPath` into the config value + TOML key + section + repair kind.
- Repair kinds mirror today's `ConfigValues` helpers exactly: `orDefault`, `valid(predicate)`, `clamp(range)`.
- Hotkeys, spaceNames, and profiles register as Fields with custom decode/encode closures, so section flattening, presence tracking, and `needsRepair` stay uniform. **As-built deviation:** hotkeys do register as Fields, but `spaceNames` and `spaceNameProfiles` stayed hand-coded custom-table paths (`TOMLConfigCodec.swift:406-420`, `:472-537`; `ConfigLoader.swift:338-349`, `:434-459`) because their nested-table shapes and the indexed profile schema do not fit one KeyPath row, and the fold kept them hand-coded by decision.
- `ConfigValues` and the `AppConfig` facade fold away; repair logic and `needsRepair` move inside the new module; preset store and CLI write through the same encode. The `ConfigLoader` disk layer (O_NOFOLLOW, secureWrite, backup rotation) is untouched beneath.
- Callers keep reading the same value type. The final commit renames `GridConfig` → `SpacemapConfig` (GLOSSARY: avoid `GridConfig`).

## Rules settled with the maintainer

- Pipeline only; settings UI bindings are a separate candidate (SettingsDraft).
- Key renames are opportunistic (misleading names only), noted in CHANGELOG, with **no migration code** (ADR 0001).
- Migration is section by section: grid, appearance, behavior, advanced; round-trip tests green at each step.

## Test surface

- Per section: defaults encode → decode → same config (round-trip).
- Repair: missing key → default + `needsRepair`; bad value → default; oversize → clamp.
- Ported from existing `ConfigValues` tests to the new seam.

## Out of scope

Settings UI bindings, theme pipeline, panel persistence (separate candidates). The `[hudKeys]` table and hotkey TOML shapes do not change.
