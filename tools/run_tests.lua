-- run_tests.lua
-- LuaJIT (Lua 5.1) test runner for the PrayerTimes engine.
-- Run from the repository root:   luajit tools/run_tests.lua
--
-- Reports PASS/FAIL per check and exits non-zero on any failure, so this is
-- the one command that decides whether a checkpoint is green. As the engine
-- grows, later checkpoints add the fixture comparison (Rotterdam vs adhan-js)
-- below; for now it exercises MathUtils.

package.path = "engine/?.lua;" .. package.path

local passed, failed = 0, 0

local function check(name, cond)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("  FAIL: " .. name)
  end
end

-- Approximate equality for floating-point results.
local function near(a, b, eps)
  return math.abs(a - b) <= (eps or 1e-9)
end

-- ---- MathUtils ------------------------------------------------------------
local Math = require("MathUtils")

check("degreesToRadians(180) == pi", near(Math.degreesToRadians(180), math.pi))
check("radiansToDegrees(pi) == 180", near(Math.radiansToDegrees(math.pi), 180))
check("normalizeToScale(370,360) == 10", near(Math.normalizeToScale(370, 360), 10))
check("normalizeToScale(-10,360) == 350", near(Math.normalizeToScale(-10, 360), 350))
check("unwindAngle(720) == 0", near(Math.unwindAngle(720), 0))
check("unwindAngle(-90) == 270", near(Math.unwindAngle(-90), 270))
check("quadrantShiftAngle(90) == 90", near(Math.quadrantShiftAngle(90), 90))
check("quadrantShiftAngle(200) == -160", near(Math.quadrantShiftAngle(200), -160))
check("quadrantShiftAngle(-200) == 160", near(Math.quadrantShiftAngle(-200), 160))
check("quadrantShiftAngle(540) == -180", near(Math.quadrantShiftAngle(540), -180))

-- ---- Astronomical: Julian Day vs Meeus textbook values -------------------
local Astro = require("Astronomical")

-- J2000 epoch: 2000 Jan 1, 12:00 UT  ->  JD 2451545.0 (exact)
check("julianDay J2000 == 2451545.0",
  near(Astro.julianDay(2000, 1, 1, 12), 2451545.0, 1e-6))
-- Meeus, Astronomical Algorithms, Example 7.a: 1957 Oct 4.81 -> 2436116.31
check("julianDay 1957-10-04.81 == 2436116.31",
  near(Astro.julianDay(1957, 10, 4, 0.81 * 24), 2436116.31, 1e-6))
-- Meeus 7.b: 1987 Jan 27.0 -> 2446822.5
check("julianDay 1987-01-27.0 == 2446822.5",
  near(Astro.julianDay(1987, 1, 27, 0), 2446822.5, 1e-6))

-- julianCentury at J2000 is 0 by definition.
check("julianCentury(2451545) == 0", near(Astro.julianCentury(2451545.0), 0, 1e-12))

-- Solar-longitude helpers must run and stay normalized to [0, 360).
local Tj2000 = Astro.julianCentury(2451545.0)
local function inRange360(x) return x >= 0 and x < 360 end
check("meanSolarLongitude in [0,360)", inRange360(Astro.meanSolarLongitude(Tj2000)))
check("meanSolarAnomaly in [0,360)", inRange360(Astro.meanSolarAnomaly(Tj2000)))
check("apparentSolarLongitude in [0,360)",
  inRange360(Astro.apparentSolarLongitude(Tj2000, Astro.meanSolarLongitude(Tj2000))))
check("meanSiderealTime in [0,360)", inRange360(Astro.meanSiderealTime(Tj2000)))

-- ---- SolarCoordinates: declination / RA / sidereal vs adhan-js -----------
-- Reference values produced by adhan-js 4.4.4 (its own SolarCoordinates) for
-- two Julian Days: 2448908.5 = Meeus Astronomical Algorithms Example 25.b
-- (1992 Oct 13.0, apparent declination ~ -7.785 deg) and 2461212.5 =
-- 2026-06-21 00:00 UT (near summer solstice, declination ~ +23.44 deg).
local SolarCoordinates = require("SolarCoordinates")

local meeus = SolarCoordinates.new(2448908.5)
check("Meeus 25.b declination matches adhan-js",
  near(meeus.declination, -7.7850685152648795, 1e-9))
check("Meeus 25.b right ascension matches adhan-js",
  near(meeus.rightAscension, 198.3808221425188, 1e-9))
check("Meeus 25.b apparent sidereal time matches adhan-js",
  near(meeus.apparentSiderealTime, 21.80542426334863, 1e-9))
-- Independent textbook cross-check: Meeus gives delta ~ -7.785 deg.
check("Meeus 25.b declination ~ -7.785 (textbook)",
  near(meeus.declination, -7.785, 0.01))

