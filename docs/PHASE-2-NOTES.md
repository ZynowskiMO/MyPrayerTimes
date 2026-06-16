# Phase 2 — build notes (carry forward)

These are builder notes for Phase 2 (Display + city selection). Phase 2 does
not start until Phase 1's exit criterion is met and confirmed by the owner.

## High-latitude rule must fix the summer Fajr/Isha clamp

In Phase 1, with adhan-js default parameters, Rotterdam (51.9°N) at the
summer solstice produces **Fajr and Isha both clamped to ~01:44 local** — the
sun never reaches the 18°/17° below-horizon angles, so the default
`MiddleOfTheNight` rule collapses both to the middle of the night. This is
correct adhan-js behaviour and is the locked Phase 1 ground truth.

Phase 2 must port `HighLatitudeRule.recommended()` and apply it. For latitudes
above 48°N this selects `SeventhOfTheNight`, which re-opens a usable spread.

**Add to the Phase 2 exit criterion:** verify that summer Fajr/Isha for a
>48°N city (e.g. Amsterdam, Stockholm) produce *usable* times — not the
midnight clamp seen in Phase 1. Compare against adhan-js run with the
recommended rule, within ±1 minute.
