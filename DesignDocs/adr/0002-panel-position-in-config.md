# One panel-position scheme, stored in config

The HUD persisted its position as a normalized fraction plus a screen identity in UserDefaults; the glyph strip persisted raw x/y offsets in config. Two schemes for the same problem, both hand-rolled, meant every panel-placement fix had to land twice and behaved differently per surface. We decided one scheme: a fraction of screen plus screen identity, written to `~/.config/spacemap/config.toml`, consumed by both the HUD and the strip. The strip's offset scheme and the HUD's UserDefaults entry die. Migrating either old format would need alias code (see ADR 0001), so positions reset: the HUD keeps its anchored placement and any custom-dragged position is re-dragged once.

## Consequences

- Screen identity survives monitor changes; raw offsets did not, which was a latent bug in the strip scheme.
- One drag-and-persist path behind the PanelPresenter seam; placement fixes land once for both surfaces.
