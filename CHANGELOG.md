# Changelog

All notable changes to PrayerTimes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project uses
[semantic versioning](https://semver.org/).

## [0.9.0] - 2026-06-22

First public beta.

### Added
- Local in-game calculation of the five daily prayer times plus sunrise, ported
  from adhan-js and verified to within ±1 minute.
- Built-in European city list, country → city picker, search, and custom
  locations (latitude/longitude + UTC offset, optional EU daylight saving).
- All standard calculation methods and the Asr school (Standard / Hanafi),
  with the adhan-js recommended high-latitude rule.
- Reminders: minutes-before each prayer, an at-time alert, and an optional sound.
- Movable / lockable display window with a minimise mode and a settings gear.
- First-run welcome wizard (location → calculation → notifications → summary).
- Lucide icons throughout the interface.

### Notes
- Calculated times are an aid; confirm against a trusted local source.
- Tested on Retail and TBC Classic.
