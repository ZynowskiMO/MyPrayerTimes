-- core/Main.lua
-- WoW-only entry point. On login it builds the display window (2c-2). The
-- window itself reads the clock via Clock.cityNow, so the schedule reflects
-- the selected city's own "today".

local Window = require("Window")

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  Window.create()
  print("|cff33ff99PrayerTimes|r loaded.")
end)
