# ADR-0003: Timezone and DST handling (city-local time without a tz database)

- **Status:** Proposed
- **Date:** 2026-06-17
- **Decision makers:** Muhamed Bašić (PO), Claude (advisory)
- **Relates to:** ADR-0002 (local calculation). Governs sub-phase 2b.

## Context

The calculation engine returns each prayer time as **minute-of-day in UTC**.
To display a schedule we must convert to local time — and specifically to the
**selected city's** local time, not the player's machine time. A player in
Chicago viewing Istanbul must see Istanbul's clock.

Correct conversion requires the city's UTC offset *including daylight saving*
for the given date. The WoW Lua sandbox has no timezone database and no
network. The player's machine clock (`date`, `time`) reflects the player's own
locale, which is the wrong locale for the selected city. So we need a
self-contained way to compute each city's offset, with DST, from a date alone.

The target audience is the WoW **"EU" region**, which is broader than the EU
DST zone: it includes Russian and Turkish players on EU realms. The city list
must therefore include major Russian and Turkish cities, which do **not**
observe DST.

## Decision

1. **The engine stays UTC.** Timezone conversion is a separate display-layer
   concern (`engine/Timezone.lua`), never mixed into the astronomical math.

2. **Each city stores `{ baseUtcOffset, dstRule }`**, where `baseUtcOffset` is
   the standard-time offset in minutes and `dstRule` is a **named key** into a
   DST-rules table. The city's offset on a date is:

   ```
   offset(date) = baseUtcOffset + RULES[dstRule](year, month, day)
   ```

   where each rule function returns the DST adjustment in minutes (e.g. 0 or
   60) for that date.

3. **DST rules are an extensible lookup table of named rules — not hardcoded
   to EU.** Adding a new region later is **data plus one rule function**, not
   an architecture change. v1.0 ships exactly two rules:

   - **`"none"`** — always returns 0. Fixed offset, no DST. Covers Russia
     (Moscow / Saint Petersburg +3), Turkey (Istanbul / Ankara +3), Iceland
     (0), Belarus (+3), and — for free later — most of the Middle East
     (Saudi +3, UAE +4, etc.).
   - **`"EU"`** — the EU-harmonised rule (in force since 1996): DST = +60 min
     from **01:00 UTC on the last Sunday of March** to **01:00 UTC on the last
     Sunday of October**. Covers essentially all of EU/EEA Europe and,
     currently, the UK.

4. **Transition dates are computed from the Julian Day**, reusing the engine:
   `JD mod 7` yields the weekday, so "last Sunday of March/October" is pure
   arithmetic with no clock dependency. This keeps the whole conversion
   testable outside WoW.

5. **DST is decided at date granularity**, with the spring transition day
   counted as DST-on and the autumn transition day as DST-off — i.e. active
   when `lastSundayMarch <= date < lastSundayOctober`. This is exact for our
   use because the transition instant is 01:00 UTC and **every prayer time in
   the target latitudes falls after 01:00 UTC** (the earliest, Fajr, is well
   after it even in late March / late October, and the high-latitude
   safe-value clamping that could push Isha late is inactive near the
   equinoxes when the transitions occur). The verification (below) confirms
   this on the transition days themselves, not just around them.

6. **Verification against an authoritative source.** A Node generator uses the
   ICU/IANA timezone database (via `Intl` with the real zone, e.g.
   `Europe/Istanbul`) to emit reference **local** times for a representative
   sample of cities — across offsets 0/+1/+2/+3, both DST observers and
   non-observers — including dates straddling **both** the March and October
   transitions. `engine/Timezone.lua` + the engine must reproduce those local
   times within ±1 minute. This checks our hand-rolled DST against a real tz
   database at the boundaries.

## Expansion path (designed-for, not built)

Because the engine already computes times for any coordinates worldwide,
future geographic expansion is purely a **city-list + DST-rule** concern:

- **More `"none"` cities** (Russia other zones, Middle East): add rows with the
  correct fixed `baseUtcOffset`. Zero new logic. (Russia spans many zones; we
  store the correct per-city offset rather than inventing a "Russia rule".)
- **`"US"` rule:** 2nd Sunday of March → 1st Sunday of November. Same
  Julian-Day mechanism; add one rule function. Per-city exceptions (e.g.
  Arizona observes no DST) are handled by giving those cities `dstRule =
  "none"` — exactly what the table is for.
- **North Africa (e.g. Morocco):** DST is suspended during Ramadan, which
  tracks the **lunar** calendar. This needs a separate lunar-aware mechanism
  and is **explicitly out of scope** until built deliberately. Do not bolt it
  onto the solar date rules.

## Consequences

Positive:
- No tz database shipped; tiny data footprint; works offline in-sandbox.
- One rule covers the whole EU-DST market; `"none"` covers Russia/Turkey now
  and the Middle East later for near-free.
- Adding regions later is data + one function, verified the same way.

Negative / trade-offs:
- **Hand-rolled DST carries correctness risk** — mitigated by ICU-reference
  verification at the transition boundaries, which is mandatory for 2b's exit.
- **The EU rule could change** (the EU has debated abolishing DST). If it does,
  it is a one-function update, not a redesign; flagged for maintenance.
- **Pre-1996 dates and non-listed regions are not guaranteed.** v1.0 ships
  only the curated European/Russian/Turkish list; anything else is manual
  entry.
- **Manual lat/lon entry has no bundled zone.** The choice (let the user pick
  an offset vs. use the player's machine tz) is **deferred to 2c (UI)** and
  flagged, not guessed here.

## Revisit when

- ICU-reference verification fails at a transition boundary (then the rule
  model is wrong and must be re-examined), or
- Demand justifies a non-European region whose DST does not fit `"none"` or a
  simple solar rule (e.g. North Africa), or
- The EU changes or abolishes its DST rule.
