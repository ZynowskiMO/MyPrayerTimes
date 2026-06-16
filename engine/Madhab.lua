-- Madhab.lua
-- Direct port of adhan-js src/Madhab.ts (batoulapps/adhan-js, MIT).
-- The Asr school selects the shadow-length factor used by SolarTime:afternoon:
-- Shafi (Standard) = 1, Hanafi = 2. Phase 1 uses Shafi only; Hanafi ships in
-- Phase 3. Pure Lua: no WoW globals.

local Madhab = {
  Shafi = "shafi",
  Hanafi = "hanafi",
}

function Madhab.shadowLength(madhab)
  if madhab == Madhab.Shafi then
    return 1
  elseif madhab == Madhab.Hanafi then
    return 2
  else
    error("Invalid Madhab: " .. tostring(madhab))
  end
end

return Madhab