local sol = SolarCoordinates.new(2461212.5)
check("solstice declination matches adhan-js",
  near(sol.declination, 23.437715792610817, 1e-9))
-- Summer-solstice declination must sit just under the obliquity (~23.44 deg).
check("solstice declination ~ +23.44 (near max tilt)",
  near(sol.declination, 23.44, 0.01))

-- ---- SolarTime: transit / sunrise / sunset for Rotterdam -----------------
-- Reference fractional-hour (UTC) values from adhan-js 4.4.4 SolarTime for
-- Rotterdam (51.9244, 4.4777). The Lua port must match these closely; small
-- floating differences are fine, the prayer-time tolerance is +/-1 minute.
local SolarTime = require("SolarTime")
local ROTTERDAM = { latitude = 51.9244, longitude = 4.4777 }

local function roundMinUTC(hours) return math.floor(hours * 60 + 0.5) end

local stWinter = SolarTime.new(2026, 12, 21, ROTTERDAM)
check("winter transit matches adhan-js", near(stWinter.transit, 11.6691540885, 1e-7))
check("winter sunrise matches adhan-js", near(stWinter.sunrise, 7.7909050794, 1e-7))
check("winter sunset matches adhan-js", near(stWinter.sunset, 15.5472916270, 1e-7))

local stSummer = SolarTime.new(2026, 6, 21, ROTTERDAM)
check("summer transit matches adhan-js", near(stSummer.transit, 11.7319190136, 1e-7))
check("summer sunrise matches adhan-js", near(stSummer.sunrise, 3.3715712451, 1e-7))
check("summer sunset matches adhan-js", near(stSummer.sunset, 20.0921808055, 1e-7))

-- Sunrise and sunset already equal the locked fixtures (minute-of-day UTC).
-- Sunrise -> fixture.sunrise; sunset -> fixture.maghrib (Maghrib == sunset).
-- Dhuhr is NOT checked here: MWL adds methodAdjustments.dhuhr = +1 min,
-- applied during prayer-time assembly in a later checkpoint.
local fx = {}
for _, r in ipairs(dofile("fixtures/rotterdam_mwl_standard.lua").dates) do fx[r.date] = r end
check("winter sunrise == fixture (467)", roundMinUTC(stWinter.sunrise) == fx["2026-12-21"].sunrise)
check("winter sunset == fixture maghrib (933)", roundMinUTC(stWinter.sunset) == fx["2026-12-21"].maghrib)
check("summer sunrise == fixture (202)", roundMinUTC(stSummer.sunrise) == fx["2026-06-21"].sunrise)
check("summer sunset == fixture maghrib (1206)", roundMinUTC(stSummer.sunset) == fx["2026-06-21"].maghrib)

-- ---- Fajr / Asr / Isha raw times (MWL 18/17, Shafi Asr) ------------------
-- MWL fajrAngle = 18, ishaAngle = 17. Asr (Standard) uses shadow length 1.
-- Raw fractional-hour (UTC) references from adhan-js 4.4.4 SolarTime methods.
local Madhab = require("Madhab")
local function isNaN(x) return x ~= x end

-- Winter: all three angles are reachable at this latitude.
local fajrW = stWinter:hourAngle(-1 * 18, false)
local ishaW = stWinter:hourAngle(-1 * 17, true)
local asrW  = stWinter:afternoon(Madhab.shadowLength(Madhab.Shafi))
check("winter Fajr raw matches adhan-js", near(fajrW, 5.694705957998483, 1e-7))
check("winter Isha raw matches adhan-js", near(ishaW, 17.531409514807383, 1e-7))
check("winter Asr raw matches adhan-js", near(asrW, 13.2858551963, 1e-7))
check("winter Fajr rounds to fixture (342)", roundMinUTC(fajrW) == fx["2026-12-21"].fajr)
check("winter Asr rounds to fixture (797)", roundMinUTC(asrW) == fx["2026-12-21"].asr)
check("winter Isha rounds to fixture (1052)", roundMinUTC(ishaW) == fx["2026-12-21"].isha)

-- Summer: Fajr/Isha angles are NEVER reached at 51.9N -> NaN (the high-lat
-- case the default rule resolves to the midnight clamp during assembly). Asr
-- is still well-defined.
local fajrS = stSummer:hourAngle(-1 * 18, false)
local ishaS = stSummer:hourAngle(-1 * 17, true)
local asrS  = stSummer:afternoon(Madhab.shadowLength(Madhab.Shafi))
check("summer Fajr raw is NaN (angle unreachable)", isNaN(fajrS))
check("summer Isha raw is NaN (angle unreachable)", isNaN(ishaS))
check("summer Asr raw matches adhan-js", near(asrS, 16.1279039575, 1e-7))
check("summer Asr rounds to fixture (968)", roundMinUTC(asrS) == fx["2026-06-21"].asr)

