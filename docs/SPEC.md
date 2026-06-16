# PrayerTimes — Project Specification (v2.0)

**Owner:** Muhamed Bašić (Product Owner, not a developer)
**Builder:** Claude Code
**Status:** Spec v2.0 — public multi-city addon, local calculation
**Supersedes:** SPEC v1.0 (NamazTimes, single-city pre-generated table)
**Governing decision:** `docs/ADR-0002-local-calculation.md`

---

## 1. Goal

A public World of Warcraft addon, **PrayerTimes**, that calculates and
displays Islamic prayer times in-game for cities across Europe, and notifies
the player when a prayer time arrives. Distributed on CurseForge.

## 2. Approach (from ADR-0002)

Prayer times are **calculated locally in Lua** by porting the `adhan-js`
library (batoulapps/adhan-js, MIT). No internet at runtime, no pre-generated
data tables, no yearly regeneration. The user selects a city (or enters
coordinates); the addon computes times from coordinates + date + method +
Asr school.

## 3. Phased delivery

Phases are sequential. Do not start a phase until the previous one meets its
exit criterion. Each phase is itself broken into ~50-line checkpoints by
Claude Code at build time.

### Phase 1 — Calculation engine (the foundation)
- Port the adhan-js core math to Lua: Julian date, solar coordinates,
  equation of time, sunrise/sunset, Fajr/Isha angles, Asr shadow factor.
- Hardcode ONE city (Rotterdam, 51.9244, 4.4777), method MWL, Asr Standard.
- **Exit criterion:** for a set of fixed test dates, the Lua output matches
  adhan-js reference output for Rotterdam within ±1 minute. A verification
  table (date → expected times from adhan-js) is committed and checked.
- No UI work in this phase beyond printing times to chat for verification.

### Phase 2 — Display + city selection
- Port adhan-js `HighLatitudeRule.recommended()` and apply it.
- Display window (six times, next-prayer highlight, countdown), movable,
  lockable, position persisted per character.
- City picker: a bundled list of major European cities with coordinates,
  searchable; plus manual lat/lon entry. Selection persisted.
- Notifications (sound + center-screen + chat) for the five prayers.
- Slash commands: show, hide, lock, test, city.
- **Exit criterion:** switching city updates times correctly; high-latitude
  cities (e.g. Amsterdam, Stockholm) produce sane summer Isha/Fajr.

### Phase 3 — Methods + Asr schools
- Settings to choose calculation method (MWL, ISNA, Egypt, Makkah, Karachi,
  and others adhan-js supports) and Asr school (Standard / Hanafi).
- Persist per character. Defaults: MWL + Standard.
- **Exit criterion:** each method/school combo matches adhan-js reference
  for a sample city within ±1 minute.

### Phase 4 — CurseForge release
- Both Retail and Classic .toc manifests; verify current Interface numbers.
- README, THIRD_PARTY_LICENSES.md (adhan-js MIT text), CurseForge listing.
- String localisation scaffold (English baseline).
- Packaging metadata (.pkgmeta) and a changelog discipline.
- **Exit criterion:** clean install from a packaged build on both clients,
  no Lua errors, listing copy ready.

Out of scope for v1.0 release (candidate later): Qibla direction, Sunnah
(Qiyam) times, adhan mp3 audio, pre-prayer reminders, in-combat auto-hide.

## 4. Reference source

- Port from: https://github.com/batoulapps/adhan-js (MIT).
- Read its source and `METHODS.md` for method parameters and high-latitude
  rules. Do NOT reimplement the math from memory; follow adhan-js.
- Generate reference values by running adhan-js (Node) for the test cities
  and dates, and commit them as the verification fixtures.

## 5. Calculation defaults

- Default method: Muslim World League.
- Default Asr school: Standard (Shafi).
- Default high-latitude rule: adhan-js recommended-for-coordinates.

## 6. Client compatibility

Use only API stable on both Retail and Classic: `CreateFrame`,
`C_Timer`, `RaidNotice_AddMessage`, `PlaySound`, `date`, `time`.
The per-client difference is the `## Interface:` number; verify current
values at build time, do not hardcode from memory.

## 7. Definition of Done (v1.0 release)

- Phases 1–4 exit criteria all met.
- No Lua errors on Retail and Classic.
- Calculated times match adhan-js reference within ±1 minute across the
  tested cities, methods, and Asr schools.
- adhan-js MIT licence retained and batoulapps credited.
- README explains setup for a non-developer; CurseForge listing ready.
- All code, comments, and docs in English.

## 8. Risks (carry into README / listing)

- A port bug sends wrong prayer times to users. Verification against
  adhan-js is mandatory, not optional. Times are an aid; users should
  confirm against a trusted local source.
- High-latitude summer times are inherently contested; expose the
  high-latitude rule so users can adjust.
- Ongoing maintenance and user support are a real commitment for a public
  addon. Demand is uncertain.
