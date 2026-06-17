-- Schedule.lua
-- Pure next-prayer logic (no WoW API, clock injected as an argument so the
-- runner can drive it). Given today's six times as local minute-of-day and
-- the current local minute-of-day, returns the ordered list (each flagged
-- isNext), the next prayer's key, and minutes until it -- wrapping to
-- tomorrow's Fajr after the last time of the day.

local Schedule = {}

local ORDER = { "fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha" }
Schedule.ORDER = ORDER

-- times: { fajr=minOfDay, sunrise=..., ... }; nowMin: 0..1439
function Schedule.compute(times, nowMin)
  local nextKey, nextMin
  for _, key in ipairs(ORDER) do
    if times[key] > nowMin then
      nextKey, nextMin = key, times[key]
      break
    end
  end

  local untilMinutes
  if nextKey then
    untilMinutes = nextMin - nowMin
  else
    -- Past the day's last time -> next is tomorrow's Fajr.
    nextKey, nextMin = "fajr", times.fajr
    untilMinutes = (1440 - nowMin) + times.fajr
  end

  local order = {}
  for i, key in ipairs(ORDER) do
    order[i] = { key = key, minuteOfDay = times[key], isNext = (key == nextKey) }
  end

  return { order = order, nextKey = nextKey, nextMin = nextMin, untilMinutes = untilMinutes }
end

if PrayerTimesNS then PrayerTimesNS.modules.Schedule = Schedule end
return Schedule