-- ---- PHASE 1 EXIT CRITERION: full engine vs adhan-js fixtures ------------
-- Build the assembled PrayerTimes for Rotterdam (MWL, Standard Asr) on every
-- locked test date and compare all six times to the adhan-js fixtures within
-- +/-1 minute. Prints a PASS/FAIL table; any cell over tolerance fails CI.
local PrayerTimes = require("PrayerTimes")
local CalculationMethod = require("CalculationMethod")

local PRAYERS = { "fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha" }
local TOLERANCE = 1 -- minutes

-- Smallest difference between two minute-of-day values, accounting for wrap.
local function minuteDiff(a, b)
  local d = math.abs(a - b)
  return math.min(d, 1440 - d)
end

print("\n=== Phase 1 exit criterion: Rotterdam MWL / Standard Asr ===")
print("    (engine vs adhan-js 4.4.4, tolerance +/-1 min, minute-of-day UTC)\n")
local header = string.format("%-12s", "date")
for _, p in ipairs(PRAYERS) do header = header .. string.format("%-10s", p) end
print(header)

local fixtureRows = dofile("fixtures/rotterdam_mwl_standard.lua").dates
for _, row in ipairs(fixtureRows) do
  local y, mo, d = row.date:match("(%d+)-(%d+)-(%d+)")
  y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
  local pt = PrayerTimes.new(y, mo, d, ROTTERDAM, CalculationMethod.MuslimWorldLeague())
  local cells = string.format("%-12s", row.date)
  for _, p in ipairs(PRAYERS) do
    local diff = minuteDiff(pt[p], row[p])
    local ok = diff <= TOLERANCE
    check(string.format("%s %s within +/-1 min", row.date, p), ok)
    cells = cells .. string.format("%-10s", ok and ("ok " .. diff) or ("FAIL " .. diff))
  end
  print(cells)
end

-- ---- 2a-1: HighLatitudeRule.recommended() + Calculator default ----------
local HighLatitudeRule = require("HighLatitudeRule")
local Calculator = require("Calculator")

-- Rule selection: strictly > 48 -> SeventhOfTheNight, else MiddleOfTheNight.
check("Cairo (30.0) -> MiddleOfTheNight",
  HighLatitudeRule.recommended({ latitude = 30.0444, longitude = 31.2357 })
    == HighLatitudeRule.MiddleOfTheNight)
check("Rotterdam (51.9) -> SeventhOfTheNight",
  HighLatitudeRule.recommended({ latitude = 51.9244, longitude = 4.4777 })
    == HighLatitudeRule.SeventhOfTheNight)
check("Stockholm (59.3) -> SeventhOfTheNight",
  HighLatitudeRule.recommended({ latitude = 59.3293, longitude = 18.0686 })
    == HighLatitudeRule.SeventhOfTheNight)
check("boundary 48.0 -> MiddleOfTheNight (not > 48)",
  HighLatitudeRule.recommended({ latitude = 48.0, longitude = 0 })
    == HighLatitudeRule.MiddleOfTheNight)
check("boundary 48.0001 -> SeventhOfTheNight",
  HighLatitudeRule.recommended({ latitude = 48.0001, longitude = 0 })
    == HighLatitudeRule.SeventhOfTheNight)

-- Behavioural proof (fixture-free): the engine's bare default clamps summer
-- Rotterdam Fajr == Isha (midnight), but the Calculator default (recommended
-- -> SeventhOfTheNight) de-clamps them. adhan-js numeric match comes in 2a-3.
local clamped = PrayerTimes.new(2026, 6, 21, ROTTERDAM, CalculationMethod.MuslimWorldLeague())
check("raw default still clamps summer (Fajr == Isha)", clamped.fajr == clamped.isha)
local declamped = Calculator.timesForLocation(2026, 6, 21, ROTTERDAM)
check("Calculator default de-clamps summer (Fajr ~= Isha)", declamped.fajr ~= declamped.isha)

-- Override must be honoured (rule stays user-changeable for Phase 3).
local forced = Calculator.timesForLocation(2026, 6, 21, ROTTERDAM,
  { highLatitudeRule = HighLatitudeRule.MiddleOfTheNight })
check("explicit MiddleOfTheNight override re-clamps", forced.fajr == forced.isha)

-- ---- 2a-3 EXIT CRITERION: recommended rule vs adhan-js, no clamp ---------
-- Verify the engine via Calculator.timesForLocation (recommended rule) matches
-- the adhan-js recommended-rule fixtures for Rotterdam + Stockholm within
-- +/-1 min, and assert summer Fajr/Isha are de-clamped (not the midnight
-- midpoint). Summer dates here are the ones that previously clamped.
local SUMMER_DATES = { ["2026-06-21"] = true, ["2026-07-15"] = true }

