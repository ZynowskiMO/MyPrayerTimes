-- run_tests.lua
-- LuaJIT (Lua 5.1) test runner for the PrayerTimes engine.
-- Run from the repository root:   luajit tools/run_tests.lua
--
-- Reports PASS/FAIL per check and exits non-zero on any failure, so this is
-- the one command that decides whether a checkpoint is green. As the engine
-- grows, later checkpoints add the fixture comparison (Rotterdam vs adhan-js)
-- below; for now it exercises MathUtils.

-- engine/ for modules; root ?.lua so dotted tokens like "data.cities" resolve
-- to data/cities.lua without colliding with engine/Cities.lua (case-insensitive FS).
package.path = "engine/?.lua;ui/?.lua;?.lua;" .. package.path

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

-- ---- 2b-3: city list + selection + selected-city -> local times ----------
local Cities = require("Cities")

check("city list has 65 entries", #Cities.all() == 65)

-- Every city has the required fields and a known dstRule.
local fieldsOk = true
for _, c in ipairs(Cities.all()) do
  if type(c.name) ~= "string" or type(c.country) ~= "string"
      or type(c.latitude) ~= "number" or type(c.longitude) ~= "number"
      or type(c.baseUtcOffset) ~= "number"
      or not (c.dstRule == "EU" or c.dstRule == "none") then
    fieldsOk = false
  end
end
check("every city has valid fields + known dstRule", fieldsOk)

-- Lookup (case-insensitive) and the signed-off fixed-offset cities.
check("findByName Rotterdam", Cities.findByName("Rotterdam") ~= nil)
check("findByName case-insensitive", Cities.findByName("rotterdam") ~= nil)
for _, name in ipairs({ "Moscow", "Saint Petersburg", "Istanbul", "Ankara" }) do
  local c = Cities.findByName(name)
  check(name .. " is +180 / none", c and c.baseUtcOffset == 180 and c.dstRule == "none")
end

-- Search by substring over name and country.
check("search 'ber' finds Berlin",
  (function() for _, c in ipairs(Cities.search("ber")) do if c.name == "Berlin" then return true end end end)())
check("search 'germany' finds multiple", #Cities.search("germany") >= 4)
check("unknown city -> nil times", Cities.times("Atlantis", 2026, 6, 21) == nil)

-- Selected-city -> local times: end-to-end through engine + Timezone.
-- Rotterdam winter (EU, +60): Fajr UTC 342 -> 06:42 local.
local rWinter = Cities.times("Rotterdam", 2026, 12, 21)
check("Rotterdam winter Fajr local 06:42", rWinter.prayers.fajr.hhmm == "06:42")
check("Rotterdam winter offset +60", rWinter.offsetMinutes == 60)
-- Rotterdam summer (EU, +120) de-clamped: Isha 23:08 local.
local rSummer = Cities.times("Rotterdam", 2026, 6, 21)
check("Rotterdam summer offset +120", rSummer.offsetMinutes == 120)
check("Rotterdam summer Isha local 23:08", rSummer.prayers.isha.hhmm == "23:08")
-- Istanbul ("none") stays +180 in summer.
check("Istanbul summer offset +180", Cities.times("Istanbul", 2026, 7, 1).offsetMinutes == 180)

-- Eastern Russia fixed offsets (new zones, all "none" -> no summer change).
for _, t in ipairs({ { "Kazan", 180 }, { "Ufa", 300 }, { "Yekaterinburg", 300 }, { "Novosibirsk", 420 } }) do
  local c = Cities.findByName(t[1])
  check(t[1] .. " is +" .. t[2] .. " / none", c and c.baseUtcOffset == t[2] and c.dstRule == "none")
  check(t[1] .. " offset unchanged in summer",
    Cities.times(t[1], 2026, 7, 1).offsetMinutes == t[2])
end

-- ---- 2b-4 EXIT CRITERION: engine + Timezone vs ICU/IANA local times ------
-- For a sample spanning every offset zone (+0..+7) and both DST observers and
-- non-observers, verify Cities.times (engine UTC + our Timezone) reproduces
-- the ICU/IANA reference LOCAL times within +/-1 min, on dates straddling both
-- 2026 transitions plus solstice controls. Also cross-check that each sampled
-- city's coordinates in data/cities.lua match the fixture (catches typos).
print("\n=== Phase 2b exit criterion: engine + Timezone vs ICU/IANA ===")
print("    (local minute-of-day, tolerance +/-1 min; * = DST transition day)\n")
local TRANSITION = { ["2026-03-29"] = true, ["2026-10-25"] = true }

for _, s in ipairs(dofile("fixtures/tz_local_reference.lua").samples) do
  local city = Cities.findByName(s.name)
  check(s.name .. " present in city list", city ~= nil)
  -- Coordinate typo guard: data-file coords must equal the verified fixture.
  check(s.name .. " coords match data/cities.lua",
    city and city.latitude == s.lat and city.longitude == s.lon)
  local off = city and city.baseUtcOffset or 0
  print(string.format("%s  (UTC%+d %s)", s.name, off / 60, city and city.dstRule or "?"))
  local hdr = string.format("  %-13s", "date")
  for _, p in ipairs(PRAYERS) do hdr = hdr .. string.format("%-10s", p) end
  print(hdr)
  for _, row in ipairs(s.dates) do
    local y, mo, d = row.date:match("(%d+)-(%d+)-(%d+)")
    local res = Cities.times(s.name, tonumber(y), tonumber(mo), tonumber(d))
    local label = row.date .. (TRANSITION[row.date] and " *" or "")
    local cells = string.format("  %-13s", label)
    for _, p in ipairs(PRAYERS) do
      local diff = minuteDiff(res.prayers[p].localMin, row[p])
      local ok = diff <= TOLERANCE
      check(string.format("%s %s %s within +/-1 min (local)", s.name, row.date, p), ok)
      cells = cells .. string.format("%-10s", ok and ("ok " .. diff) or ("FAIL " .. diff))
    end
    print(cells)
  end
  print("")
end

-- ---- 2c-1: WoW API mock sanity (tooling for the UI checkpoints) ----------
-- The mock stubs only the WoW functions our UI calls; verify it behaves so
-- ui/Window.lua (2c-2+) can be loaded and exercised under the runner.
local WowMock = dofile("tools/wow_mock.lua")
WowMock.install()

local mf = CreateFrame("Frame", "TestFrame", UIParent)
mf:Hide(); check("mock frame Hide -> not shown", mf:IsShown() == false)
mf:Show(); check("mock frame Show -> shown", mf:IsShown() == true)
mf:SetMovable(true); check("mock frame movable flag", mf:IsMovable() == true)
mf:EnableMouse(true); check("mock frame mouse flag", mf:IsMouseEnabled() == true)

local mfs = mf:CreateFontString()
mfs:SetText("12:34"); check("mock fontstring SetText/GetText", mfs:GetText() == "12:34")

local ticks = 0
local ticker = C_Timer.NewTicker(1, function() ticks = ticks + 1 end)
ticker.fn(); check("mock ticker stores callback", ticks == 1)
ticker:Cancel(); check("mock ticker cancellable", ticker._cancelled == true)

WowMock.setNow(1750000000)
check("mock clock injectable (GetServerTime)", GetServerTime() == 1750000000)
check("mock clock injectable (time)", time() == 1750000000)

-- ---- 2c-2: Schedule (pure) -----------------------------------------------
local Schedule = require("Schedule")
-- Rotterdam winter local minute-of-day (UTC fixture + 60).
local RW = { fajr = 402, sunrise = 527, dhuhr = 761, asr = 857, maghrib = 993, isha = 1112 }
local sBefore = Schedule.compute(RW, 0)
check("Schedule 00:00 -> next Fajr, until 402", sBefore.nextKey == "fajr" and sBefore.untilMinutes == 402)
local sGap = Schedule.compute(RW, 510)  -- 08:30, between Fajr and Sunrise
check("Schedule 08:30 -> next Sunrise", sGap.nextKey == "sunrise" and sGap.untilMinutes == 17)
local sMid = Schedule.compute(RW, 800)  -- 13:20, between Dhuhr and Asr
check("Schedule 13:20 -> next Asr, until 57", sMid.nextKey == "asr" and sMid.untilMinutes == 57)
local sWrap = Schedule.compute(RW, 1200) -- 20:00, after Isha
check("Schedule after Isha -> wrap to Fajr", sWrap.nextKey == "fajr"
  and sWrap.untilMinutes == (1440 - 1200) + 402)
local nextCount = 0
for _, r in ipairs(sMid.order) do if r.isNext then nextCount = nextCount + 1 end end
check("Schedule flags exactly one isNext", nextCount == 1)
check("Schedule order has six entries", #sMid.order == 6)

-- ---- 2c-2: Clock helper vs os.date (UTC authoritative) -------------------
local Clock = require("Clock")
for _, ep in ipairs({ 0, 1640995200, 1750000000, 1766318400 }) do
  local y, m, d = Clock.civilFromDays(math.floor(ep / 86400))
  local u = os.date("!*t", ep)
  check("civilFromDays matches os.date @" .. ep, y == u.year and m == u.month and d == u.day)
end
-- Istanbul (+180 "none"): city-local = UTC+3, year-round.
local ist = Cities.findByName("Istanbul")
local istNow = Clock.cityNow(ist, 1766318400)
local uShift = os.date("!*t", 1766318400 + 180 * 60)
check("cityNow Istanbul date == UTC+3 date",
  istNow.year == uShift.year and istNow.month == uShift.month and istNow.day == uShift.day)
check("cityNow Istanbul minute == UTC+3 minute",
  istNow.minuteOfDay == uShift.hour * 60 + uShift.min)

-- ---- 2c-2: static Window builds + renders + highlights (under the mock) --
local Window = require("Window")
WowMock.setNow(1766318400)
local win = Window.create()
check("Window is shown", win:IsShown() == true)
check("Window create is idempotent", Window.create() == win)

-- Window renders the same times the engine produces for the city's "today".
local rCity = Cities.findByName("Rotterdam")
local rNow = Clock.cityNow(rCity, 1766318400)
local rRes = Cities.times("Rotterdam", rNow.year, rNow.month, rNow.day)
check("Window Fajr text matches engine", win.rows.fajr.time:GetText() == rRes.prayers.fajr.hhmm)
check("Window Isha text matches engine", win.rows.isha.time:GetText() == rRes.prayers.isha.hhmm)
local rTimes = {}
for _, k in ipairs(Schedule.ORDER) do rTimes[k] = rRes.prayers[k].localMin end
check("Window highlights the schedule's next prayer",
  Window.lastSchedule.nextKey == Schedule.compute(rTimes, rNow.minuteOfDay).nextKey)

-- ---- 2c-3: movable / lockable / position persistence --------------------
-- Drive the persistence + lock logic with a plain table as the SavedVariables
-- DB (the runner can't test real reload persistence -- that's verified
-- in-game -- but the save/restore/lock logic is fully testable).
local db = {}
Window.init(db)
check("init defaults locked = false", db.locked == false)

-- savePosition reads the frame's current anchor into the DB.
win:ClearAllPoints()
win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 123, -45)
Window.savePosition()
check("savePosition captures point", db.position.point == "TOPLEFT")
check("savePosition captures offsets", db.position.x == 123 and db.position.y == -45)

-- restorePosition applies a stored anchor back onto the frame.
db.position = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -10, y = 20 }
Window.restorePosition()
local rp, _, rrel, rx, ry = win:GetPoint(1)
check("restorePosition applies stored anchor",
  rp == "BOTTOMRIGHT" and rrel == "BOTTOMRIGHT" and rx == -10 and ry == 20)

-- Lock toggles mouse interactivity and the DB flag.
Window.setLocked(true)
check("setLocked(true) sets flag", db.locked == true)
check("locked window disables mouse", win:IsMouseEnabled() == false)
Window.setLocked(false)
check("unlocked window enables mouse", win:IsMouseEnabled() == true)
Window.toggleLock()
check("toggleLock flips to locked", db.locked == true)

-- Drag is blocked while locked, allowed while unlocked, and saves on stop.
win._moving = false
Window.setLocked(true)
win:GetScript("OnDragStart")(win)
check("locked frame does not start moving", win._moving == false)
Window.setLocked(false)
win:GetScript("OnDragStart")(win)
check("unlocked frame starts moving", win._moving == true)
win:GetScript("OnDragStop")(win)
check("drag stop ends moving", win._moving == false)

-- ---- 2c-4: countdown logic + live ticker ---------------------------------
-- Pure countdown (Schedule), driven by the injectable clock.
local sCd = Schedule.compute(RW, 800) -- next Asr (857), untilMinutes 57
check("untilSeconds subtracts seconds-into-minute",
  Schedule.untilSeconds(sCd, 800 * 60 + 30) == 57 * 60 - 30)
check("formatCountdown mm:ss", Schedule.formatCountdown(57 * 60 - 30) == "56:30")
check("formatCountdown h:mm:ss", Schedule.formatCountdown(3661) == "1:01:01")
check("formatCountdown clamps negative", Schedule.formatCountdown(-5) == "0:00")

-- Clock now reports second-of-day too (vs os.date UTC for Istanbul +3).
local istNow2 = Clock.cityNow(ist, 1766318400)
local uS = os.date("!*t", 1766318400 + 180 * 60)
check("cityNow second-of-day matches UTC+3",
  istNow2.secondOfDay == uS.hour * 3600 + uS.min * 60 + uS.sec)

-- Live ticker: a NewTicker was registered, and a tick updates the countdown.
check("Window registered a 1s ticker", Window.ticker ~= nil)

local PROPER = { fajr = "Fajr", sunrise = "Sunrise", dhuhr = "Dhuhr",
  asr = "Asr", maghrib = "Maghrib", isha = "Isha" }

local E1 = 1766318400
WowMock.setNow(E1)
Window.refresh()
local sched1 = Window.lastSchedule
local now1 = Clock.cityNow(Cities.findByName("Rotterdam"), E1)
local untilSec1 = Schedule.untilSeconds(sched1, now1.secondOfDay)
check("countdown text shows next prayer + time",
  Window.frame.countdown:GetText()
    == PROPER[sched1.nextKey] .. " in " .. Schedule.formatCountdown(untilSec1))

-- Advance the clock just past the next prayer -> highlight must move on.
WowMock.setNow(E1 + untilSec1 + 60)
Window.tick()
check("highlight advances after the prayer passes",
  Window.lastSchedule.nextKey ~= sched1.nextKey)

-- ---- 2d-1: Notifier pure trigger logic -----------------------------------
local Notifier = require("Notifier")
-- Five-prayer local times (Rotterdam winter); sunrise present but ignored.
local NT = { fajr = 402, sunrise = 527, dhuhr = 761, asr = 857, maghrib = 993, isha = 1112 }
local DEFAULT_NOTIFY = { beforeMinutes = 10, atTime = true }
local DAY = "2026-12-21"

-- Continuous day: every prayer fires before+at exactly once; sunrise never.
do
  local fired, count = {}, {}
  local sawSunrise = false
  for nowMin = 0, 1439 do
    for _, ev in ipairs(Notifier.check(NT, nowMin, DEFAULT_NOTIFY, DAY, fired)) do
      local k = ev.prayer .. ":" .. ev.type
      count[k] = (count[k] or 0) + 1
      if ev.prayer == "sunrise" then sawSunrise = true end
    end
  end
  local total = 0
  for _, c in pairs(count) do total = total + c end
  check("continuous day fires 10 alerts (5 before + 5 at)", total == 10)
  check("each alert fires exactly once", count["maghrib:before"] == 1 and count["maghrib:at"] == 1)
  check("Sunrise never notifies", sawSunrise == false)
end

-- Mid-window login: 5 min before Maghrib (993) fires 'before' once, in 5 min.
do
  local fired = {}
  local ev = Notifier.check(NT, 988, DEFAULT_NOTIFY, DAY, fired)
  check("mid-window login fires before once", #ev == 1 and ev[1].prayer == "maghrib"
    and ev[1].type == "before" and ev[1].minutesUntil == 5)
  check("same window, next tick does not re-fire", #Notifier.check(NT, 989, DEFAULT_NOTIFY, DAY, fired) == 0)
end

-- Login exactly at the prayer minute: 'at' fires, 'before' is skipped (closed).
do
  local fired = {}
  local ev = Notifier.check(NT, 993, DEFAULT_NOTIFY, DAY, fired)
  check("at-minute login fires only 'at'", #ev == 1 and ev[1].type == "at")
end

-- Login a minute late: neither fires (stale).
do
  local fired = {}
  check("late login fires nothing", #Notifier.check(NT, 994, DEFAULT_NOTIFY, DAY, fired) == 0)
end

-- Persisted dedupe across a simulated /reload: keep the same `fired` table.
do
  local fired = {}
  Notifier.check(NT, 985, DEFAULT_NOTIFY, DAY, fired)            -- before fires (8 min out)
  -- "reload" keeps persisted fired:
  check("reload mid-window does not re-fire before",
    #Notifier.check(NT, 990, DEFAULT_NOTIFY, DAY, fired) == 0)
  local atEv = Notifier.check(NT, 993, DEFAULT_NOTIFY, DAY, fired)
  check("at still fires once after persisted before", #atEv == 1 and atEv[1].type == "at")
  check("reload at prayer minute does not re-fire at",
    #Notifier.check(NT, 993, DEFAULT_NOTIFY, DAY, fired) == 0)
end

-- Settings: before-only, at-only, both-off.
do
  local f1 = {}; local e1 = Notifier.check(NT, 402, { beforeMinutes = 0, atTime = true }, DAY, f1)
  check("beforeMinutes=0 disables before", #e1 == 1 and e1[1].type == "at")
  local f2 = {}; local e2 = Notifier.check(NT, 392, { beforeMinutes = 10, atTime = false }, DAY, f2)
  check("atTime=false still allows before", #e2 == 1 and e2[1].type == "before")
  local f3 = {}
  local any = false
  for nowMin = 0, 1439 do
    if #Notifier.check(NT, nowMin, { beforeMinutes = 0, atTime = false }, DAY, f3) > 0 then any = true end
  end
  check("both off -> no alerts all day", any == false)
end

-- pruneFired drops other days, keeps today.
do
  local fired = { ["2026-12-20:fajr:at"] = true, ["2026-12-21:fajr:at"] = true }
  Notifier.pruneFired(fired, "2026-12-21")
  check("pruneFired removes stale day", fired["2026-12-20:fajr:at"] == nil)
  check("pruneFired keeps current day", fired["2026-12-21:fajr:at"] == true)
end

-- Full-day simulation printout (Rotterdam winter, before=10 + at-time).
print("\n=== 2d-1 notification simulation: Rotterdam winter, before=10m + at ===")
do
  local PRO = { fajr = "Fajr", dhuhr = "Dhuhr", asr = "Asr", maghrib = "Maghrib", isha = "Isha" }
  local fired = {}
  for nowMin = 0, 1439 do
    for _, ev in ipairs(Notifier.check(NT, nowMin, DEFAULT_NOTIFY, DAY, fired)) do
      local hhmm = string.format("%02d:%02d", math.floor(nowMin / 60), nowMin % 60)
      if ev.type == "before" then
        print(string.format("  %s  %-8s (in %d min)", hhmm, PRO[ev.prayer], ev.minutesUntil))
      else
        print(string.format("  %s  %-8s (now)", hhmm, PRO[ev.prayer]))
      end
    end
  end
end

-- ---- 2d-2: Alerts presentation + Window wiring (under the mock) ----------
local Alerts = require("Alerts")

-- Pure message text.
check("messageFor before", Alerts.messageFor({ prayer = "maghrib", type = "before", minutesUntil = 10 })
  == "Maghrib in 10 min")
check("messageFor at", Alerts.messageFor({ prayer = "fajr", type = "at" }) == "Fajr - it's time")

-- fire() plays a sound and shows a center-screen notice.
WowMock.resetAlerts()
Alerts.fire({ prayer = "isha", type = "at" }, { sound = true })
check("fire plays the alert file on Master",
  WowMock.lastSound == 561542 and WowMock.lastSoundChannel == "Master")
check("fire shows raid notice text", WowMock.lastRaidNotice == "Isha - it's time")

-- sound = false suppresses the sound but still shows the notice.
WowMock.resetAlerts()
Alerts.fire({ prayer = "isha", type = "at" }, { sound = false })
check("muted: no sound", WowMock.lastSound == nil)
check("muted: still shows notice", WowMock.lastRaidNotice ~= nil)

-- Window wiring: checkNotifications fires due alerts once, deduped.
do
  local ndb = {}
  Window.init(ndb)
  Window.localTimes = { fajr = 402, sunrise = 527, dhuhr = 761, asr = 857, maghrib = 993, isha = 1112 }
  Window.dayKey = "2026-12-21"

  WowMock.resetAlerts()
  local atNow = { minuteOfDay = 993, secondOfDay = 993 * 60 } -- Maghrib at-time
  local evs = Window.checkNotifications(atNow)
  check("Window fires Maghrib at-time", #evs == 1 and evs[1].prayer == "maghrib" and evs[1].type == "at")
  check("Window center-screen shows Maghrib", WowMock.lastRaidNotice == "Maghrib - it's time")
  local countAfter = WowMock.raidNoticeCount
  Window.checkNotifications(atNow) -- same minute again (e.g. next tick / reload)
  check("Window does not re-fire same minute", WowMock.raidNoticeCount == countAfter)
end

-- /pt test path fires a sample alert.
WowMock.resetAlerts()
Window.testNotification()
check("testNotification fires a sample", WowMock.lastRaidNotice ~= nil)

-- ---- 2d-3: selection model + country grouping + manual validation -------
local Selection = require("Selection")

-- Country grouping for the picker.
do
  local groups = Cities.byCountry()
  local total, germany, sorted = 0, nil, true
  for i, g in ipairs(groups) do
    total = total + #g.cities
    if g.country == "Germany" then germany = g end
    if i > 1 and groups[i - 1].country > g.country then sorted = false end
  end
  check("byCountry covers all 65 cities", total == 65)
  check("byCountry countries sorted A-Z", sorted == true)
  check("Germany grouped has 6, name-sorted", germany and #germany.cities == 6
    and germany.cities[1].name <= germany.cities[2].name)
end

-- Coordinate validation.
check("valid coords accepted", (Selection.validateCoords(51.9, 4.5)) == true)
check("latitude out of range rejected", (Selection.validateCoords(120, 0)) == false)
check("longitude out of range rejected", (Selection.validateCoords(0, 200)) == false)
check("non-number coords rejected", (Selection.validateCoords("x", 0)) == false)

-- Bundled-city selection persists and resolves.
do
  local db = {}
  Selection.setCity(db, "Sarajevo")
  check("setCity persists descriptor", db.selectedCity.kind == "city" and db.selectedCity.name == "Sarajevo")
  check("resolve bundled city", Selection.resolve(db).name == "Sarajevo")
end

-- Default + unknown fall back to Rotterdam (temporary, until first-run picker).
check("empty selection resolves to default", Selection.resolve({}).name == "Rotterdam")
check("unknown saved city falls back", Selection.resolve({ selectedCity = { kind = "city", name = "Atlantis" } }).name == "Rotterdam")

-- Manual entry, fixed offset + rule -> flows through the pure pipeline.
do
  local db = {}
  local ok = Selection.setManual(db, 48.5, 9.0, { tz = "fixed", baseUtcOffset = 90, dstRule = "none" })
  check("setManual(fixed) accepted", ok == true)
  local city = Selection.resolve(db)
  check("manual fixed city offset/rule", city.baseUtcOffset == 90 and city.dstRule == "none")
  check("manual fixed flows through Cities.times",
    Cities.times(city, 2026, 1, 15).offsetMinutes == 90)
end

-- Manual entry, machine tz -> uses the injected live offset (ADR-0003 addendum).
do
  local db = {}
  Selection.setManual(db, 50.0, 10.0, { tz = "machine" })
  local city = Selection.resolve(db, function() return 120 end)
  check("manual machine uses injected offset", city.baseUtcOffset == 120 and city.dstRule == "none")
  check("manual machine offset applied by Cities.times",
    Cities.times(city, 2026, 7, 1).offsetMinutes == 120)
end

-- Invalid manual entry is rejected and does not change the selection.
do
  local db = { selectedCity = { kind = "city", name = "Berlin" } }
  local ok, err = Selection.setManual(db, 999, 0)
  check("invalid manual rejected with message", ok == false and type(err) == "string")
  check("invalid manual leaves selection untouched", db.selectedCity.name == "Berlin")
end

-- Window follows the persisted selection (title + times).
do
  local db = {}
  Selection.setCity(db, "Istanbul")
  Window.init(db)
  WowMock.setNow(1766318400)
  Window.refresh()
  check("Window title follows selection", Window.frame.title:GetText() == "Istanbul")
  local iCity = Cities.findByName("Istanbul")
  local iNow = Clock.cityNow(iCity, 1766318400)
  local iRes = Cities.times("Istanbul", iNow.year, iNow.month, iNow.day)
  check("Window Fajr follows selection", Window.frame.rows.fajr.time:GetText() == iRes.prayers.fajr.hhmm)
end

-- ---- 2d-4a: city picker (logic under the mock) ---------------------------
local Picker = require("Picker")

-- Display list: empty query -> headers + all 65 cities; query -> flat matches.
do
  local all = Cities.displayList("")
  local cityRows, headerRows = 0, 0
  for _, r in ipairs(all) do
    if r.kind == "city" then cityRows = cityRows + 1 else headerRows = headerRows + 1 end
  end
  check("displayList('') lists all 65 cities", cityRows == 65)
  check("displayList('') has country headers", headerRows >= 10)
  local hits = Cities.displayList("ber")
  local foundBerlin = false
  for _, r in ipairs(hits) do if r.kind == "city" and r.city.name == "Berlin" then foundBerlin = true end end
  check("displayList('ber') finds Berlin, no headers", foundBerlin and hits[1].kind == "city")
end

-- shouldAutoOpen: true with no selection, false once chosen.
check("first run auto-opens picker", Picker.shouldAutoOpen({}) == true)
check("does not auto-open once chosen",
  Picker.shouldAutoOpen({ selectedCity = { kind = "city", name = "Berlin" } }) == false)

-- currentSelectionText for the three cases.
check("indicator: default", Picker.currentSelectionText({}) == "Selected: Rotterdam (default)")
check("indicator: city",
  Picker.currentSelectionText({ selectedCity = { kind = "city", name = "Sarajevo" } })
    == "Selected: Sarajevo, Bosnia and Herzegovina")
check("indicator: manual",
  Picker.currentSelectionText({ selectedCity = { kind = "manual", latitude = 48.5, longitude = 9, tz = "machine" } })
    :find("Manual 48.5000, 9.0000") ~= nil)

-- Build the picker under the mock and drive selection/manual logic.
do
  local pdb = {}
  Window.init(pdb)
  Picker.init(pdb)
  Window.create()
  Picker.create()
  WowMock.setNow(1766318400)

  check("picker builds master + detail row pools",
    #Picker.masterPool == 20 and #Picker.detailPool == 18)
  Picker.refreshLocation("")
  check("master column lists every country (+ COUNTRIES header)",
    #Picker.masterData == (#Cities.byCountry() + 1))

  -- Selecting a city persists and updates the main window.
  Picker.selectCity("Sarajevo")
  check("selectCity persists", pdb.selectedCity.kind == "city" and pdb.selectedCity.name == "Sarajevo")
  check("selectCity updates main window title", Window.frame.title:GetText() == "Sarajevo")
  check("selectCity updates indicator", Picker.selectedLabel:GetText():find("Sarajevo") ~= nil)

  -- Manual entry (machine tz) persists and retargets the window.
  local ok = Picker.applyManual("48.5", "9.0", "")
  check("applyManual valid accepted", ok == true)
  check("applyManual persists manual", pdb.selectedCity.kind == "manual" and pdb.selectedCity.tz == "machine")
  check("applyManual updates window title", Window.frame.title:GetText() == "Manual")

  -- Manual entry with explicit offset override.
  Picker.applyManual("40.0", "20.0", "2")
  check("applyManual offset override -> fixed +120",
    pdb.selectedCity.tz == "fixed" and pdb.selectedCity.baseUtcOffset == 120)

  -- Invalid coordinates are rejected and leave the selection unchanged.
  local before = pdb.selectedCity
  local ok2, err2 = Picker.applyManual("999", "0", "")
  check("applyManual invalid rejected", ok2 == false and type(err2) == "string")
  check("applyManual invalid keeps selection", pdb.selectedCity == before)

  -- Search drives the detail column (flat cross-city matches); scroll clamps.
  Picker.refreshLocation("istanbul")
  check("search narrows detail to Istanbul",
    #Picker.detailData == 1 and Picker.detailData[1].city.name == "Istanbul" and Picker.detailSearching)
  Picker.refreshLocation("")
  Picker.scrollDetail(-100) -- scroll way down; offset clamps, no error
  check("detail scroll offset clamps", Picker.dScroll <= math.max(0, #Picker.detailData - 18))

  -- Selected city is checkmarked/highlighted in the detail column.
  Picker.selectCity("Istanbul")
  Picker.refreshLocation("istanbul") -- one row, the selected city
  check("selected detail row marked", Picker.detailPool[1]._selected == true)
  Picker.refreshLocation("berlin")
  check("non-selected detail row not marked", Picker.detailPool[1]._selected == false)

  -- Master column: picking a country drives the detail column.
  Picker.selectCountry("Germany")
  check("selectCountry filters detail to that country",
    Picker.selectedCountry == "Germany" and #Picker.detailData >= 1)

  -- Tab order wired across the add-form input fields.
  check("lat has tab handler", Picker.latBox:GetScript("OnTabPressed") ~= nil)
  check("lon has tab handler", Picker.lonBox:GetScript("OnTabPressed") ~= nil)
  check("offset has tab handler", Picker.offsetBox:GetScript("OnTabPressed") ~= nil)
  check("name has tab handler", Picker.nameBox:GetScript("OnTabPressed") ~= nil)
end

-- ---- 2d-4b: notification controls wired into the picker ------------------
do
  local ndb = {}
  Window.init(ndb)
  Picker.init(ndb)
  Picker.frame = nil -- force a fresh build with the new controls
  Picker.create()

  check("notif controls built", Picker.beforeBox ~= nil and Picker.atCheck ~= nil and Picker.soundCheck ~= nil)

  -- before-minutes parsing.
  Picker.setBeforeMinutes("15")
  check("setBeforeMinutes accepts 15", ndb.notify.beforeMinutes == 15)
  Picker.setBeforeMinutes("-3")
  check("setBeforeMinutes clamps negative to 0", ndb.notify.beforeMinutes == 0)
  Picker.setBeforeMinutes("abc")
  check("setBeforeMinutes non-number -> 0", ndb.notify.beforeMinutes == 0)

  -- toggles.
  Picker.setAtTime(false); check("setAtTime false", ndb.notify.atTime == false)
  Picker.setAtTime(true); check("setAtTime true", ndb.notify.atTime == true)
  Picker.setSound(false); check("setSound false", ndb.notify.sound == false)
  Picker.setSound(true); check("setSound true", ndb.notify.sound == true)

  -- The Notifier reads these settings live: both-off -> no alerts; at -> fires.
  local five = { fajr = 402, dhuhr = 761, asr = 857, maghrib = 993, isha = 1112 }
  Picker.setBeforeMinutes("0"); Picker.setAtTime(false)
  local fired1, any1 = {}, false
  for m = 0, 1439 do if #Notifier.check(five, m, ndb.notify, "D", fired1) > 0 then any1 = true end end
  check("controls: both off -> Notifier silent", any1 == false)

  Picker.setAtTime(true)
  local fired2 = {}
  local atFires = #Notifier.check(five, 993, ndb.notify, "D", fired2)
  check("controls: at-time on -> Notifier fires", atFires == 1)
end

-- ---- 2d-5: slash command logic (city-by-name) + empty-manual fix --------
do
  local db5 = {}
  Window.init(db5)
  Picker.init(db5)

  check("city <name> matches (case-insensitive)", Picker.selectCityByName("vienna") == "Vienna")
  check("city <name> persists", db5.selectedCity.name == "Vienna")
  check("city <name> handles multi-word", Picker.selectCityByName("saint petersburg") == "Saint Petersburg")
  check("city <name> unknown -> nil", Picker.selectCityByName("Atlantis") == nil)
  check("unknown city leaves selection", db5.selectedCity.name == "Saint Petersburg")

  -- Empty manual entry is a no-op (the validation-error-on-empty fix).
  local ok = Picker.applyManual("", "", "")
  check("empty manual no-op, no selection change",
    ok == false and db5.selectedCity.name == "Saint Petersburg")
end

-- ---- 2d crash fix: non-finite times at polar latitudes -------------------
-- Validation rejects polar / out-of-range coordinates.
check("validateCoords rejects north pole", (Selection.validateCoords(90, 0)) == false)
check("validateCoords rejects arctic 80", (Selection.validateCoords(80, 20)) == false)
check("validateCoords rejects 66 (polar boundary)", (Selection.validateCoords(66, 20)) == false)
check("validateCoords rejects -66", (Selection.validateCoords(-66, 0)) == false)
check("validateCoords accepts 65", (Selection.validateCoords(65, 20)) == true)
check("validateCoords accepts Helsinki 60.2", (Selection.validateCoords(60.17, 24.94)) == true)
check("validateCoords rejects longitude 200", (Selection.validateCoords(50, 200)) == false)

-- formatHHMM fails safe on non-finite input.
local NAN = 0 / 0
check("formatHHMM NaN -> --:--", Timezone.formatHHMM(NAN) == "--:--")
check("formatHHMM +Inf -> --:--", Timezone.formatHHMM(math.huge) == "--:--")
check("formatHHMM normal still works", Timezone.formatHHMM(625) == "10:25")

-- Engine defense in depth: even if a polar coord reaches the engine (bypassing
-- validation), it must not crash -- undefined prayers render "--:--", not NaN.
do
  local polar = { name = "Polar", latitude = 80, longitude = 20, baseUtcOffset = 0, dstRule = "none" }
  local ok, res = pcall(Cities.times, polar, 2026, 6, 21)
  check("Cities.times at polar lat does not crash", ok == true)
  check("polar Maghrib renders --:-- (not NaN)", res.prayers.maghrib.hhmm == "--:--" and res.prayers.maghrib.localMin == nil)
end

-- Schedule tolerates a nil (undefined) time without erroring.
do
  local partial = { fajr = 300, sunrise = 360, dhuhr = 700, asr = 800, maghrib = nil, isha = nil }
  local ok = pcall(Schedule.compute, partial, 750)
  check("Schedule.compute tolerates nil times", ok == true)
end

-- applyManual rejects a polar coordinate with the normal error, no crash.
do
  local db = { selectedCity = { kind = "city", name = "Berlin" } }
  Picker.init(db)
  local ok, err = Picker.applyManual("80", "20", "")
  check("applyManual rejects polar with message", ok == false and type(err) == "string")
  check("applyManual polar leaves selection unchanged", db.selectedCity.name == "Berlin")
end

-- ---- 2d-4c: saved "My Cities" (model + picker) ---------------------------
do
  local db = {}
  Window.init(db)
  Picker.init(db)

  -- Save (machine tz) -> persists, validates, and auto-selects.
  local ok = Picker.saveManual("Travnik", "44.2261", "17.6650", "", false)
  check("saveManual accepted", ok == true)
  check("saved city persisted", Selection.findSaved(db, "Travnik") ~= nil)
  check("saved city uses machine tz", Selection.findSaved(db, "Travnik").tz == "machine")
  check("saving selects it", db.selectedCity.kind == "saved" and db.selectedCity.name == "Travnik")

  -- Saved city flows through the same pipeline (resolve + Cities.times).
  local resolved = Selection.resolve(db, function() return 60 end)
  check("saved resolves with machine offset", resolved.name == "Travnik" and resolved.baseUtcOffset == 60)
  check("saved produces times", Cities.times(resolved, 2026, 1, 15).prayers.fajr.hhmm ~= nil)

  -- Save with explicit offset + EU rule.
  Picker.saveManual("Tashkent", "41.3", "69.2", "5", false)
  check("saved fixed offset", Selection.findSaved(db, "Tashkent").baseUtcOffset == 300)
  check("saved fixed dstRule none", Selection.findSaved(db, "Tashkent").dstRule == "none")
  Picker.saveManual("MyBerlin", "52.5", "13.4", "1", true)
  check("saved fixed EU rule", Selection.findSaved(db, "MyBerlin").dstRule == "EU")

  -- Duplicate name rejected; empty name rejected; polar rejected.
  local dOk, dErr = Picker.saveManual("Travnik", "40", "10", "", false)
  check("duplicate name rejected", dOk == false and dErr:find("already exists") ~= nil)
  check("empty name rejected", (Picker.saveManual("", "40", "10", "", false)) == false)
  check("polar coord rejected on save", (Picker.saveManual("Pole", "80", "10", "", false)) == false)
  check("invalid coords rejected on save", (Picker.saveManual("Bad", "abc", "10", "", false)) == false)

  -- Picker rows: My Cities group on top, with the built-in list beneath.
  local rows = Picker.buildRows(db, "")
  check("first row is My Cities header", rows[1].kind == "header" and rows[1].label == "My Cities")
  check("saved rows follow the header", rows[2].kind == "saved")
  local hasBuiltin = false
  for _, r in ipairs(rows) do if r.kind == "city" then hasBuiltin = true end end
  check("built-in cities still present", hasBuiltin)

  -- Search filters saved cities too.
  local s = Picker.buildRows(db, "trav")
  check("search matches saved city", s[1].kind == "header" and s[2].kind == "saved" and s[2].city.name == "Travnik")

  -- Delete: removes it and clears selection if it was active.
  Selection.setSavedCity(db, "Travnik")
  Picker.deleteSaved("Travnik")
  check("deleted saved city gone", Selection.findSaved(db, "Travnik") == nil)
  check("deleting selected falls back to default", db.selectedCity == nil)

  -- Rename (nice-to-have, model-level).
  check("rename saved city", (Selection.renameCity(db, "Tashkent", "Samarkand")) == true)
  check("renamed present, old gone",
    Selection.findSaved(db, "Samarkand") ~= nil and Selection.findSaved(db, "Tashkent") == nil)
end

-- Picker renders saved rows + highlight + delete buttons (under the mock).
do
  local db = {}
  Window.init(db); Picker.init(db)
  Picker.frame = nil
  Selection.saveCity(db, "Travnik", 44.2261, 17.6650, {})
  Picker.create()
  Picker.selectSaved("Travnik")
  Picker.refreshLocation("")
  check("My Cities header rendered in master row 1", Picker.masterPool[1].kind == "header")
  check("saved row rendered + selected + delete shown",
    Picker.masterPool[2].kind == "saved" and Picker.masterPool[2]._selected == true
    and Picker.masterPool[2].delBtn:IsShown() == true)
  check("name field has tab handler", Picker.nameBox:GetScript("OnTabPressed") ~= nil)
end

-- ---- 3-1: all method factories carry the adhan-js parameters -------------
-- Structural checks only (parameters, not times -- the +/-1 min time gate is
-- the 3-2 fixture matrix). Verifies every factory ports the exact angles,
-- intervals, method adjustments, and the inert maghribAngle/rounding fields
-- from adhan-js 4.4.4. CalculationMethod is already required above.
do
  local function adj(p) return p.methodAdjustments end

  local mwl = CalculationMethod.MuslimWorldLeague()
  check("MWL 18/17, dhuhr +1, no maghribAngle, nearest",
    mwl.fajrAngle == 18 and mwl.ishaAngle == 17 and adj(mwl).dhuhr == 1
    and mwl.maghribAngle == 0 and mwl.rounding == "nearest")

  local eg = CalculationMethod.Egyptian()
  check("Egyptian 19.5/17.5, dhuhr +1",
    eg.fajrAngle == 19.5 and eg.ishaAngle == 17.5 and adj(eg).dhuhr == 1)

  local ka = CalculationMethod.Karachi()
  check("Karachi 18/18, dhuhr +1",
    ka.fajrAngle == 18 and ka.ishaAngle == 18 and adj(ka).dhuhr == 1)

  local uq = CalculationMethod.UmmAlQura()
  check("UmmAlQura 18.5, isha interval 90, no isha angle",
    uq.fajrAngle == 18.5 and uq.ishaAngle == 0 and uq.ishaInterval == 90)

  local du = CalculationMethod.Dubai()
  check("Dubai 18.2/18.2, adj sunrise -3 dhuhr/asr/maghrib +3",
    du.fajrAngle == 18.2 and du.ishaAngle == 18.2 and adj(du).sunrise == -3
    and adj(du).dhuhr == 3 and adj(du).asr == 3 and adj(du).maghrib == 3)

  local na = CalculationMethod.NorthAmerica()
  check("NorthAmerica/ISNA 15/15, dhuhr +1",
    na.fajrAngle == 15 and na.ishaAngle == 15 and adj(na).dhuhr == 1)

  local kw = CalculationMethod.Kuwait()
  check("Kuwait 18/17.5, no adjustments",
    kw.fajrAngle == 18 and kw.ishaAngle == 17.5 and adj(kw).dhuhr == 0)

  local qa = CalculationMethod.Qatar()
  check("Qatar 18, isha interval 90, no isha angle",
    qa.fajrAngle == 18 and qa.ishaAngle == 0 and qa.ishaInterval == 90)

  local sg = CalculationMethod.Singapore()
  check("Singapore 20/18, dhuhr +1, rounding up",
    sg.fajrAngle == 20 and sg.ishaAngle == 18 and adj(sg).dhuhr == 1
    and sg.rounding == "up")

  local te = CalculationMethod.Tehran()
  check("Tehran 17.7/14, maghribAngle 4.5, no isha interval",
    te.fajrAngle == 17.7 and te.ishaAngle == 14 and te.maghribAngle == 4.5
    and te.ishaInterval == 0)

  local tr = CalculationMethod.Turkey()
  check("Turkey 18/17, adj sunrise -7 dhuhr +5 asr +4 maghrib +7",
    tr.fajrAngle == 18 and tr.ishaAngle == 17 and adj(tr).sunrise == -7
    and adj(tr).dhuhr == 5 and adj(tr).asr == 4 and adj(tr).maghrib == 7)

  local ot = CalculationMethod.Other()
  check("Other 0/0, no interval/angle",
    ot.fajrAngle == 0 and ot.ishaAngle == 0 and ot.ishaInterval == 0
    and ot.maghribAngle == 0)

  -- Shafi default carried through every factory; Asr school is set separately.
  check("factory default madhab is Shafi", mwl.madhab == require("Madhab").Shafi)
end

-- ---- 3-2 EXIT CRITERION: method x Asr x city matrix vs adhan-js ----------
-- Drive every fixture row through Calculator (which defaults the high-latitude
-- rule to recommended(coords), exactly mirroring the generator) and compare
-- all six times to adhan-js within +/-1 minute. Prints a per-method PASS/FAIL
-- summary with the worst cell, plus a detail line for every over-tolerance
-- cell. Expected gaps before 3-3: Tehran (Maghrib angle) and possibly
-- Singapore (round-up). Calculator/PrayerTimes/CalculationMethod required above.
do
  local matrix = dofile("fixtures/methods_matrix.lua")
  print("\n=== Phase 3-2 gate: method x {shafi,hanafi} x city vs adhan-js 4.4.4 ===")
  print(string.format("    (%d rows, tolerance +/-1 min, recommended high-lat rule)\n",
    matrix.meta.count))

  -- 3-3 closed the Tehran Maghrib-angle and Singapore round-up gaps, so there
  -- is no quarantine: every method must now match adhan-js at exactly 0 min.
  local function knownPending() return false end

  -- Per-method aggregate across both madhabs / all cities / all dates.
  local order, stats = {}, {}
  local function stat(m)
    if not stats[m] then
      stats[m] = { fails = 0, pending = 0, maxDiff = 0, worst = "" }
      order[#order + 1] = m
    end
    return stats[m]
  end
  local pendingLines = {}

  for _, r in ipairs(matrix.rows) do
    local y, mo, d = r.date:match("(%d+)-(%d+)-(%d+)")
    y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
    local params = CalculationMethod[r.method]()
    params.madhab = r.madhab
    local pt = Calculator.timesForLocation(y, mo, d,
      { latitude = r.lat, longitude = r.lon }, { params = params })
    local s = stat(r.method)
    for _, p in ipairs(PRAYERS) do
      local diff = (pt[p] == nil) and 9999 or minuteDiff(pt[p], r[p])
      local ok = diff <= TOLERANCE
      if diff > s.maxDiff then
        s.maxDiff = diff
        s.worst = string.format("%s/%s %s %s %s diff=%d", r.method, r.madhab, r.city, r.date, p, diff)
      end
      if not ok and knownPending(r.method, p) then
        -- Quarantined: counted as pending, not a failure (keeps suite green).
        s.pending = s.pending + 1
        pendingLines[#pendingLines + 1] = string.format("    PENDING %-8s %-6s %-9s %-10s %-7s diff=%d",
          r.method, r.madhab, r.city, r.date, p, diff)
      else
        check(string.format("%s/%s %s %s %s within +/-1", r.method, r.madhab, r.city, r.date, p), ok)
        if not ok then s.fails = s.fails + 1 end
      end
    end
  end

  print(string.format("%-18s %-10s %-9s %s", "method", "status", "maxDiff", "worst cell"))
  for _, m in ipairs(order) do
    local s = stats[m]
    local status = "PASS"
    if s.fails > 0 then status = "FAIL:" .. s.fails
    elseif s.pending > 0 then status = "PENDING:" .. s.pending end
    print(string.format("%-18s %-10s %-9d %s", m, status, s.maxDiff,
      s.maxDiff > 0 and s.worst or ""))
  end
  if #pendingLines > 0 then
    print("\n  KNOWN PENDING -- engine gap closed in 3-3 (Tehran Maghrib angle):")
    for _, line in ipairs(pendingLines) do print(line) end
  end
end

-- ---- 3-4: method/Asr registry + wiring through Cities.times --------------
do
  local Methods = require("Methods")
  local Cities = require("Cities")

  -- Registry shape + ordering (default first).
  check("Methods.list first entry is MWL", Methods.list()[1].key == "MuslimWorldLeague")
  check("Methods.list has all 12 methods", #Methods.list() == 12)
  check("Methods.asrList has 2 schools", #Methods.asrList() == 2)
  check("DEFAULT_METHOD/MADHAB are MWL/shafi",
    Methods.DEFAULT_METHOD == "MuslimWorldLeague" and Methods.DEFAULT_MADHAB == "shafi")

  -- Safe fallback for unknown / nil / stale keys.
  check("resolveMethod(nil) -> MWL", Methods.resolveMethod(nil) == "MuslimWorldLeague")
  check("resolveMethod('Bogus') -> MWL", Methods.resolveMethod("Bogus") == "MuslimWorldLeague")
  check("resolveMethod('Tehran') -> Tehran", Methods.resolveMethod("Tehran") == "Tehran")
  check("resolveMadhab(nil) -> shafi", Methods.resolveMadhab(nil) == "shafi")
  check("resolveMadhab('bogus') -> shafi", Methods.resolveMadhab("bogus") == "shafi")
  check("resolveMadhab('hanafi') -> hanafi", Methods.resolveMadhab("hanafi") == "hanafi")

  -- params() builds the right CalculationParameters with the madhab applied.
  local pDef = Methods.params(nil, nil)
  check("params(nil,nil) == MWL/shafi",
    pDef.method == "MuslimWorldLeague" and pDef.fajrAngle == 18 and pDef.madhab == "shafi")
  local pTeh = Methods.params("Tehran", "hanafi")
  check("params('Tehran','hanafi') carries angle + madhab",
    pTeh.fajrAngle == 17.7 and pTeh.maghribAngle == 4.5 and pTeh.madhab == "hanafi")
  local pBad = Methods.params("Bogus", "bogus")
  check("params(bad,bad) -> MWL/shafi", pBad.method == "MuslimWorldLeague" and pBad.madhab == "shafi")

  -- Wiring: omitting opts must reproduce explicit MWL/Standard exactly.
  local dflt = Cities.times("Rotterdam", 2026, 6, 21)
  local mwl = Cities.times("Rotterdam", 2026, 6, 21, { method = "MuslimWorldLeague", madhab = "shafi" })
  local sameAsDefault = true
  for _, p in ipairs(PRAYERS) do
    if dflt.prayers[p].localMin ~= mwl.prayers[p].localMin then sameAsDefault = false end
  end
  check("Cities.times default == explicit MWL/Standard (default unchanged)", sameAsDefault)

  -- Asr school moves Asr: Hanafi (shadow factor 2) is later than Standard.
  local shafi = Cities.times("Istanbul", 2026, 1, 15, { madhab = "shafi" })
  local hanafi = Cities.times("Istanbul", 2026, 1, 15, { madhab = "hanafi" })
  check("Hanafi Asr later than Standard Asr",
    hanafi.prayers.asr.localMin > shafi.prayers.asr.localMin)

  -- Method moves Fajr: ISNA (15 deg) Fajr is later than MWL (18 deg) in winter.
  local isna = Cities.times("Istanbul", 2026, 1, 15, { method = "NorthAmerica" })
  local mwlIst = Cities.times("Istanbul", 2026, 1, 15, { method = "MuslimWorldLeague" })
  check("ISNA Fajr differs from MWL Fajr (shallower angle, later)",
    isna.prayers.fajr.localMin ~= mwlIst.prayers.fajr.localMin
    and isna.prayers.fajr.localMin > mwlIst.prayers.fajr.localMin)

  -- Window.init seeds + sanitises the persisted settings.
  do
    local db = { method = "Bogus", madhab = "bogus" }
    Window.init(db)
    check("Window.init sanitises stale method/madhab to defaults",
      db.method == "MuslimWorldLeague" and db.madhab == "shafi")
    local db2 = {}
    Window.init(db2)
    check("Window.init defaults method/madhab when absent",
      db2.method == "MuslimWorldLeague" and db2.madhab == "shafi")
  end
end

-- ---- 3-5: method/Asr settings controls in the picker (under the mock) ----
do
  local Picker = require("Picker")
  local Methods = require("Methods")

  local db = {}
  Window.init(db); Picker.init(db)
  Picker.frame = nil
  Picker.create()

  -- Spy on Window.refresh to prove the controls trigger a live recompute.
  local realRefresh = Window.refresh
  local refreshes = 0
  Window.refresh = function(...) refreshes = refreshes + 1; return realRefresh(...) end

  -- Default reflects MWL (dropdown button shows the current method label).
  check("method dropdown shows MWL by default",
    Picker.methodDropdown.button:GetText() == Methods.methodLabel("MuslimWorldLeague"))

  -- setMethod persists, refreshes, and updates the dropdown button.
  Picker.setMethod("Tehran")
  check("setMethod persists to db", db.method == "Tehran")
  check("setMethod updates the dropdown button",
    Picker.methodDropdown.button:GetText() == Methods.methodLabel("Tehran"))
  check("setMethod triggers a window refresh", refreshes >= 1)

  -- Bogus key falls back to MWL via the registry.
  Picker.setMethod("Nonsense")
  check("setMethod sanitises unknown key -> MWL", db.method == "MuslimWorldLeague")

  -- cycleMethod logic is retained (kept pure/tested even though the arrows are
  -- gone): prev from MWL (first) wraps to last, next wraps back to first.
  local list = Methods.list()
  Picker.setMethod(list[1].key)
  Picker.cycleMethod(-1)
  check("cycleMethod(-1) wraps to last method", db.method == list[#list].key)
  Picker.cycleMethod(1)
  check("cycleMethod(1) wraps back to first (MWL)", db.method == list[1].key)

  -- toggleMadhab + setMadhab logic flips Standard <-> Hanafi.
  db.madhab = "shafi"
  Picker.toggleMadhab()
  check("toggleMadhab shafi -> hanafi", db.madhab == "hanafi")
  Picker.toggleMadhab()
  check("toggleMadhab hanafi -> shafi", db.madhab == "shafi")

  Window.refresh = realRefresh
end

-- ---- 3R-1: tabbed settings scaffold (navigation only, under the mock) ----
do
  local Picker = require("Picker")
  local db = {}
  Window.init(db); Picker.init(db)
  Picker.frame = nil
  Picker.create()

  -- Three tabs + three panels exist.
  check("three tab buttons created",
    Picker.tabButtons.location and Picker.tabButtons.calculation and Picker.tabButtons.notifications ~= nil)
  check("three panels created",
    Picker.panels.location and Picker.panels.calculation and Picker.panels.notifications ~= nil)

  -- Default tab is Location: its panel shown, the others hidden.
  check("default active tab is location", Picker.activeTab == "location")
  check("location panel shown by default", Picker.panels.location:IsShown() == true)
  check("calculation panel hidden by default", Picker.panels.calculation:IsShown() == false)
  check("notifications panel hidden by default", Picker.panels.notifications:IsShown() == false)

  -- Switching tabs flips visibility (one shown at a time).
  Picker.showTab("calculation")
  check("showTab(calculation) shows calc panel", Picker.panels.calculation:IsShown() == true)
  check("showTab(calculation) hides location panel", Picker.panels.location:IsShown() == false)
  check("showTab(calculation) hides notifications panel", Picker.panels.notifications:IsShown() == false)
  check("active tab updated to calculation", Picker.activeTab == "calculation")

  Picker.showTab("notifications")
  check("showTab(notifications) shows notif panel", Picker.panels.notifications:IsShown() == true)
  check("only one panel shown at a time",
    Picker.panels.location:IsShown() == false and Picker.panels.calculation:IsShown() == false)

  -- Unknown tab name falls back to location (never blank).
  Picker.showTab("bogus")
  check("unknown tab falls back to location", Picker.activeTab == "location")

  -- Existing controls survived the move into panels (still present + wired).
  check("search box still present", Picker.searchBox ~= nil)
  check("name box still has tab handler", Picker.nameBox:GetScript("OnTabPressed") ~= nil)
  check("method dropdown + Asr radios still present", Picker.methodDropdown ~= nil and Picker.asrRadios ~= nil)
  check("notification controls still present",
    Picker.beforeBox ~= nil and Picker.atCheck ~= nil and Picker.soundCheck ~= nil)

  -- And still functional after the re-parent: city select + method set work.
  Picker.selectCityByName("Istanbul")
  check("city selection still works through tabs", db.selectedCity and db.selectedCity.name == "Istanbul")
  Picker.setMethod("Tehran")
  check("method selection still works through tabs", db.method == "Tehran")
end

-- ---- 3R-2: reusable dropdown component + Calculation tab controls --------
do
  local Picker = require("Picker")
  local Methods = require("Methods")
  local db = {}
  Window.init(db); Picker.init(db)
  Picker.frame = nil
  Picker.create()

  local dd = Picker.methodDropdown
  check("method dropdown created", dd ~= nil and dd.button ~= nil)

  -- Closed initially; opening shows the popup + catcher and renders rows.
  check("dropdown starts closed", dd.isOpen == false and dd.popup:IsShown() == false)
  dd:open()
  check("open() shows popup + catcher", dd.popup:IsShown() == true and dd.catcher:IsShown() == true)
  check("open() renders min(visible, options) rows",
    dd.rows[1]:IsShown() == true and dd.rows[8]:IsShown() == true)

  -- Current method (MWL) is highlighted among the rendered rows.
  local function selectedRowKey()
    for _, r in ipairs(dd.rows) do if r._selected then return r.key end end
  end
  check("current method highlighted in the list", selectedRowKey() == "MuslimWorldLeague")

  -- Scrolling moves the window into the 12-item list (12 > 8 visible).
  dd:scroll(-1)
  check("scroll advances the offset", dd.scrollOffset == 1)
  dd:scroll(99)
  check("scroll clamps to top", dd.scrollOffset == 0)

  -- Selecting an item closes the list, persists, and updates the button label.
  dd:select("Tehran")
  check("select() closes the dropdown", dd.isOpen == false and dd.popup:IsShown() == false)
  check("select() persists the choice", db.method == "Tehran")
  check("select() updates the button label", dd.button:GetText() == Methods.methodLabel("Tehran"))

  -- Selecting an unknown key falls back to MWL via the registry.
  dd:select("Nonsense")
  check("select(unknown) -> MWL fallback", db.method == "MuslimWorldLeague")

  -- Asr radios: exactly one checked, reflecting the current madhab.
  local function checkedRadios()
    local n, key = 0, nil
    for _, r in ipairs(Picker.asrRadios) do if r:GetChecked() then n = n + 1; key = r.key end end
    return n, key
  end
  db.madhab = "shafi"; Picker.updateCalcControls()
  local n, key = checkedRadios()
  check("exactly one Asr radio checked (Standard)", n == 1 and key == "shafi")

  -- Clicking the Hanafi radio is mutually exclusive + updates Asr live.
  local realRefresh = Window.refresh
  local refreshes = 0
  Window.refresh = function(...) refreshes = refreshes + 1; return realRefresh(...) end
  Picker.asrRadios[2]:GetScript("OnClick")(Picker.asrRadios[2])
  local n2, key2 = checkedRadios()
  check("clicking Hanafi radio selects it exclusively", n2 == 1 and key2 == "hanafi")
  check("Asr radio click persists madhab", db.madhab == "hanafi")
  check("Asr radio click refreshes the window", refreshes >= 1)
  Window.refresh = realRefresh
end

-- ---- 3R-3: Location "Add a location" form re-layout (under the mock) -----
do
  local Picker = require("Picker")
  local db = {}
  Window.init(db); Picker.init(db)
  Picker.frame = nil
  Picker.create()

  -- All form widgets survived the re-layout.
  check("form fields present after re-layout",
    Picker.latBox and Picker.lonBox and Picker.offsetBox and Picker.nameBox and Picker.euCheck ~= nil)

  -- Tab-key chain wired across the new order (lat->lon->utc->name->search).
  check("lat/lon/utc/name all have tab handlers",
    Picker.latBox:GetScript("OnTabPressed") and Picker.lonBox:GetScript("OnTabPressed")
    and Picker.offsetBox:GetScript("OnTabPressed") and Picker.nameBox:GetScript("OnTabPressed") ~= nil)

  -- Logic intact: saving a named city through the new layout still works.
  Picker.nameBox:SetText("Travnik")
  Picker.latBox:SetText("44.2261"); Picker.lonBox:SetText("17.6650")
  local ok = Picker.saveManual(Picker.nameBox:GetText(), Picker.latBox:GetText(),
    Picker.lonBox:GetText(), "", false)
  check("save through new layout creates the city", ok == true and Selection.findSaved(db, "Travnik") ~= nil)

  -- Validation never fires on empty fields (both lat+lon empty = no-op, no error).
  Picker.clearError()
  local applied = Picker.applyManual("", "", "")
  check("empty Use-once is a no-op with no error",
    applied == false and Picker.errorLabel:GetText() == "")

  -- Save with empty name still errors (validation reused unchanged).
  local sOk, sErr = Picker.saveManual("", "50", "5", "", false)
  check("save with empty name still errors", sOk == false and sErr ~= nil)
end

-- ---- 3S-1: Approach B chrome (sidebar nav + header) under the mock -------
do
  local Picker = require("Picker")
  local db = {}
  Window.init(db); Picker.init(db)
  Picker.frame = nil
  Picker.create()

  -- Sidebar nav items (title + subtitle + active marker) for all three tabs.
  check("three sidebar nav items created",
    Picker.navItems.location and Picker.navItems.calculation and Picker.navItems.notifications ~= nil)
  check("each nav item has a gold bar + highlight",
    Picker.navItems.location.bar ~= nil and Picker.navItems.location.hl ~= nil)

  -- Active section marked: its bar+highlight shown, others hidden.
  Picker.showTab("location")
  check("active nav shows bar + highlight",
    Picker.navItems.location.bar:IsShown() == true and Picker.navItems.location.hl:IsShown() == true)
  check("inactive nav hides bar + highlight",
    Picker.navItems.calculation.bar:IsShown() == false and Picker.navItems.notifications.hl:IsShown() == false)
  Picker.showTab("notifications")
  check("switching marks the new section only",
    Picker.navItems.notifications.bar:IsShown() == true
    and Picker.navItems.location.bar:IsShown() == false)

  -- Panels still switch (one shown at a time) under the new chrome.
  check("only the active panel is shown",
    Picker.panels.notifications:IsShown() == true and Picker.panels.location:IsShown() == false)

  -- Header location reflects the selection and updates on change.
  Picker.selectCityByName("Istanbul")
  Picker.updateSelected()
  check("header shows City . Country",
    Picker.headerLoc:GetText() ~= nil and Picker.headerLoc:GetText():find("Istanbul", 1, true) ~= nil)
end

-- ---- 3S-2: Location master-detail (country -> city, search, card) --------
do
  local Picker = require("Picker")
  local db = {}
  Window.init(db); Picker.init(db)
  Picker.frame = nil
  Picker.create()

  -- masterRows: COUNTRIES header + one row per country; My Cities prepended.
  local m = Picker.masterRows(db)
  check("masterRows has a COUNTRIES header", m[1].kind == "cheader" and m[1].label == "COUNTRIES")
  check("masterRows lists every country with a count",
    #m == (1 + #Cities.byCountry()) and m[2].kind == "country" and m[2].count >= 1)
  Selection.saveCity(db, "Hometown", 50, 5, {})
  local m2 = Picker.masterRows(db)
  check("My Cities header + saved row prepended",
    m2[1].kind == "myheader" and m2[2].kind == "saved" and m2[2].city.name == "Hometown")

  -- detailRows: country filter vs cross-city search.
  local dRows, searching = Picker.detailRows(db, "", "Germany")
  check("detailRows by country returns that country's cities", #dRows >= 1 and not searching)
  local sRows, s2 = Picker.detailRows(db, "istan", nil)
  check("detailRows by query searches across cities", s2 == true
    and sRows[1] and sRows[1].city.name == "Istanbul")

  -- defaultCountry follows the current city selection.
  Picker.selectCity("Berlin")
  check("defaultCountry follows selection", Picker.defaultCountry(db) == "Germany")

  -- selectCountry drives the detail column + marks the master row.
  Picker.selectCountry("France")
  check("selectCountry sets selectedCountry + detail", Picker.selectedCountry == "France")
  local franceSelectedInMaster = false
  for _, row in ipairs(Picker.masterPool) do
    if row.kind == "country" and row.country == "France" then franceSelectedInMaster = row._selected end
  end
  check("selected country highlighted in master", franceSelectedInMaster == true)

  -- Checkmark on the selected city in the detail column.
  Picker.selectCity("Paris")
  Picker.selectCountry("France")
  local parisChecked = false
  for _, row in ipairs(Picker.detailPool) do
    if row.name == "Paris" then parisChecked = row._selected end
  end
  check("selected city checkmarked in detail", parisChecked == true)

  -- Current-location card reflects the selection.
  check("card shows the selected city + country",
    Picker.cardCity:GetText() == "Paris" and Picker.cardCountry:GetText() == "France")

  -- "Add custom location" opens the overlay and hides the browse view (so
  -- nothing shows through); Back/closeAddPanel restores it.
  check("add panel hidden + browse shown by default",
    Picker.addPanel:IsShown() == false and Picker.browse:IsShown() == true)
  Picker.openAddPanel()
  check("openAddPanel shows form + hides browse",
    Picker.addPanel:IsShown() == true and Picker.browse:IsShown() == false)
  Picker.closeAddPanel()
  check("closeAddPanel hides form + restores browse",
    Picker.addPanel:IsShown() == false and Picker.browse:IsShown() == true)

  -- Saving persists; closing the form (as the Save button does) restores browse.
  Picker.openAddPanel()
  Picker.nameBox:SetText("Sklep"); Picker.latBox:SetText("46.0"); Picker.lonBox:SetText("14.5")
  local sOk = Picker.saveManual(Picker.nameBox:GetText(), Picker.latBox:GetText(),
    Picker.lonBox:GetText(), "", false)
  Picker.closeAddPanel()
  check("save persists + form close restores browse",
    sOk == true and Picker.browse:IsShown() == true and Selection.findSaved(db, "Sklep") ~= nil)
end

-- ---- (fixture comparison wired in a later checkpoint) ---------------------

-- ---- Summary --------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
