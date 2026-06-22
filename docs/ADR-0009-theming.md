# ADR-0009: Theming (Light / Dark), applied live

- **Status:** Accepted
- **Date:** 2026-06-22
- **Decision makers:** Muhamed Bašić (PO), Claude (advisory)
- **Relates to:** ADR-0005 (the cream/gold redesign that defines today's Light
  look). This generalises that single look into a switchable theme.

## Context

The addon currently has one hard-wired look (cream/gold, "Light"). Colours live
partly in per-file palette tables (`COL`) and partly as literals scattered
across the UI (border greys, near-white fills, toggle colours, etc.). The PO
wants a **Dark** theme, switchable from the UI, applied **live** (no `/reload`).

Live switching means every coloured surface must be re-colourable on demand.
That is only maintainable if all colours come from one palette and the coloured
regions are tracked so they can be repainted.

## Decision

1. **A `Theme` module with two palettes and colour roles.** `Light` (the
   current cream/gold) and `Dark`. Both define the same set of *roles* (e.g.
   `bg`, `content`, `header`, `text`, `muted`, `gold`, `border`, `card`,
   `cardSel`, `cardOff`, `sidebar`, `navHl`, `rowHl`, `slot`, `inputFill`, …).
   `Theme.color(role)` returns the active RGBA.

2. **A skin registry.** UI code paints through helpers instead of calling
   `SetColorTexture`/`SetTextColor` directly:
   - `Theme.tex(region, role)` — texture fill, applied now and recorded.
   - `Theme.txt(fontstring, role)` — text colour, applied now and recorded.
   On a theme change, `Theme.apply()` walks the registry and repaints every
   recorded region from the active palette.

3. **Dynamic (state-dependent) colours need no registry.** Colours chosen at
   update time (next-prayer row, Sunrise marker, selected Asr card, toggle
   on/off) already read the palette when they run. The palette table's values
   are swapped in place on a theme change, so re-running the existing update
   hooks (`Window.refresh`, `Picker.updateCalcControls` /
   `updateNotifyControls` / `refreshLocation`, wizard equivalents) repaints them.

4. **Persisted `PrayerTimesDB.theme`** = `"light"` (default) | `"dark"`.
   `Theme.set(name)` updates the active palette, calls `Theme.apply()`, and
   re-runs the update hooks of any built windows — repainting live, no reload.

5. **UI toggle in an existing tab.** A "Dark theme" switch at the bottom of the
   Notifications tab (reusing the tri-modal toggle). Also `/pt theme
   light|dark` for convenience.

6. **Gold accent is shared.** The gold used for accents/active states reads on
   both palettes, so it stays (perhaps a hair brighter on Dark); the big change
   is background/text inversion (cream↔charcoal, dark text↔light text).

7. **No engine/logic change.** Pure presentation; only `theme` is added to the
   DB. Cross-client safe (colour calls only). Icons are tinted at runtime, so
   they re-tint with the palette; the minimap logo is a fixed image (unchanged).

## Checkpoint plan (governed by this ADR)

- **T-1** `Theme` module (Light+Dark palettes, roles, `tex`/`txt` registry,
  `apply`, `set`) + route the **main window** (`Window.lua`) colours through it,
  including the literals. Live-switch the main window via `/pt theme`.
- **T-2** Route the **settings window** (`Picker.lua`) colours through Theme.
- **T-3** Route the **wizard** (`Wizard.lua`) and any minimap chrome through
  Theme.
- **T-4** "Dark theme" toggle in the Notifications tab; `Theme.set` repaints all
  open windows live; tune the Dark palette in-game.

Each checkpoint keeps a working, runner-green build and is verified in-game.

## Consequences

Positive:
- A real Dark option, switched live from the UI.
- All colours finally centralised in one place (easier future tweaks).

Negative / trade-offs:
- The largest change since the redesign: every colour call is routed through the
  registry (mechanical but broad). Done in phases to stay verifiable.
- Two palettes to maintain when adding future UI.

## Revisit when

- More themes are wanted (the registry already generalises to N palettes), or
- Per-element customisation (user-picked colours) is ever requested.
