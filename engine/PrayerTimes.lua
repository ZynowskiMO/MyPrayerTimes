-- PrayerTimes.lua
-- Port of adhan-js src/PrayerTimes.ts (batoulapps/adhan-js, MIT).
-- Assembles the six prayer times for a date and location: raw solar times,
-- the high-latitude safe-value rule (resolves the summer Fajr/Isha clamp),
-- per-prayer adjustments (incl. MWL's +1 min Dhuhr), and rounding to the
-- nearest minute. Times are returned as minute-of-day in UTC [0, 1440); the
-- display layer converts to local time. Pure Lua: no WoW globals.

local SolarTime = require("SolarTime")
local Madhab = require("Madhab")

local floor = math.floor

local function isNaN(x) return x ~= x end

local function isLeapYear(y)
  return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

-- Calendar day increment, clock/timezone-free (mirrors dateByAddingDays).
local function nextDay(year, month, day)
  local dim = DAYS_IN_MONTH[month]
  if month == 2 and isLeapYear(year) then dim = 29 end
  day = day + 1
  if day > dim then
    day = 1
    month = month + 1
    if month > 12 then month = 1; year = year + 1 end
  end
  return year, month, day
end

-- Fractional UTC hours (+ whole-minute adjustment) -> minute-of-day [0,1440),
-- with the rounding mode from adhan-js DateUtils.roundedMinute:
--   "nearest" (default) -- round half up at 30s; seconds>=30 <=> frac>=0.5,
--                          the exact same boundary as floor(x + 0.5).
--   "up"                -- advance to the next minute boundary (Singapore).
--   "none"              -- truncate to the minute.
-- Returns nil for a non-finite time (e.g. polar latitudes where the sun never
-- crosses the horizon) so callers can fail safe instead of storing NaN.
local function toMinuteOfDay(hours, adjustmentMinutes, rounding)
  if hours ~= hours or hours == math.huge or hours == -math.huge then
    return nil
  end
  local m = hours * 60 + adjustmentMinutes
  local whole = floor(m)
  local seconds = (m - whole) * 60 -- [0, 60)
  local delta
  if rounding == "up" then
    delta = 1
  elseif rounding == "none" then
    delta = 0
  else -- "nearest"
    delta = (seconds >= 30) and 1 or 0
  end
  return (whole + delta) % 1440
end

local PrayerTimes = {}
PrayerTimes.__index = PrayerTimes

-- coordinates: { latitude, longitude }. params: a CalculationParameters table.
function PrayerTimes.new(year, month, day, coordinates, params)
  local self = setmetatable({}, PrayerTimes)

  local solarTime = SolarTime.new(year, month, day, coordinates)
  local transit = solarTime.transit
  local sunrise = solarTime.sunrise
  local sunset = solarTime.sunset
  local asr = solarTime:afternoon(Madhab.shadowLength(params.madhab))

  -- night (hours) from today's sunset to tomorrow's sunrise.
  local ny, nm, nd = nextDay(year, month, day)
  local tomorrowSunrise = SolarTime.new(ny, nm, nd, coordinates).sunrise
  local night = (24 + tomorrowSunrise) - sunset

  local portions = params:nightPortions()

  -- Fajr: fall back to the safe (later) value when the angle is unreached.
  local fajr = solarTime:hourAngle(-1 * params.fajrAngle, false)
  local safeFajr = sunrise - portions.fajr * night
  if isNaN(fajr) or safeFajr > fajr then fajr = safeFajr end

  -- Isha: interval-based, or angle-based with a safe (earlier) fallback.
  local isha
  if params.ishaInterval > 0 then
    isha = sunset + params.ishaInterval / 60
  else
    isha = solarTime:hourAngle(-1 * params.ishaAngle, true)
    local safeIsha = sunset + portions.isha * night
    if isNaN(isha) or safeIsha < isha then isha = safeIsha end
  end

  -- Maghrib is sunset, unless the method defines a Maghrib twilight angle
  -- (Tehran, 4.5 deg): then use the angle-based time when it falls strictly
  -- after sunset and before Isha. NaN at high latitudes (angle unreached) fails
  -- both comparisons, so Maghrib correctly stays at sunset.
  local maghrib = sunset
  if params.maghribAngle and params.maghribAngle > 0 then
    local angleBasedMaghrib = solarTime:hourAngle(-1 * params.maghribAngle, true)
    if sunset < angleBasedMaghrib and isha > angleBasedMaghrib then
      maghrib = angleBasedMaghrib
    end
  end

  local adj = params.adjustments
  local madj = params.methodAdjustments
  local function totalAdjustment(prayer)
    return (adj[prayer] or 0) + (madj[prayer] or 0)
  end

  local rounding = params.rounding
  self.fajr = toMinuteOfDay(fajr, totalAdjustment("fajr"), rounding)
  self.sunrise = toMinuteOfDay(sunrise, totalAdjustment("sunrise"), rounding)
  self.dhuhr = toMinuteOfDay(transit, totalAdjustment("dhuhr"), rounding)
  self.asr = toMinuteOfDay(asr, totalAdjustment("asr"), rounding)
  self.maghrib = toMinuteOfDay(maghrib, totalAdjustment("maghrib"), rounding)
  self.isha = toMinuteOfDay(isha, totalAdjustment("isha"), rounding)

  return self
end

if PrayerTimesNS then PrayerTimesNS.modules.PrayerTimes = PrayerTimes end
return PrayerTimes
