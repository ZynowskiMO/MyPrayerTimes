-- core/Main.lua
-- WoW-only entry point. On login it builds the display window (2c-2). The
-- window itself reads the clock via Clock.cityNow, so the schedule reflects
-- the selected city's own "today".

local Window = require("Window")

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  PrayerTimesDB = PrayerTimesDB or {}
  Window.init(PrayerTimesDB)
  Window.create()
  print("|cff33ff99PrayerTimes|r loaded. Drag to move; |cffffd100/pt lock|r to lock.")
end)

-- Temporary slash scaffold for 2c testing; the full command set is 2d.
SLASH_PRAYERTIMES1 = "/pt"
SlashCmdList["PRAYERTIMES"] = function(msg)
  msg = (msg or ""):lower():gsub("%s+", "")
  if msg == "lock" then
    Window.setLocked(true); print("PrayerTimes: window locked")
  elseif msg == "unlock" then
    Window.setLocked(false); print("PrayerTimes: window unlocked")
  elseif msg == "show" then
    if Window.frame then Window.frame:Show() end
  elseif msg == "hide" then
    if Window.frame then Window.frame:Hide() end
  else
    Window.toggleLock()
    print("PrayerTimes: window " .. (PrayerTimesDB.locked and "locked" or "unlocked"))
  end
end
