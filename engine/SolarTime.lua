-- SolarTime.lua
-- Direct port of adhan-js src/SolarTime.ts (batoulapps/adhan-js, MIT).
-- For a given date (year/month/day) and coordinates, computes the solar
-- transit (Dhuhr), sunrise, and sunset as fractional hours in UTC, plus the
-- hourAngle/afternoon helpers used to derive Fajr, Isha, and Asr.
-- adhan-js takes a JS Date; the Lua port takes explicit y/m/d so the engine
-- stays free of any clock/timezone dependency. Pure Lua: no WoW globals.

local Astronomical = require("Astronomical")
local MathUtils = require("MathUtils")
local degreesToRadians = MathUtils.degreesToRadians
local radiansToDegrees = MathUtils.radiansToDegrees

local abs = math.abs
local tan = math.tan
local atan = math.atan

local SolarTime = {}
SolarTime.__index = SolarTime

-- coordinates is a table { latitude = ..., longitude = ... }.
function SolarTime.new(year, month, day, coordinates)
  local self = setmetatable({}, SolarTime)

  local julianDay = Astronomical.julianDay(year, month, day, 0)

  self.observer = coordinates
  self.solar = require("SolarCoordinates").new(julianDay)
  self.prevSolar = require("SolarCoordinates").new(julianDay - 1)
  self.nextSolar = require("SolarCoordinates").new(julianDay + 1)

  local m0 = Astronomical.approximateTransit(
    coordinates.longitude, self.solar.apparentSiderealTime, self.solar.rightAscension)
  local solarAltitude = -50.0 / 60.0

  self.approxTransit = m0

  self.transit = Astronomical.correctedTransit(
    m0, coordinates.longitude, self.solar.apparentSiderealTime,
    self.solar.rightAscension, self.prevSolar.rightAscension, self.nextSolar.rightAscension)

  self.sunrise = Astronomical.correctedHourAngle(
    m0, solarAltitude, coordinates, false, self.solar.apparentSiderealTime,
    self.solar.rightAscension, self.prevSolar.rightAscension, self.nextSolar.rightAscension,
    self.solar.declination, self.prevSolar.declination, self.nextSolar.declination)

  self.sunset = Astronomical.correctedHourAngle(
    m0, solarAltitude, coordinates, true, self.solar.apparentSiderealTime,
    self.solar.rightAscension, self.prevSolar.rightAscension, self.nextSolar.rightAscension,
    self.solar.declination, self.prevSolar.declination, self.nextSolar.declination)

  return self
end

function SolarTime:hourAngle(angle, afterTransit)
  return Astronomical.correctedHourAngle(
    self.approxTransit, angle, self.observer, afterTransit,
    self.solar.apparentSiderealTime, self.solar.rightAscension,
    self.prevSolar.rightAscension, self.nextSolar.rightAscension,
    self.solar.declination, self.prevSolar.declination, self.nextSolar.declination)
end

function SolarTime:afternoon(shadowLength)
  local tangent = abs(self.observer.latitude - self.solar.declination)
  local inverse = shadowLength + tan(degreesToRadians(tangent))
  local angle = radiansToDegrees(atan(1.0 / inverse))
  return self:hourAngle(angle, true)
end

return SolarTime
