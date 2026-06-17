-- Clock.lua
-- Pure clock helper: turn a UTC epoch (seconds) into the SELECTED CITY's local
-- calendar date and minute-of-day, so an eastern city after midnight shows its
-- own day, not the player's. Epoch is injected (the UI passes GetServerTime()),
-- keeping this runner-testable. Uses Timezone for the per-city offset/DST.

local Timezone = require("Timezone")

local floor = math.floor

local Clock = {}

-- Civil (Gregorian) date from a day number counted from 1970-01-01.
-- Howard Hinnant's algorithm; integer math, valid for any reasonable date.
function Clock.civilFromDays(z)
  z = z + 719468
  local era = floor((z >= 0 and z or (z - 146096)) / 146097)
  local doe = z - era * 146097
  local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
  local mp = floor((5 * doy + 2) / 153)
  local d = doy - floor((153 * mp + 2) / 5) + 1
  local m = (mp < 10) and (mp + 3) or (mp - 9)
  if m <= 2 then y = y + 1 end
  return y, m, d
end

-- City-local date + minute-of-day for a UTC epoch. Two passes so the DST
-- decision uses the correct local date near midnight / transition days.
function Clock.cityNow(city, epoch)
  local function partsFor(offsetMinutes)
    local localEpoch = epoch + offsetMinutes * 60
    local days = floor(localEpoch / 86400)
    local secOfDay = localEpoch - days * 86400
    local y, m, d = Clock.civilFromDays(days)
    return y, m, d, floor(secOfDay / 60)
  end

  local y, m, d = partsFor(city.baseUtcOffset)          -- provisional (no DST)
  local offset = Timezone.offsetMinutes(city, y, m, d)  -- real offset for that date
  local ly, lm, ld, lminute = partsFor(offset)
  return { year = ly, month = lm, day = ld, minuteOfDay = lminute, offsetMinutes = offset }
end

if PrayerTimesNS then PrayerTimesNS.modules.Clock = Clock end
return Clock
