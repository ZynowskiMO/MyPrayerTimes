-- Notifier.lua
-- Pure notification trigger logic (no WoW API; clock injected). Decides which
-- prayer alerts should fire "now" for the FIVE prayers (Sunrise excluded).
-- Two alert types per prayer, each with an eligibility window:
--   before : [prayer - beforeMinutes, prayer)   -- fires through the lead-up,
--            so a mid-window login fires it once; logging in at/after the
--            prayer skips it (the at-alert covers "it's time").
--   at     : [prayer, prayer + 1)               -- the prayer's own minute;
--            a same-minute login fires it, a later login skips the stale one.
-- Dedupe is keyed by (dayKey, prayer, type) in a `fired` table the caller
-- PERSISTS (SavedVariables), so a /reload mid-window does not re-fire and the
-- at-alert never double-fires after the before-alert.

local Notifier = {}

local PRAYERS = { "fajr", "dhuhr", "asr", "maghrib", "isha" } -- no sunrise
Notifier.PRAYERS = PRAYERS

local function firedKey(dayKey, prayer, atype)
  return dayKey .. ":" .. prayer .. ":" .. atype
end

-- times:    { fajr=min, dhuhr=min, asr=min, maghrib=min, isha=min } local m-o-d
-- nowMin:   current local minute-of-day
-- settings: { beforeMinutes = N (0 = off), atTime = bool }
-- dayKey:   string identifying the local day (dedupe scope)
-- fired:    persisted dedupe set (mutated in place)
-- returns a list of { prayer, type, prayerMin, minutesUntil }.
function Notifier.check(times, nowMin, settings, dayKey, fired)
  local out = {}
  local beforeMinutes = settings.beforeMinutes or 0

  local function tryFire(prayer, atype, windowStart, windowEnd, minutesUntil, prayerMin)
    if nowMin >= windowStart and nowMin < windowEnd then
      local key = firedKey(dayKey, prayer, atype)
      if not fired[key] then
        fired[key] = true
        out[#out + 1] = { prayer = prayer, type = atype,
          prayerMin = prayerMin, minutesUntil = minutesUntil }
      end
    end
  end

  for _, prayer in ipairs(PRAYERS) do
    local pm = times[prayer]
    if pm then
      if beforeMinutes > 0 then
        local start = pm - beforeMinutes
        if start < 0 then start = 0 end
        tryFire(prayer, "before", start, pm, pm - nowMin, pm)
      end
      if settings.atTime then
        tryFire(prayer, "at", pm, pm + 1, 0, pm)
      end
    end
  end

  return out
end

-- Drop dedupe keys not belonging to the current day (call on day rollover so
-- the persisted set does not grow unbounded).
function Notifier.pruneFired(fired, dayKey)
  local prefix = dayKey .. ":"
  for key in pairs(fired) do
    if key:sub(1, #prefix) ~= prefix then fired[key] = nil end
  end
end

if PrayerTimesNS then PrayerTimesNS.modules.Notifier = Notifier end
return Notifier
