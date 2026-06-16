# ADR-0002: Pivot to local calculation + public multi-city addon

- **Status:** Accepted
- **Date:** 2026-06-16
- **Supersedes:** ADR-0001 (Pre-generated table for a single city)
- **Decision makers:** Muhamed Bašić (PO), Claude (advisory)

## Context

ADR-0001 chose a pre-generated yearly table for a single city (Rotterdam),
optimised for a personal-use addon. The product intent has changed: the
addon will be **published publicly on CurseForge** under the name
**PrayerTimes**, and must cover major cities across Europe.

This breaks the assumptions behind ADR-0001:

- A pre-generated table scales linearly with cities × days. Covering many
  European cities for a full year produces a multi-megabyte Lua table that
  is loaded into game memory on every login. Login lag, memory cost, and an
  unmaintainable yearly regeneration of every city.
- A baked-in table expires at year end. For thousands of public users this
  means everyone silently gets wrong times until the author ships an update.
  Unacceptable for a public product, and unacceptable for prayer timing.

## Decision

Adopt **local calculation in Lua (former "Option A")** and **port the
`adhan-js` library** (batoulapps/adhan-js, MIT) into Lua as the calculation
engine. The addon computes prayer times on the user's machine from city
coordinates, date, calculation method, and Asr school. No internet at
runtime; no yearly regeneration; works anywhere.

The Python generator and pre-generated `*_Data.lua` table from ADR-0001 are
**discarded**.

## Rationale

- **Correctness risk is mitigated by porting, not inventing.** adhan-js uses
  high-precision astronomical equations from Jean Meeus' "Astronomical
  Algorithms" (the reference recommended by the US Naval Observatory and
  NOAA). We translate a proven, unit-tested implementation rather than
  writing the math from scratch.
- **JavaScript → Lua is the lowest-risk port.** Similar dynamic semantics,
  no static types to translate, readable source.
- **High-latitude handling already exists.** adhan-js provides a
  `HighLatitudeRule.recommended()` based on coordinates, important above 48°N
  (Amsterdam, Berlin, London, Scandinavia) — i.e. much of the target market.
  This was the single hardest part of "Option A" and it is already solved
  upstream.
- **Licence allows it.** adhan-js is MIT; porting, public release, and even
  commercial use are permitted with the copyright/licence notice retained.

## Consequences

Positive:
- One implementation covers all of Europe and beyond, indefinitely.
- No runtime internet dependency; no yearly maintenance of data tables.
- Clear upgrade path to Qibla direction and Sunnah times (adhan provides
  both), useful as public differentiators.

Negative / trade-offs:
- **Significantly larger scope** than the personal addon: full calculation
  engine, multiple methods, both Asr schools, high-latitude rules, city
  selection UI, localisation, CurseForge packaging, plus ongoing support
  and issue handling for public users.
- **Public correctness liability.** A bug in the Lua port sends wrong prayer
  times to real users. Phase 1 MUST verify ported output against adhan-js
  reference values before anything else is built.
- **Uncertain demand.** No competing Islamic prayer-time addon exists on
  CurseForge, which is both an opportunity (first mover) and a warning
  (small intersection of WoW players who want this in-game when a phone app
  already solves it). Build for interest and learning, not adoption targets.

## Licence obligation

Retain the adhan-js MIT licence text and copyright notice in the repo
(e.g. `THIRD_PARTY_LICENSES.md`) and credit batoulapps in the addon's
README and CurseForge description.

## Revisit when

- Phase 1 verification fails to match adhan-js within tolerance (then the
  port strategy itself is wrong and must be re-examined), or
- Demand proves high enough to justify Qibla/Sunnah/localisation investment.
