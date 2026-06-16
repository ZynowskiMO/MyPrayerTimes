-- Astronomical.lua
-- Direct port of adhan-js src/Astronomical.ts (batoulapps/adhan-js, MIT).
-- Meeus "Astronomical Algorithms" solar math. This checkpoint covers the
-- Julian Day conversion and the solar-longitude cluster; transit, hour angle
-- and the rest of Astronomical.ts arrive in later checkpoints.
-- Pure Lua: no WoW globals, so it runs identically in LuaJIT and in-game.

local MathUtils = require("MathUtils")
local degreesToRadians = MathUtils.degreesToRadians
local unwindAngle = MathUtils.unwindAngle

local sin = math.sin
local floor = math.floor
local ceil = math.ceil

-- JavaScript Math.trunc: truncate toward zero (Lua 5.1 has no math.trunc).
local function trunc(x)
  if x < 0 then return ceil(x) else return floor(x) end
end

local A = {}

function A.julianDay(year, month, day, hours)
  hours = hours or 0
  local Y = trunc(month > 2 and year or year - 1)
  local M = trunc(month > 2 and month or month + 12)
  local D = day + hours / 24
  local a = trunc(Y / 100)
  local B = trunc(2 - a + trunc(a / 4))
  local i0 = trunc(365.25 * (Y + 4716))
  local i1 = trunc(30.6001 * (M + 1))
  return i0 + i1 + D + B - 1524.5
end

function A.julianCentury(julianDay)
  return (julianDay - 2451545.0) / 36525
end

function A.meanSolarLongitude(julianCentury)
  local T = julianCentury
  local L0 = 280.4664567 + 36000.76983 * T + 0.0003032 * (T * T)
  return unwindAngle(L0)
end

function A.meanLunarLongitude(julianCentury)
  local T = julianCentury
  local Lp = 218.3165 + 481267.8813 * T
  return unwindAngle(Lp)
end

function A.meanSolarAnomaly(julianCentury)
  local T = julianCentury
  -- Astronomical Algorithms page 163
  local M = 357.52911 + 35999.05029 * T - 0.0001537 * (T * T)
  return unwindAngle(M)
end

function A.solarEquationOfTheCenter(julianCentury, meanAnomaly)
  local T = julianCentury
  -- Astronomical Algorithms page 164
  local Mrad = degreesToRadians(meanAnomaly)
  local term1 = (1.914602 - 0.004817 * T - 0.000014 * (T * T)) * sin(Mrad)
  local term2 = (0.019993 - 0.000101 * T) * sin(2 * Mrad)
  local term3 = 0.000289 * sin(3 * Mrad)
  return term1 + term2 + term3
end

function A.apparentSolarLongitude(julianCentury, meanLongitude)
  local T = julianCentury
  local L0 = meanLongitude
  local longitude = L0 + A.solarEquationOfTheCenter(T, A.meanSolarAnomaly(T))
  local Omega = 125.04 - 1934.136 * T
  local Lambda = longitude - 0.00569 - 0.00478 * sin(degreesToRadians(Omega))
  return unwindAngle(Lambda)
end

function A.meanSiderealTime(julianCentury)
  local T = julianCentury
  local JD = T * 36525 + 2451545.0
  local term1 = 280.46061837
  local term2 = 360.98564736629 * (JD - 2451545)
  local term3 = 0.000387933 * (T * T)
  local term4 = (T * T * T) / 38710000
  local Theta = term1 + term2 + term3 - term4
  return unwindAngle(Theta)
end

return A
