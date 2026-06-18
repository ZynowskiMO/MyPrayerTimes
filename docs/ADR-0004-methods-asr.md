# ADR-0004: Calculation methods and Asr school (user-selectable, fixture-gated)

- **Status:** Accepted
- **Date:** 2026-06-18
- **Decision makers:** Muhamed Bašić (PO), Claude (advisory)
- **Relates to:** ADR-0002 (local calculation). Governs Phase 3.

## Context

Phase 1/2 ship a single hardcoded configuration: **Muslim World League (MWL)**
angles with the **Standard (Shafi)** Asr school. The engine
(`engine/PrayerTimes.lua`, `engine/CalculationParameters.lua`) already reads its
behaviour from a parameter table — Fajr angle, Isha angle, Isha interval, Asr
school, per-prayer adjustments, and the high-latitude rule — so the math is
parameterised even though only one parameter set is exposed.

The "EU" region audience uses several different conventions: Diyanet in Turkey,
Umm al-Qura in the Gulf-facing community, ISNA among North-American-influenced
users, Egyptian, Karachi, and others. Phase 3 exposes the **method** and the
**Asr school** as user-selectable, persisted settings. The default stays MWL +
Standard so existing users see no change.

adhan-js (our ported source of truth) defines its methods as factory functions
that return a parameter table. For most methods that table is built only from
fields our engine already honours, so adding them is data, not logic. Two
methods are exceptions and are called out explicitly below.

## Decision

1. **Methods are parameter tables, ported verbatim from adhan-js.** Each method
   is a factory returning a `CalculationParameters` table, mirroring
   `CalculationMethod.*` in adhan-js. We do **not** invent or tune any angles.
   v1.0 exposes the full adhan-js method set **except** MoonsightingCommittee
   (see point 4):

   - **MuslimWorldLeague** (default), **Egyptian**, **Karachi**,
     **UmmAlQura** (Makkah), **Dubai**, **NorthAmerica** (ISNA), **Kuwait**,
     **Qatar**, **Singapore**, **Turkey** (Diyanet), **Tehran**, and **Other**
     (zero angles — for the advanced/manual case).

2. **Asr school is the existing `Madhab` switch.** `Standard` = Shafi
   (shadow factor 1), `Hanafi` = shadow factor 2. Already ported in
   `engine/Madhab.lua` and consumed by `SolarTime:afternoon`. Default
   `Standard`. No engine change — only exposure.

3. **One genuine engine addition: a Maghrib twilight angle (for Tehran).**
   Our engine currently sets Maghrib = sunset unconditionally. Tehran defines
   Maghrib by a **twilight angle** (sun a few degrees below the horizon), not
   plain sunset. We add an optional `maghribAngle` to `CalculationParameters`
   and port adhan-js's Maghrib-angle branch into `PrayerTimes.lua`: when a
   method sets a Maghrib angle, Maghrib is the angle-based time when that falls
   after sunset (else sunset). Methods without a Maghrib angle are unchanged.
   This is a faithful port, fixture-verified like everything else.

4. **MoonsightingCommittee is deferred (out of scope for v1.0).** It is **not**
   a parameter set: it computes Fajr/Isha from a **seasonal, latitude-dependent
   twilight algorithm** with its own "shafaq" (twilight-colour) logic. That is a
   separate code path with its own correctness surface. It will be its own small
   project — a dedicated ADR plus its own fixtures — added later without
   disturbing the parameter-table methods. v1.0 ships every other method.

5. **New persisted settings, per character** (same pattern as city/notify):
   - `PrayerTimesDB.method` — a method **key** string (default
     `"MuslimWorldLeague"`).
   - `PrayerTimesDB.madhab` — `"shafi"` | `"hanafi"` (default `"shafi"`).

   Settings init supplies the defaults if absent. A method/Asr registry
   (`engine/Methods.lua`: key → factory, plus an ordered list of
   `{ key, label }` for the UI) is the single source the settings UI and the
   resolver share. Unknown/missing keys fall back to the MWL default rather than
   erroring, so a stale saved value can never break the window.

6. **The high-latitude rule stays latitude-keyed and method-independent.**
   `HighLatitudeRule.recommended()` keys off **latitude only** (>48° →
   SeventhOfTheNight, else MiddleOfTheNight) and is applied per city regardless
   of the chosen method. Switching method changes Fajr/Isha **angles**, which
   changes *how often* the high-latitude safe-value clamp engages in summer
   (a 15° ISNA Fajr is reached on more days than a 20° Singapore Fajr), but it
   does **not** change which rule is selected. This is correct behaviour, not a
   bug. The verification below deliberately tests a >48° city under multiple
   methods so the clamp interaction is **proven against adhan-js per method**,
   not assumed.

7. **Verification — every method × Asr school × city, gated at ±1 minute.** A
   Node generator enumerates **all exposed methods × {Standard, Hanafi}** over a
   small city set that **includes at least one >48° high-latitude city**, with
   the generator mirroring the exact high-latitude policy the addon uses
   (`recommended()`), and emits adhan-js reference times. The runner reproduces
   them within ±1 minute. The **Phase 1/2 fixtures stay in the suite as a
   regression guard.** A method that fails the gate is the engine reporting a
   parameter it does not yet model — gaps are **discovered, not guessed** — and
   we close them (e.g. the Maghrib angle in point 3) until the whole matrix is
   green. adhan-js is reinstalled to run the generator; the pinned version is
   recorded in the fixture metadata.

## Expansion path (designed-for, not built)

- **MoonsightingCommittee:** future ADR + algorithm port (seasonal twilight +
  shafaq) + its own fixtures. The method registry already tolerates being
  extended by one more key.
- **Custom angles:** the `Other` method plus existing `adjustments` already
  allow an advanced user to enter arbitrary angles; a UI for that is out of
  scope for v1.0 but the engine path exists.
- **Per-method method-adjustments** (the small fixed minute offsets some methods
  apply, e.g. Dubai/Singapore) are part of each ported factory and need no new
  mechanism — `methodAdjustments` is already summed in `PrayerTimes.lua`.

## Consequences

Positive:
- Most methods are pure data; adding them is near-free and low-risk.
- One small, faithful engine change (Maghrib angle) unlocks Tehran for a real
  audience and is fixture-verified.
- The registry is the single source for both the UI and the resolver, so the
  list cannot drift between them.
- Default unchanged → no surprise for existing users.

Negative / trade-offs:
- **The Maghrib-angle branch is new engine behaviour**, so it carries the only
  real correctness risk in Phase 3 — mitigated by the ±1-minute gate including
  Tehran.
- **MoonsightingCommittee absence** may disappoint a few users; deferred
  deliberately rather than shipped half-ported.
- **More method × school × city combinations** enlarge the fixture set and the
  regenerate step (acceptable; it is the whole point of the gate).

## Revisit when

- The ±1-minute gate fails for any method (then a parameter is unmodelled or a
  port is wrong, and the engine must be re-examined), or
- Demand justifies MoonsightingCommittee (its own ADR), or
- adhan-js changes a method's published parameters (re-port + regenerate).
