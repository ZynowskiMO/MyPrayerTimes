-- SolarCoordinates.lua
-- Direct port of adhan-js src/SolarCoordinates.ts (batoulapps/adhan-js, MIT).
-- Given a Julian Day, computes the Sun's declination, right ascension, and
-- apparent sidereal time (Astronomical Algorithms pp. 88, 165).
-- adhan-js models this as a class; in Lua, new(julianDay) returns a table
-- with fields declination, rightAscension, apparentSiderealTime.
-- Pure Lua: no WoW globals.

local MathUtils = require("MathUtils")
local Astronomical = require("Astronomical")
local degreesToRadians = MathUtils.degreesToRadians
local radiansToDegrees = MathUtils.radiansToDegrees
local unwindAngle = MathUtils.unwindAngle

local sin = math.sin
local cos = math.cos
local asin = math.asin
local atan2 = math.atan2 -- Lua 5.1 / LuaJIT

local SolarCoordinates = {}

function SolarCoordinates.new(julianDay)
  local T = Astronomical.julianCentury(julianDay)
  local L0 = Astronomical.meanSolarLongitude(T)
  local Lp = Astronomical.meanLunarLongitude(T)
  local Omega = Astronomical.ascendingLunarNodeLongitude(T)
  local Lambda = degreesToRadians(Astronomical.apparentSolarLongitude(T, L0))
  local Theta0 = Astronomical.meanSiderealTime(T)
  local dPsi = Astronomical.nutationInLongitude(T, L0, Lp, Omega)
  local dEpsilon = Astronomical.nutationInObliquity(T, L0, Lp, Omega)
  local Epsilon0 = Astronomical.meanObliquityOfTheEcliptic(T)
  local EpsilonApparent =
    degreesToRadians(Astronomical.apparentObliquityOfTheEcliptic(T, Epsilon0))

  -- Astronomical Algorithms page 165
  local declination = radiansToDegrees(asin(sin(EpsilonApparent) * sin(Lambda)))

  -- Astronomical Algorithms page 165
  local rightAscension = unwindAngle(
    radiansToDegrees(atan2(cos(EpsilonApparent) * sin(Lambda), cos(Lambda)))
  )

  -- Astronomical Algorithms page 88
  local apparentSiderealTime =
    Theta0 + (dPsi * 3600 * cos(degreesToRadians(Epsilon0 + dEpsilon))) / 3600

  return {
    declination = declination,
    rightAscension = rightAscension,
    apparentSiderealTime = apparentSiderealTime,
  }
end

return SolarCoordinates
