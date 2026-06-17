-- wow_load_check.lua
-- Emulates the WoW addon load path under luajit: reads PrayerTimes.toc and
-- loads each listed Lua file in order through the bootstrap require() shim,
-- with the WoW API mocked. Catches .toc order / module-bridge regressions
-- (which the require-based runner would not) before testing in-game.
-- Run from repo root:  luajit tools/wow_load_check.lua

local WowMock = dofile("tools/wow_mock.lua")
WowMock.install()
_G.date = os.date -- core/Main.lua uses date("*t")

-- Record created frames so we can fire PLAYER_LOGIN like WoW would.
local frames = {}
local baseCreate = _G.CreateFrame
_G.CreateFrame = function(...) local f = baseCreate(...); frames[#frames + 1] = f; return f end

-- Capture chat output from core/Main.lua.
local printed = {}
local realPrint = print
_G.print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

-- WoW has no require(); remove luajit's so bootstrap.lua installs the shim
-- (this is what makes the emulation faithful to the in-game environment).
_G.require = nil

local addonName, ns = "PrayerTimes", {}

-- Parse the .toc for .lua files (skip comments/blanks).
local files = {}
for line in io.lines("PrayerTimes.toc") do
  line = line:gsub("%s+$", "")
  if line ~= "" and not line:match("^#") and line:match("%.lua$") then
    files[#files + 1] = line
  end
end

for _, rel in ipairs(files) do
  local chunk, err = loadfile(rel)
  if not chunk then realPrint("LOAD FAIL " .. rel .. ": " .. tostring(err)); os.exit(1) end
  local ok, e = pcall(chunk, addonName, ns)
  if not ok then realPrint("RUN FAIL " .. rel .. ": " .. tostring(e)); os.exit(1) end
end

-- Fire PLAYER_LOGIN on every registered OnEvent handler (Main prints times).
for _, f in ipairs(frames) do
  local onEvent = f.GetScript and f:GetScript("OnEvent")
  if onEvent then onEvent(f, "PLAYER_LOGIN") end
end

_G.print = realPrint

-- Assertions: registry populated, WoW-path Cities.times correct, Main printed.
local fail = 0
local function expect(name, cond) if not cond then fail = fail + 1; print("  FAIL: " .. name) end end

expect("loaded " .. #files .. " toc files", #files >= 17)
expect("PrayerTimesNS.modules populated", ns.modules and ns.modules.Cities ~= nil)
expect("data.cities registered", ns.modules.cities ~= nil and #ns.modules.cities == 65)

-- WoW-path engine call via the require() shim.
local Cities = ns.modules.Cities
local res = Cities.times("Rotterdam", 2026, 12, 21)
expect("WoW-path Rotterdam winter Fajr 06:42", res and res.prayers.fajr.hhmm == "06:42")

-- core/Main built the window on PLAYER_LOGIN: six rows with HH:MM times.
local win = ns.modules.Window
expect("Window created on login", win and win.frame ~= nil)
local rowsOk, rowCount = true, 0
if win and win.frame and win.frame.rows then
  for _, key in ipairs({ "fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha" }) do
    local row = win.frame.rows[key]
    rowCount = rowCount + 1
    if not (row and row.time:GetText():match("%d%d:%d%d")) then rowsOk = false end
  end
end
expect("window has six rows with HH:MM", rowCount == 6 and rowsOk)
expect("a next prayer was highlighted", win and win.lastSchedule and win.lastSchedule.nextKey ~= nil)
expect("Notifier + Alerts registered", ns.modules.Notifier ~= nil and ns.modules.Alerts ~= nil)
expect("/pt test fires an alert", (function()
  WowMock.resetAlerts()
  win.testNotification()
  return WowMock.lastRaidNotice ~= nil
end)())

print(string.format("\nWoW load-path check: %d files loaded, %d failure(s)",
  #files, fail))
if fail > 0 then os.exit(1) end
print("OK - addon loads cleanly via the .toc chain.")
