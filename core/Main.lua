-- core/Main.lua
-- WoW-only entry point. On login it builds the display window (2c-2). The
-- window itself reads the clock via Clock.cityNow, so the schedule reflects
-- the selected city's own "today".

local Window = require("Window")
local Picker = require("Picker")
local Wizard = require("Wizard")
local Selection = require("Selection")

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  PrayerTimesDB = PrayerTimesDB or {}
  Window.init(PrayerTimesDB)
  Picker.init(PrayerTimesDB)
  Wizard.init(PrayerTimesDB)
  Window.create()
  if Wizard.shouldOpen(PrayerTimesDB) then
    Wizard.open() -- first run: guided welcome wizard (ADR-0006)
    print("|cff33ff99PrayerTimes|r: welcome! Let's get you set up.")
  else
    print("|cff33ff99PrayerTimes|r loaded. |cffffd100/pt settings|r to change city.")
  end
end)

-- Slash commands.
SLASH_PRAYERTIMES1 = "/pt"
SLASH_PRAYERTIMES2 = "/prayertimes"
SlashCmdList["PRAYERTIMES"] = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()

  if cmd == "" or cmd == "help" then
    print("|cff33ff99PrayerTimes|r commands:")
    print("  |cffffd100/pt show|r / |cffffd100hide|r - show or hide the window")
    print("  |cffffd100/pt lock|r / |cffffd100unlock|r - lock or free its position")
    print("  |cffffd100/pt settings|r - open the city / settings window")
    print("  |cffffd100/pt setup|r - run the welcome wizard again")
    print("  |cffffd100/pt city <name>|r - select a city by name")
    print("  |cffffd100/pt test|r - preview a notification")
  elseif cmd == "show" then
    if Window.frame then Window.frame:Show() end
  elseif cmd == "hide" then
    if Window.frame then Window.frame:Hide() end
  elseif cmd == "lock" then
    Window.setLocked(true); print("|cff33ff99PrayerTimes|r: window locked")
  elseif cmd == "unlock" then
    Window.setLocked(false); print("|cff33ff99PrayerTimes|r: window unlocked")
  elseif cmd == "settings" or cmd == "config" or cmd == "options" then
    Picker.toggle()
  elseif cmd == "welcome" or cmd == "setup" then
    Wizard.open() -- re-run the welcome/setup wizard on demand
  elseif cmd == "city" then
    if rest == "" then
      Picker.open()
    else
      local matched = Picker.selectCityByName(rest)
      if matched then
        print("|cff33ff99PrayerTimes|r: city set to " .. matched)
      else
        print("|cffff5555PrayerTimes|r: unknown city '" .. rest .. "' - try /pt settings")
      end
    end
  elseif cmd == "test" then
    Window.testNotification()
  else
    print("|cffff5555PrayerTimes|r: unknown command - try |cffffd100/pt help|r")
  end
end
