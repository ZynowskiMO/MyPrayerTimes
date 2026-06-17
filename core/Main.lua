-- core/Main.lua
-- WoW-only entry point for 2c-1: proves the whole engine + cities + timezone
-- stack runs inside WoW by printing the default city's six times to chat on
-- login. The real display window arrives in 2c-2.
-- NOTE: this uses the player's local calendar date as a temporary stand-in;
-- the city-local "today" helper (correct for eastern cities after midnight)
-- is built in 2c-2.

local Cities = require("Cities")

local PRAYERS = { "fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha" }
local DEFAULT_CITY = "Rotterdam" -- temporary hardcoded default for 2c

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  local t = date("*t") -- player-local date (temporary; see note above)
  local res = Cities.times(DEFAULT_CITY, t.year, t.month, t.day)
  print(string.format("|cff33ff99PrayerTimes|r loaded - %s %04d-%02d-%02d:",
    DEFAULT_CITY, t.year, t.month, t.day))
  if res then
    for _, p in ipairs(PRAYERS) do
      print(string.format("  %-8s %s", p, res.prayers[p].hhmm))
    end
  else
    print("  |cffff5555error:|r default city not found")
  end
end)
