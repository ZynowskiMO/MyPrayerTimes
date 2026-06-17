-- Calculator.lua
-- Application layer (not part of the adhan-js port). Computes prayer times for
-- a location with sensible defaults, the key one being the high-latitude rule:
-- when the caller does not specify a rule, it defaults to
-- HighLatitudeRule.recommended(coordinates) instead of the engine's bare
-- MiddleOfTheNight default. This is what gives high-latitude cities usable
-- summer Fajr/Isha instead of the midnight clamp.
-- The rule stays overridable via opts.highLatitudeRule (Phase 3 settings).
-- Pure Lua: no WoW globals.

local CalculationMethod = require("CalculationMethod")
local HighLatitudeRule = require("HighLatitudeRule")
local PrayerTimes = require("PrayerTimes")

local Calculator = {}

-- coordinates: { latitude, longitude }
-- opts (all optional):
--   params            a CalculationParameters table (default: MWL)
--   highLatitudeRule  explicit rule override (default: recommended(coords))
function Calculator.timesForLocation(year, month, day, coordinates, opts)
  opts = opts or {}
  local params = opts.params or CalculationMethod.MuslimWorldLeague()
  if opts.highLatitudeRule ~= nil then
    params.highLatitudeRule = opts.highLatitudeRule
  else
    params.highLatitudeRule = HighLatitudeRule.recommended(coordinates)
  end
  return PrayerTimes.new(year, month, day, coordinates, params)
end

return Calculator
