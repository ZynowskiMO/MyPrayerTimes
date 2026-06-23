# Changelog

All notable changes to MyPrayerTimes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project uses
[semantic versioning](https://semver.org/).

## [1.0.2] - 2026-06-23

### Changed
- New final logo (the gold "M" coin) on the minimap button and in the settings
  sidebar, with the version and author centred beneath it.

## [1.0.1] - 2026-06-23

### Changed
- Renamed the addon to **MyPrayerTimes**. Saved settings (city, method,
  reminders, theme) carry over from earlier versions.

### Fixed
- Version number shown in the settings sidebar was stale on Retail
  (GetAddOnMetadata moved into the C_AddOns namespace); it now reads correctly.

## [1.0.0] - 2026-06-22

First stable release. Builds on the 0.9.0 beta with a minimap button, a full
light/dark theme, and interface polish.

### Added
- Minimap button: left-click toggles the window, right-click opens settings,
  draggable around the minimap, with the PrayerTimes logo.
- Light and dark themes, switchable live from the welcome wizard and the
  Notifications settings tab. Dark is the default.
- "How to find coordinates" guide (Google Maps → latitude/longitude + UTC
  offset) in the custom-location form, in both the wizard and settings.
- Addon version and author shown in the settings sidebar.

### Changed
- Sunrise now reads in its own accent colour instead of being dimmed.
- Countdown sits on a dark footer for readability.
- Spacing, alignment, and header treatment refined across the wizard and
  settings.

### Fixed
- Settings sidebar item text was rendered white (undefined colour roles) and
  is now legible in both themes.

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
