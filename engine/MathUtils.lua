-- MathUtils.lua
-- Direct port of adhan-js src/MathUtils.ts (batoulapps/adhan-js, MIT).
-- Angle conversion and normalization helpers used by the solar math.
-- Pure Lua: no WoW globals, so it runs identically in LuaJIT and in-game.

local M = {}

local floor = math.floor
local pi = math.pi

function M.degreesToRadians(degrees)
  return (degrees * pi) / 180.0
end

function M.radiansToDegrees(radians)
  return (radians * 180.0) / pi
end

function M.normalizeToScale(num, max)
  return num - max * floor(num / max)
end

function M.unwindAngle(angle)
  return M.normalizeToScale(angle, 360.0)
end

-- JavaScript's Math.round() rounds half toward +Infinity. For every value
-- quadrantShiftAngle feeds it, floor(x + 0.5) reproduces that exactly
-- (e.g. -1.5 -> -1, 1.5 -> 2), so the port stays faithful to adhan-js.
local function jsRound(x)
  return floor(x + 0.5)
end

function M.quadrantShiftAngle(angle)
  if angle >= -180 and angle <= 180 then
    return angle
  end
  return angle - 360 * jsRound(angle / 360)
end

return M
