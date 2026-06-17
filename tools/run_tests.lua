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
check("fire plays a sound", WowMock.lastSound ~= nil)
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

-- ---- (fixture comparison wired in a later checkpoint) ---------------------

-- ---- Summary --------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
