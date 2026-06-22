# ADR-0008: Minimap button + addon logo

- **Status:** Accepted
- **Date:** 2026-06-22
- **Decision makers:** Muhamed Bašić (PO), Claude (advisory)
- **Relates to:** ADR-0007 (bundled icons; same Media folder + rasterise step).

## Context

The addon is opened via slash commands (`/pt`, `/pt settings`, `/pt setup`).
Many WoW players expect a small clickable button on the minimap to open an
addon. The PO also has a logo (a gold "PT" crest in WoW's icon style) and wants
it used in the addon.

A minimap button is commonly done with the **LibDBIcon-1.0 / LibDataBroker-1.1**
libraries. They are battle-tested and add an Addon-Compartment entry too, but
they pull bundled third-party library files (and their licences) into a repo
that has so far stayed dependency-free and hand-rolled.

The logo is a PNG; WoW loads only `.blp`/`.tga`, so it is rasterised offline to
a small `.tga` (the same pipeline as the Lucide icons).

## Decision

1. **A hand-rolled minimap button — no external libraries.** A small round
   button parented to `Minimap`, positioned on the minimap's edge by an angle,
   draggable around the edge, with the logo as its icon and the standard
   minimap tracking-border ring. Keeps the addon dependency-free (consistent
   with the rest of the project).

2. **Behaviour.** Left-click toggles the prayer-times window; right-click opens
   the settings window. A tooltip on hover names the addon and the clicks.

3. **New persisted setting: `PrayerTimesDB.minimap`** = `{ angle = <degrees>,
   hide = <bool> }`. The angle remembers where the user dragged the button;
   `hide` lets it be turned off (a `/pt minimap` toggle). No other persistence
   changes.

4. **Bundled logo asset.** The PO's PNG is rasterised to `Media/logo.tga`
   (white/colour preserved, sized for the ~20px button) via the existing build
   tooling. The licence/ownership is the PO's; recorded if needed. The larger
   PNG is also what the PO uploads as the CurseForge listing icon (that upload
   is separate and not shipped in the addon).

5. **Cross-client.** `Minimap`, `CreateFrame`, `Texture`, `GameTooltip` and
   `SetPoint` are stable on Retail and Classic. No new API.

6. **Placeholder-first.** The button is built first with a placeholder icon so
   the behaviour/position is verifiable immediately; the real `logo.tga` drops
   in once the PO supplies the PNG, with no code change.

## Checkpoint plan (governed by this ADR)

- **M-1** Hand-rolled minimap button: round button on the minimap edge,
  draggable (angle persisted), left-click → window, right-click → settings,
  tooltip, `/pt minimap` to show/hide. Placeholder icon. Runner covers the pure
  bits (angle math, show/hide, toggle wiring).
- **M-2** Rasterise the PO's PNG → `Media/logo.tga` and use it as the button
  icon (and document its origin).

Each checkpoint keeps a working, runner-green build and is verified in-game.

## Consequences

Positive:
- Familiar one-click access from the minimap; the addon feels complete.
- No new library dependencies; small bundled asset.
- Logo reused for the button and (separately) the CurseForge listing.

Negative / trade-offs:
- A hand-rolled button lacks LibDBIcon niceties (Addon Compartment, other
  addons' settings managers). Acceptable for a single, simple button; can be
  revisited if broader integration is wanted.

## Revisit when

- The PO wants Addon-Compartment / broker integration (would reconsider
  LibDBIcon), or
- More than one minimap entry/data source is needed.
