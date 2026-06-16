# ADR-0001: Prayer-time source strategy

- **Status:** Superseded by ADR-0002
- **Date:** 2026-06-16
- **Decision makers:** Muhamed Bašić (PO), Claude (advisory)

## Context

WoW addons run in a sandboxed Lua environment with **no network access**.
The addon cannot call a prayer-time API at runtime. Prayer times must
therefore be available locally. Three options were considered:

- **A. Astronomical calculation in Lua** — implement the prayer-time
  algorithm (sun angles per coordinate/date) directly in the addon.
- **B. Pre-generated table** — an external tool computes a full year of
  times; the addon reads a static data file. *(chosen)*
- **C. Manual entry** — the user types times into a config.

## Decision

Adopt **Option B**. A standalone Python generator fetches a full year of
prayer times from the **Aladhan API** (method=3 MWL, school=0 Standard Asr)
and emits a static Lua table the addon consumes. The generator runs on the
user's PC once per year.

## Rationale

- The Product Owner is not a developer and cannot verify a hand-written
  astronomical algorithm. A miscalculation that announces the *wrong*
  prayer time is a serious correctness failure, not a cosmetic bug.
- Option B moves the hard math out of the addon to a trusted external
  source (Aladhan), which the PO can compare against an official local
  schedule. The in-game Lua stays simple and auditable.
- Separation of concerns: "hard math, run once, verifiable" (Python) vs
  "simple display, runs in-game" (Lua).

## Consequences

Positive:
- In-game code is small, stable, and easy to review.
- Source of truth is an established prayer-times service, not our math.

Negative / trade-offs:
- Data file is bound to one location and one year; requires a yearly
  regeneration step (manual, ~1 command).
- Requires internet on the PC at generation time (not in-game).
- High-latitude (Rotterdam, 51.9°N) summer Isha/Fajr depend on Aladhan's
  default latitude-adjustment method; output must be verified against a
  trusted local source. If it diverges, revisit `latitudeAdjustmentMethod`.

## Rejected options

- **A (Lua calculation):** highest maintenance and verification burden on a
  non-developer owner; unacceptable correctness risk for religious timing.
- **C (Manual entry):** accurate but requires daily manual updates;
  impractical for sustained use.

## Revisit when

- The addon needs to support arbitrary locations without regeneration, or
- It will be distributed to other users (then Option A or a bundled
  multi-year dataset becomes worth the cost).
