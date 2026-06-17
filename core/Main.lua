-- core/Main.lua
-- WoW-only entry point. On login it builds the display window (2c-2). The
-- window itself reads the clock via Clock.cityNow, so the schedule reflects
-- the selected city's own "today".

local Window = require("Window")
local Picker = require("Picker")
local Selection = require("Selection")

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  PrayerTimesDB = PrayerTimesDB or {}
  Window.init(PrayerTimesDB)
  Picker.init(PrayerTimesDB)
  Window.create()
  if Picker.shouldAutoOpen(PrayerTimesDB) then
    Picker.open() -- first run: welcome / choose a city
    print("|cff33ff99PrayerTimes|r: choose your city.")
  else
    print("|cff33ff99PrayerTimes|r loaded. |cffffd100/pt settings|r to change city.")
  end
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
  elseif msg == "test" then
    Window.testNotification()
  elseif msg == "settings" or msg == "city" then
    Picker.toggle()
  else
    Window.toggleLock()
    print("PrayerTimes: window " .. (PrayerTimesDB.locked and "locked" or "unlocked"))
  end
end
