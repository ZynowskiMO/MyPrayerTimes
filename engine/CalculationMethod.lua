-- CalculationMethod.lua
-- Port of adhan-js src/CalculationMethod.ts (batoulapps/adhan-js, MIT).
-- Each factory returns a CalculationParameters table, ported VERBATIM from
-- adhan-js 4.4.4 -- angles, intervals, and method adjustments are copied, never
-- invented or tuned. Phase 3 exposes the full adhan-js method set EXCEPT
-- MoonsightingCommittee, which is a seasonal/latitude-dependent algorithm with
-- its own shafaq logic (deferred to a future ADR, see ADR-0004).
--
-- Two parameters here are inert until Phase 3-3 wires them into PrayerTimes:
--   Tehran's maghribAngle (Maghrib by twilight angle, not plain sunset), and
--   Singapore's rounding = "up". They are carried now so the ports are
--   faithful; behaviour is unchanged until 3-3. Pure Lua: no WoW globals.

local CalculationParameters = require("CalculationParameters")

local CalculationMethod = {}

-- Muslim World League
function CalculationMethod.MuslimWorldLeague()
  local params = CalculationParameters.new("MuslimWorldLeague", 18, 17)
  params.methodAdjustments.dhuhr = 1
  return params
end

-- Egyptian General Authority of Survey
function CalculationMethod.Egyptian()
  local params = CalculationParameters.new("Egyptian", 19.5, 17.5)
  params.methodAdjustments.dhuhr = 1
  return params
end

-- University of Islamic Sciences, Karachi
function CalculationMethod.Karachi()
  local params = CalculationParameters.new("Karachi", 18, 18)
  params.methodAdjustments.dhuhr = 1
  return params
end

-- Umm al-Qura University, Makkah (90-minute Isha interval, no Isha angle)
function CalculationMethod.UmmAlQura()
  return CalculationParameters.new("UmmAlQura", 18.5, 0, 90)
end

-- Dubai
function CalculationMethod.Dubai()
  local params = CalculationParameters.new("Dubai", 18.2, 18.2)
  params.methodAdjustments.sunrise = -3
  params.methodAdjustments.dhuhr = 3
  params.methodAdjustments.asr = 3
  params.methodAdjustments.maghrib = 3
  return params
end

-- ISNA (Islamic Society of North America)
function CalculationMethod.NorthAmerica()
  local params = CalculationParameters.new("NorthAmerica", 15, 15)
  params.methodAdjustments.dhuhr = 1
  return params
end

-- Kuwait
function CalculationMethod.Kuwait()
  return CalculationParameters.new("Kuwait", 18, 17.5)
end

-- Qatar (90-minute Isha interval, no Isha angle)
function CalculationMethod.Qatar()
  return CalculationParameters.new("Qatar", 18, 0, 90)
end

-- Singapore (rounds prayer minutes up; consumed in 3-3)
function CalculationMethod.Singapore()
  local params = CalculationParameters.new("Singapore", 20, 18)
  params.methodAdjustments.dhuhr = 1
  params.rounding = "up"
  return params
end

-- Institute of Geophysics, University of Tehran (Maghrib by 4.5 deg angle)
function CalculationMethod.Tehran()
  return CalculationParameters.new("Tehran", 17.7, 14, 0, 4.5)
end

-- Diyanet (Turkey)
function CalculationMethod.Turkey()
  local params = CalculationParameters.new("Turkey", 18, 17)
  params.methodAdjustments.sunrise = -7
  params.methodAdjustments.dhuhr = 5
  params.methodAdjustments.asr = 4
  params.methodAdjustments.maghrib = 7
  return params
end

-- Other (zero angles -- advanced/manual baseline)
function CalculationMethod.Other()
  return CalculationParameters.new("Other", 0, 0)
end

if PrayerTimesNS then PrayerTimesNS.modules.CalculationMethod = CalculationMethod end
return CalculationMethod
