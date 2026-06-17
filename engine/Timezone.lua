-- Timezone.lua
-- Display-layer timezone/DST conversion (ADR-0003). The engine stays UTC;
-- this converts a UTC minute-of-day to the SELECTED CITY's local time using a
-- per-city { baseUtcOffset (minutes), dstRule (named key) }. DST rules are an
-- extensible lookup table: v1.0 ships "none" (fixed offset) and "EU"
-- (last-Sunday-of-March..October, computed from the Julian-Day weekday).
-- Clock-free and WoW-independent: takes an explicit date.

local Astronomical = require("Astronomical")

local floor = math.floor

local function isLeapYear(y)
  return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function daysInMonth(year, month)
  if month == 2 and isLeapYear(year) then return 29 end
  return DAYS_IN_MONTH[month]
end

-- Day of week for a calendar date at 0h UT. 0 = Sunday .. 6 = Saturday
-- (Meeus, Astronomical Algorithms ch. 7: floor(JD + 1.5) mod 7).
local function weekday(year, month, day)
  local jd = Astronomical.julianDay(year, month, day, 0)
  return floor(jd + 1.5) % 7
end

local function lastSundayOfMonth(year, month)
  local last = daysInMonth(year, month)
  return last - weekday(year, month, last)
end

-- True when (month, day) >= (m, d) within the same year.
local function onOrAfter(month, day, m, d)
  return month > m or (month == m and day >= d)
end

-- DST rules table (ADR-0003). Each returns the DST adjustment in minutes.
local RULES = {
  none = function() return 0 end,
  -- EU: +60 from 01:00 UTC last Sunday of March to 01:00 UTC last Sunday of
  -- October. Date granularity: spring transition day counts as on, autumn day
  -- as off (exact for prayer times, which fall after 01:00 UTC near equinoxes).
  EU = function(year, month, day)
    local marDay = lastSundayOfMonth(year, 3)
    local octDay = lastSundayOfMonth(year, 10)
    local afterMarch = onOrAfter(month, day, 3, marDay)
    local beforeOctober = not onOrAfter(month, day, 10, octDay)
    if afterMarch and beforeOctober then return 60 else return 0 end
  end,
}

local Timezone = {}

Timezone.RULES = RULES

-- city: { baseUtcOffset = minutes, dstRule = "none"|"EU" }
function Timezone.offsetMinutes(city, year, month, day)
  local rule = RULES[city.dstRule]
  if not rule then error("Unknown dstRule: " .. tostring(city.dstRule)) end
  return city.baseUtcOffset + rule(year, month, day)
end

-- UTC minute-of-day -> local minute-of-day [0, 1440).
function Timezone.toLocalMinuteOfDay(utcMinuteOfDay, offsetMinutes)
  return (utcMinuteOfDay + offsetMinutes) % 1440
end

function Timezone.formatHHMM(minuteOfDay)
  -- Fail safe on non-finite input (NaN/Inf) rather than crashing on format.
  if type(minuteOfDay) ~= "number" or minuteOfDay ~= minuteOfDay
      or minuteOfDay == math.huge or minuteOfDay == -math.huge then
    return "--:--"
  end
  return string.format("%02d:%02d", floor(minuteOfDay / 60), minuteOfDay % 60)
end

if PrayerTimesNS then PrayerTimesNS.modules.Timezone = Timezone end
return Timezone
