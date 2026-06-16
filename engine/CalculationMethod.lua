-- CalculationMethod.lua
-- Port of adhan-js src/CalculationMethod.ts (batoulapps/adhan-js, MIT).
-- Phase 1 ships only Muslim World League (Fajr 18, Isha 17, +1 min Dhuhr).
-- Phase 3 adds the other methods. Pure Lua: no WoW globals.

local CalculationParameters = require("CalculationParameters")

local CalculationMethod = {}

function CalculationMethod.MuslimWorldLeague()
  local params = CalculationParameters.new("MuslimWorldLeague", 18, 17)
  params.methodAdjustments.dhuhr = 1
  return params
end

return CalculationMethod
