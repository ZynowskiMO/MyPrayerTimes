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

-- adhan-js: above 48N/S use SeventhOfTheNight, otherwise MiddleOfTheNight.
-- Threshold is strictly greater than 48 (latitude == 48 -> MiddleOfTheNight).
function HighLatitudeRule.recommended(coordinates)
  if coordinates.latitude > 48 then
    return HighLatitudeRule.SeventhOfTheNight
  else
    return HighLatitudeRule.MiddleOfTheNight
  end
end

return HighLatitudeRule