print("\n=== Phase 2a exit criterion: HighLatitudeRule.recommended() ===")
print("    (engine vs adhan-js 4.4.4, tolerance +/-1 min, minute-of-day UTC)\n")

for _, city in ipairs(dofile("fixtures/highlat_recommended.lua").cities) do
  print(string.format("%s (%.1fN)  rule=%s", city.name, city.lat, city.rule))
  local hdr = string.format("  %-12s", "date")
  for _, p in ipairs(PRAYERS) do hdr = hdr .. string.format("%-10s", p) end
  print(hdr)
  local coords = { latitude = city.lat, longitude = city.lon }
  for _, row in ipairs(city.dates) do
    local y, mo, d = row.date:match("(%d+)-(%d+)-(%d+)")
    local pt = Calculator.timesForLocation(tonumber(y), tonumber(mo), tonumber(d), coords)
    local cells = string.format("  %-12s", row.date)
    for _, p in ipairs(PRAYERS) do
      local diff = minuteDiff(pt[p], row[p])
      local ok = diff <= TOLERANCE
      check(string.format("%s %s %s within +/-1 min", city.name, row.date, p), ok)
      cells = cells .. string.format("%-10s", ok and ("ok " .. diff) or ("FAIL " .. diff))
    end
    print(cells)
    -- No-clamp: on summer dates Fajr and Isha must differ (the clamp made them
    -- equal at the midnight midpoint).
    if SUMMER_DATES[row.date] then
      check(string.format("%s %s summer NOT clamped (Fajr ~= Isha)", city.name, row.date),
        pt.fajr ~= pt.isha)
    end
  end
  print("")
end

-- ---- 2b-2: Timezone offset / DST transition boundaries -------------------
local Timezone = require("Timezone")

-- 2026 EU transitions: last Sunday of March = 29th, of October = 25th.
check("2026-03-29 is Sunday (weekday 0 via Timezone.RULES path)",
  Timezone.RULES.EU(2026, 3, 29) == 60) -- only true if 29th is the last Sunday
check("EU rule: 2026-03-28 winter (0)", Timezone.RULES.EU(2026, 3, 28) == 0)
check("EU rule: 2026-03-29 spring-forward -> summer (60)", Timezone.RULES.EU(2026, 3, 29) == 60)
check("EU rule: 2026-10-24 still summer (60)", Timezone.RULES.EU(2026, 10, 24) == 60)
check("EU rule: 2026-10-25 fall-back -> winter (0)", Timezone.RULES.EU(2026, 10, 25) == 0)
check("EU rule: midsummer 2026-07-01 (60)", Timezone.RULES.EU(2026, 7, 1) == 60)
check("EU rule: midwinter 2026-01-15 (0)", Timezone.RULES.EU(2026, 1, 15) == 0)

-- "none" zone (e.g. Istanbul +3) never changes across the same dates.
local istanbul = { baseUtcOffset = 180, dstRule = "none" }
check("none: Istanbul +180 on 2026-03-28", Timezone.offsetMinutes(istanbul, 2026, 3, 28) == 180)
check("none: Istanbul +180 on 2026-03-29", Timezone.offsetMinutes(istanbul, 2026, 3, 29) == 180)
check("none: Istanbul +180 on 2026-07-01", Timezone.offsetMinutes(istanbul, 2026, 7, 1) == 180)
check("none: Istanbul +180 on 2026-10-25", Timezone.offsetMinutes(istanbul, 2026, 10, 25) == 180)

-- EU city (e.g. Amsterdam base +60) gains an hour in summer.
local amsterdam = { baseUtcOffset = 60, dstRule = "EU" }
check("EU: Amsterdam +60 in winter", Timezone.offsetMinutes(amsterdam, 2026, 1, 15) == 60)
check("EU: Amsterdam +120 in summer", Timezone.offsetMinutes(amsterdam, 2026, 7, 1) == 120)
check("EU: Amsterdam +120 on spring-forward day", Timezone.offsetMinutes(amsterdam, 2026, 3, 29) == 120)
check("EU: Amsterdam +60 on fall-back day", Timezone.offsetMinutes(amsterdam, 2026, 10, 25) == 60)

-- Conversion + wrap: 23:30 UTC + 1h -> 00:30 next local day.
check("toLocal wraps past midnight", Timezone.toLocalMinuteOfDay(23 * 60 + 30, 60) == 30)
check("toLocal formats HH:MM", Timezone.formatHHMM(Timezone.toLocalMinuteOfDay(11 * 60, 120)) == "13:00")

-- ---- (fixture comparison wired in a later checkpoint) ---------------------

-- ---- Summary --------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
