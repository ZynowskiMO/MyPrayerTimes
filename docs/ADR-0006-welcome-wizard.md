# ADR-0006: First-run welcome wizard

- **Status:** Accepted
- **Date:** 2026-06-20
- **Decision makers:** Muhamed Bašić (PO), Claude (advisory)
- **Relates to:** ADR-0005 (settings redesign, Approach B). Reuses its widgets,
  components, and pure modules.

## Context

Until now, first-run onboarding was implicit: on a character with no saved
selection the settings/city picker auto-opened (`Picker.shouldAutoOpen`,
wired in `core/Main.lua`). That drops a new user straight into the full
settings window with no explanation of what the addon is or what to set.

The PO wants a proper **first-run welcome wizard**: a guided, multi-page flow
that introduces the addon and walks the user through the few choices that
matter (location, calculation method + Asr school, notifications), then hands
off to the normal display.

This is presentation + a single new persistence flag. It introduces no new
calculation behaviour and changes none of the proven logic.

## Decision

1. **A paged welcome wizard, shown once on first run.** A dedicated framed
   window (cream/gold, matching ADR-0005) with these pages:
   1. **Welcome** — wordmark + a short description of the addon.
   2. **Location** — choose country → city, or add a custom location.
   3. **Calculation** — calculation method + Asr school.
   4. **Notifications** — minutes-before, alert-at-time, sound.
   5. **Finish** — a summary/confirmation; "Done" closes the wizard and shows
      the main window.

   Navigation: **Next / Back**, a **step indicator** (dots), and **Skip** on
   every page. Skip (or finishing) accepts whatever is currently set —
   defaults are valid (Rotterdam / MWL / Standard / 10-min before), so the
   addon is usable even if the user skips immediately.

2. **New persisted flag `PrayerTimesDB.welcomed` (boolean).** The wizard is
   shown when `not db.welcomed`. Finishing or skipping sets `db.welcomed =
   true`, so it never reappears. This **replaces** the current first-run
   auto-open of the picker (`Picker.shouldAutoOpen`) in `core/Main.lua`; the
   picker remains available any time via the gear icon / `/pt settings`.

3. **Reuse, don't reimplement.** The wizard reuses the pure modules
   (`Selection`, `Cities`, `Methods`, `Notifier`) and the styled component
   helpers built for the settings window (row-pool dropdown, master-detail
   builders `masterRows`/`detailRows`, Asr cards, faux-pill toggles, flat
   buttons/edit boxes/checkbox, scrollbar). Each page's content mirrors the
   corresponding settings tab. Selecting/persisting happens live as the user
   moves through pages (same setters as the settings window), so "Finish" has
   nothing extra to save beyond the `welcomed` flag.

4. **No logic or other persistence change.** Engine, timezone, selection,
   validation, method/Asr resolution, notifications, and all existing DB keys
   are untouched. Only `welcomed` is added. The runner stays green at every
   checkpoint; new tests cover the wizard's paging/state under the mock.

5. **Cross-client constraint holds.** Frames, buttons, textures, fontstrings,
   and the existing custom components only — stable on Retail and Classic.

## Checkpoint plan (governed by this ADR)

- **3W-1** Wizard scaffold: framed paged window, Next/Back/Skip, step-dot
  indicator, page show/hide; page 1 (Welcome text).
- **3W-2** Location page (country → city + add custom).
- **3W-3** Calculation page (method dropdown + Asr cards).
- **3W-4** Notifications page + Finish (sets `welcomed`, opens the main
  window) + first-run wiring in `core/Main.lua` (open the wizard instead of
  the picker when `not db.welcomed`).

Each checkpoint keeps a working, runner-green build and is verified in-game by
the PO before the next begins.

## Consequences

Positive:
- A clear, guided first impression; new users understand the addon and set the
  essentials without hunting through the settings window.
- Almost entirely reuse; low risk, no logic change.
- The settings window remains the place to change anything later.

Negative / trade-offs:
- Another window to lay out and maintain (mitigated by reusing components).
- The wizard duplicates *layout* (not logic) of the settings tabs; if a tab's
  fields change later, the matching wizard page may need a parallel tweak.

## Revisit when

- The set of first-run choices changes (e.g. a new must-set option), or
- The PO wants the wizard reachable again on demand (e.g. a "run setup again"
  entry), or
- Onboarding analytics/telemetry are ever desired (out of scope; no network).
