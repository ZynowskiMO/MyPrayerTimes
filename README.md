# PrayerTimes

A World of Warcraft addon that shows the five daily Islamic prayer times (plus
sunrise) for your location, calculated **locally inside the game** — no internet
connection required. Built for European cities, with a clean cream-and-gold
window, reminders, and a first-run setup wizard.

## Features

- **Five daily prayers + sunrise** (Fajr, Sunrise/Shurūq, Dhuhr, Asr, Maghrib,
  Isha) with a live countdown to the next prayer and the current one highlighted.
- **Local calculation** — prayer times are computed in-game from your
  coordinates; nothing is sent over the network.
- **Pick your city** from a built-in list of European cities, or **add a custom
  location** (latitude/longitude + UTC offset, with optional EU daylight-saving).
- **Calculation methods** — all standard methods (Muslim World League, Egyptian,
  Karachi, Umm al-Qura, Dubai, ISNA/North America, Kuwait, Qatar, Singapore,
  Tehran, Turkey, …) and the **Asr school** (Standard / Hanafi).
- **Reminders** — an alert a configurable number of minutes before each prayer,
  an alert exactly at prayer time, and an optional sound.
- **Tidy window** — movable, lockable, and minimisable to just the next prayer;
  a gear icon opens settings.
- **Guided first-run wizard** to set location, calculation method and reminders.

## Installation

**From CurseForge (recommended):** install via the CurseForge app, or download
the zip and extract the `PrayerTimes` folder into:

- Retail: `World of Warcraft/_retail_/Interface/AddOns/`
- Classic: `World of Warcraft/_classic_/Interface/AddOns/`

Restart the game (or `/reload`) and enable **PrayerTimes** in the AddOns list.

## First use

On the first login a welcome wizard opens and walks you through choosing your
city, calculation method, Asr school and reminders. When you finish, the prayer
window appears. You can re-open setup any time with `/pt setup`.

## Commands

| Command | What it does |
|---|---|
| `/pt` or `/pt help` | List all commands |
| `/pt show` / `/pt hide` | Show or hide the window |
| `/pt lock` / `/pt unlock` | Lock or free the window's position |
| `/pt settings` | Open the city / settings window |
| `/pt setup` | Run the welcome wizard again |
| `/pt city <name>` | Select a city by name |
| `/pt test` | Preview a notification |

## Accuracy — please read

Prayer-time math is **ported from [adhan-js](https://github.com/batoulapps/adhan-js)**
(by Batoul Apps) and verified against it to within **±1 minute** across the
supported cities, methods and Asr schools.

Even so, calculated times are an **aid, not an authority**: method choice, local
conventions and high-latitude rules all affect the result. Please confirm against
a trusted local source (your mosque or community calendar), especially at high
latitudes where twilight-based times are approximated.

## Compatibility

Works on **Retail** and **TBC Classic**. Uses only API stable on both clients.

## Credits & licence

- Addon code: © 2026 Muhamed Bašić — **MIT** (see `LICENSE`).
- Prayer-time algorithms: **adhan-js**, © Batoul Apps, MIT.
- Icons: **Lucide** (ISC), with Feather-derived icons under MIT.

Full third-party licence texts are in `THIRD_PARTY_LICENSES.md`.
