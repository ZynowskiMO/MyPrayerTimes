-- Astronomical.lua
-- Direct port of adhan-js src/Astronomical.ts (batoulapps/adhan-js, MIT).
-- Meeus "Astronomical Algorithms" solar math. This checkpoint covers the
-- Julian Day conversion and the solar-longitude cluster; transit, hour angle
-- and the rest of Astronomical.ts arrive in later checkpoints.
-- Pure Lua: no WoW globals, so it runs identically in LuaJIT and in-game.

local MathUtils = require("MathUtils")
local degreesToRadians = MathUtils.degreesToRadians
local radiansToDegrees = MathUtils.radiansToDegrees
local unwindAngle = MathUtils.unwindAngle
local normalizeToScale = MathUtils.normalizeToScale
local quadrantShiftAngle = MathUtils.quadrantShiftAngle

local sin = math.sin
local cos = math.cos
local asin = math.asin
local acos = math.acos
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

function A.ascendingLunarNodeLongitude(julianCentury)
  local T = julianCentury
  local term1 = 125.04452
  local term2 = 1934.136261 * T
  local term3 = 0.0020708 * (T * T)
  local term4 = (T * T * T) / 450000
  local Omega = term1 - term2 + term3 + term4
  return unwindAngle(Omega)
end

function A.meanObliquityOfTheEcliptic(julianCentury)
  local T = julianCentury
  local term1 = 23.439291
  local term2 = 0.013004167 * T
  local term3 = 0.0000001639 * (T * T)
  local term4 = 0.0000005036 * (T * T * T)
  return term1 - term2 - term3 + term4
end

function A.apparentObliquityOfTheEcliptic(julianCentury, meanObliquityOfTheEcliptic)
  local T = julianCentury
  local Epsilon0 = meanObliquityOfTheEcliptic
  local O = 125.04 - 1934.136 * T
  return Epsilon0 + 0.00256 * cos(degreesToRadians(O))
end

function A.nutationInLongitude(julianCentury, solarLongitude, lunarLongitude, ascendingNode)
  local L0 = solarLongitude
  local Lp = lunarLongitude
  local Omega = ascendingNode
  local term1 = (-17.2 / 3600) * sin(degreesToRadians(Omega))
  local term2 = (1.32 / 3600) * sin(2 * degreesToRadians(L0))
  local term3 = (0.23 / 3600) * sin(2 * degreesToRadians(Lp))
  local term4 = (0.21 / 3600) * sin(2 * degreesToRadians(Omega))
  return term1 - term2 - term3 + term4
end

function A.nutationInObliquity(julianCentury, solarLongitude, lunarLongitude, ascendingNode)
  local L0 = solarLongitude
  local Lp = lunarLongitude
  local Omega = ascendingNode
  local term1 = (9.2 / 3600) * cos(degreesToRadians(Omega))
  local term2 = (0.57 / 3600) * cos(2 * degreesToRadians(L0))
  local term3 = (0.1 / 3600) * cos(2 * degreesToRadians(Lp))
  local term4 = (0.09 / 3600) * cos(2 * degreesToRadians(Omega))
  return term1 + term2 + term3 - term4
end

function A.altitudeOfCelestialBody(observerLatitude, declination, localHourAngle)
  local Phi = observerLatitude
  local delta = declination
  local H = localHourAngle
  -- Astronomical Algorithms page 93
  local term1 = sin(degreesToRadians(Phi)) * sin(degreesToRadians(delta))
  local term2 = cos(degreesToRadians(Phi)) * cos(degreesToRadians(delta))
    * cos(degreesToRadians(H))
  return radiansToDegrees(asin(term1 + term2))
end

function A.approximateTransit(longitude, siderealTime, rightAscension)
  local L = longitude
  local Theta0 = siderealTime
  local a2 = rightAscension
  local Lw = L * -1
  local m0 = normalizeToScale((a2 + Lw - Theta0) / 360, 1)
  local expectedTransit = normalizeToScale((12.0 - L / 15.0) / 24.0, 1)
  if m0 - expectedTransit > 0.5 then
    return m0 - 1.0
  elseif expectedTransit - m0 > 0.5 then
    return m0 + 1.0
  else
    return m0
  end
end

function A.correctedTransit(approximateTransit, longitude, siderealTime,
                            rightAscension, previousRightAscension, nextRightAscension)
  local m0 = approximateTransit
  local L = longitude
  local Theta0 = siderealTime
  local a2 = rightAscension
  local a1 = previousRightAscension
  local a3 = nextRightAscension
  local Lw = L * -1
  local Theta = unwindAngle(Theta0 + 360.985647 * m0)
  local a = unwindAngle(A.interpolateAngles(a2, a1, a3, m0))
  local H = quadrantShiftAngle(Theta - Lw - a)
  local dm = H / -360
  return (m0 + dm) * 24
end

function A.correctedHourAngle(approximateTransit, angle, coordinates, afterTransit,
                              siderealTime, rightAscension, previousRightAscension,
                              nextRightAscension, declination, previousDeclination,
                              nextDeclination)
  local m0 = approximateTransit
  local h0 = angle
  local Theta0 = siderealTime
  local a2 = rightAscension
  local a1 = previousRightAscension
  local a3 = nextRightAscension
  local d2 = declination
  local d1 = previousDeclination
  local d3 = nextDeclination
  local Lw = coordinates.longitude * -1
  local term1 = sin(degreesToRadians(h0))
    - sin(degreesToRadians(coordinates.latitude)) * sin(degreesToRadians(d2))
  local term2 = cos(degreesToRadians(coordinates.latitude)) * cos(degreesToRadians(d2))
  local H0 = radiansToDegrees(acos(term1 / term2))
  local m = afterTransit and (m0 + H0 / 360) or (m0 - H0 / 360)
  local Theta = unwindAngle(Theta0 + 360.985647 * m)
  local a = unwindAngle(A.interpolateAngles(a2, a1, a3, m))
  local delta = A.interpolate(d2, d1, d3, m)
  local H = Theta - Lw - a
  local h = A.altitudeOfCelestialBody(coordinates.latitude, delta, H)
  local term3 = h - h0
  local term4 = 360 * cos(degreesToRadians(delta))
    * cos(degreesToRadians(coordinates.latitude)) * sin(degreesToRadians(H))
  local dm = term3 / term4
  return (m + dm) * 24
end

function A.interpolate(y2, y1, y3, n)
  local a = y2 - y1
  local b = y3 - y2
  local c = b - a
  return y2 + (n / 2) * (a + b + n * c)
end

function A.interpolateAngles(y2, y1, y3, n)
  local a = unwindAngle(y2 - y1)
  local b = unwindAngle(y3 - y2)
  local c = b - a
  return y2 + (n / 2) * (a + b + n * c)
end

if PrayerTimesNS then PrayerTimesNS.modules.Astronomical = A end
return A
