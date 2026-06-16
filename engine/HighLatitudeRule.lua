-- HighLatitudeRule.lua
-- Port of adhan-js src/HighLatitudeRule.ts constants (batoulapps/adhan-js, MIT).
-- Phase 1 only needs the rule identifiers; the default (MiddleOfTheNight) is
-- what produces the summer Fajr/Isha midnight clamp. Phase 2 adds
-- recommended(coordinates), which picks SeventhOfTheNight above ~48N.
-- Pure Lua: no WoW globals.

local HighLatitudeRule = {
  MiddleOfTheNight = "middleofthenight",
  SeventhOfTheNight = "seventhofthenight",
  TwilightAngle = "twilightangle",
}

return HighLatitudeRule
