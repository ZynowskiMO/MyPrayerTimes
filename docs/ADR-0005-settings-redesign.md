# ADR-0005: Settings window redesign (Approach B — sidebar + master-detail)

- **Status:** Proposed
- **Date:** 2026-06-19
- **Decision makers:** Muhamed Bašić (PO), Claude (advisory)
- **Relates to:** ADR-0002 (local calculation), ADR-0004 (methods/Asr). Supersedes
  the remaining Phase 3R checkpoints (3R-4 shrink, 3R-5 country/city dropdowns).

## Context

The settings window grew organically through Phases 2–3 and was being cleaned up
in Phase 3R (tab scaffold → dropdown component → form re-layout). The PO then
chose a more ambitious target from a set of mockups: **Approach B — a persistent
left sidebar plus a master-detail city picker** (country list → that country's
cities), with a dark header bar, a "current location" card, calculation method
as a dropdown, Asr as description cards, and notifications as a stepper + toggle
switches.

This is a re-layout and re-skin around the **existing, proven logic**. None of
the engine, timezone, selection, validation, My Cities, method/Asr resolution,
or persistence changes. The risk is almost entirely visual, plus the size of the
build.

## Decision

1. **Adopt Approach B as the settings-window target.** A persistent sidebar
   (Location / Calculation / Notifications, each a title + subtitle, active item
   marked) replaces the top tab bar from 3R-1. The Location tab becomes a
   master-detail: a country list (with per-country city counts) on the left and
   that country's cities on the right, the selected city checkmarked, **plus**
   the existing cross-city search box and a "current location" card. The
   Calculation tab keeps the 3R-2 method dropdown and turns the Asr radios into
   two description cards. The Notifications tab uses a −/+ minutes stepper and
   two toggle switches.

2. **No logic or persistence change.** This ADR governs presentation only. The
   pure modules (`Selection`, `Cities`, `Methods`, `Notifier`, …) and the DB keys
   (`selectedCity`, `savedCities`, `method`, `madhab`, `notify`) are untouched.
   The runner stays green at every checkpoint; existing pure-logic tests continue
   to cover behaviour, and new tests cover the new presentation wiring under the
   mock.

3. **Reuse, don't discard, the 3R work.** The `showTab`/panel mechanism, the
   row-pool dropdown component (3R-2), the Asr selection logic, and the
   add-location form (3R-3) are reused. Only the 3R-1 top tab bar is reworked
   into the sidebar.

4. **Skin approach: approximation first, art slots for later.** The visual style
   (cream/charcoal/gold palette, cards, separators, highlights, checkmarks,
   steppers, a faux pill-toggle, a mildly rounded frame via built-in WoW frame
   art) is built **with solid-colour textures (`SetColorTexture`) and built-in
   WoW textures only — no external image files**. Pixel-faithful chrome
   (true rounded-corner nine-slice, soft drop shadow, the exact serif wordmark,
   polished pill-toggle art) requires bundled `.tga/.blp`/font assets, which are
   **out of scope until the PO supplies them**. The layout will expose clearly
   named texture "slots" so PO-supplied art can drop in during the final polish
   without touching layout or logic.

5. **No new code dependency is added now.** v1.0 ships zero bundled art or fonts
   under this ADR. If the PO later supplies art/fonts, bundling them is a small,
   additive change (and its licensing, if any, recorded in
   `THIRD_PARTY_LICENSES.md`).

6. **Cross-client constraint holds.** Only widgets stable on both Retail and
   Classic are used — frames, buttons, textures, fontstrings, the row-pool
   dropdown. No Blizzard `UIDropDownMenu`, no Retail-only APIs.

## Checkpoint plan (governed by this ADR)

- **3S-1** Frame chrome + sidebar navigation (wider frame, dark header with
  wordmark + current-location + close, left sidebar, right content area).
- **3S-2** Location master-detail (country list with counts → cities with
  checkmark) + cross-city search + current-location card.
- **3S-3** My Cities group (with delete) + "Add custom location" panel (the
  3R-3 form).
- **3S-4** Calculation: method dropdown + Asr description cards.
- **3S-5** Notifications: −/+ minutes stepper + at-time and sound toggles.
- **3S-6** Skin polish (palette, separators, rounded/shadow approximation,
  wordmark, hover/selected states, spacing; art slots ready for PO art).

Each checkpoint keeps a working, runner-green window and is verified in-game by
the PO before the next begins.

## Consequences

Positive:
- A materially more polished, structured settings UI; one focus at a time;
  city selection by drill-down *or* search.
- Logic untouched → low correctness risk; the proven foundation is preserved.
- Art can be upgraded later with no layout/logic rework.

Negative / trade-offs:
- **Largest UI build of the project so far** — six presentation checkpoints.
- **Not pixel-identical to the mockup without bundled art.** The approximation
  is close (~85–90%); the last ~10% (true rounded corners, shadow, serif logo,
  pill-toggle art) waits on PO-supplied assets.
- Wider window uses more screen space; must stay movable and sane at common UI
  scales.

## Revisit when

- The PO supplies texture/font art (then a polish pass wires it into the slots),
  or
- A widget proves unstable on Classic (then approximate it differently), or
- Scope pressure from Phase 4 (CurseForge release) argues for shipping the
  approximation and deferring further polish.
