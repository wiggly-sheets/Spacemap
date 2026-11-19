# No migration code for config key renames

Spacemap's config self-heals: a missing key falls back to its default, sets `needsRepair`, and the next save rewrites the file. We lean on that instead of shipping alias or migration code when config keys are renamed. A renamed key therefore resets to its default until the user re-sets it; there is no translation layer, no deprecation period, and no compat list. Renames are still allowed when a name misleads, each one is noted in CHANGELOG, and the user hand-fixes their own config after upgrading. Migration code would outlive the keys it bridges and grow a permanent alias surface; the self-heal path already exists and stays deep.

## Consequences

- Pre-2.0 alias removals (see CHANGELOG 2.0.0 [Unreleased] "Removed") are the precedent; future architecture work (key table, opportunistic renames) follows it.
- Users who keep non-default values must re-enter them after a rename. The maintainer's own config is hand-fixed the same way.
- Future reviews should not re-suggest alias/compat layers for renamed keys; propose the rename in CHANGELOG instead.
