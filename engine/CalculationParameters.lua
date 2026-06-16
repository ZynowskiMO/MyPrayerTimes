-- CalculationParameters.lua
-- Port of adhan-js src/CalculationParameters.ts (batoulapps/adhan-js, MIT).
-- Holds the method angles, Asr school, high-latitude rule, and adjustments,
-- and computes the night-portion fractions used for high-latitude safe times.
-- Defaults match adhan-js: Shafi madhab, MiddleOfTheNight rule, zero offsets.
-- Pure Lua: no WoW globals.

local Madhab = require("Madhab")
local HighLatitudeRule = require("HighLatitudeRule")

local CalculationParameters = {}
CalculationParameters.__index = CalculationParameters

function CalculationParameters.new(method, fajrAngle, ishaAngle, ishaInterval)
  local self = setmetatable({}, CalculationParameters)
  self.method = method or "Other"
  self.fajrAngle = fajrAngle or 0
  self.ishaAngle = ishaAngle or 0
  self.ishaInterval = ishaInterval or 0
  self.madhab = Madhab.Shafi
  self.highLatitudeRule = HighLatitudeRule.MiddleOfTheNight
  self.adjustments = { fajr = 0, sunrise = 0, dhuhr = 0, asr = 0, maghrib = 0, isha = 0 }
  self.methodAdjustments = { fajr = 0, sunrise = 0, dhuhr = 0, asr = 0, maghrib = 0, isha = 0 }
  return self
end

function CalculationParameters:nightPortions()
  local rule = self.highLatitudeRule
  if rule == HighLatitudeRule.MiddleOfTheNight then
    return { fajr = 1 / 2, isha = 1 / 2 }
  elseif rule == HighLatitudeRule.SeventhOfTheNight then
    return { fajr = 1 / 7, isha = 1 / 7 }
  elseif rule == HighLatitudeRule.TwilightAngle then
    return { fajr = self.fajrAngle / 60, isha = self.ishaAngle / 60 }
  else
    error("Invalid high latitude rule: " .. tostring(rule))
  end
end

return CalculationParameters
