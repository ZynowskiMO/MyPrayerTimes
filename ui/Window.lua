-- Window.lua
-- The in-game display window. WoW API calls live only inside functions, so the
-- runner can load this under the mock. Builds a frame with a title and six
-- rows (proper-case label + time), and highlights the next prayer. 2c-2 renders
-- once (static); movable/lockable is 2c-3 and the live ticker is 2c-4.

local Cities = require("Cities")
local Schedule = require("Schedule")
local Clock = require("Clock")
local Notifier = require("Notifier")
local Alerts = require("Alerts")
local Selection = require("Selection")

local LABELS = {
  fajr = "Fajr", sunrise = "Sunrise", dhuhr = "Dhuhr",
  asr = "Asr", maghrib = "Maghrib", isha = "Isha",
}
local ORDER = Schedule.ORDER

local NEXT_COLOR = { 0.25, 1.0, 0.4 } -- green highlight for the next prayer
local NORMAL_COLOR = { 1.0, 1.0, 1.0 }

local Window = {}

local function nowEpoch()
  if GetServerTime then return GetServerTime() end
  return time()
end

-- Player's live UTC offset in minutes (for manual machine-tz entries). WoW-side
-- via date(); overridden in tests. DST is handled by the OS.
function Window.machineOffset()
  if not (time and date) then return 0 end
  local now = time()
  local u = date("!*t", now)
  u.isdst = false
  return math.floor((now - time(u)) / 60 + 0.5)
end

function Window.create()
  if Window.frame then return Window.frame end

  local f = CreateFrame("Frame", "PrayerTimesFrame", UIParent)
  f:SetSize(190, 234)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    if not (Window.db and Window.db.locked) then self:StartMoving() end
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    Window.savePosition()
  end)

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.6)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -10)
  f.title = title

  f.rows = {}
  for i, key in ipairs(ORDER) do
    local y = -34 - (i - 1) * 26
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 14, y)
    label:SetJustifyH("LEFT")
    label:SetText(LABELS[key])
    local timeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timeText:SetPoint("TOPRIGHT", -14, y)
    timeText:SetJustifyH("RIGHT")
    f.rows[key] = { label = label, time = timeText }
  end

  local countdown = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  countdown:SetPoint("BOTTOM", 0, 12)
  countdown:SetTextColor(0.85, 0.85, 0.35)
  f.countdown = countdown

  Window.frame = f
  Window.restorePosition()
  Window.applyLock()
  Window.refresh()
  if C_Timer and C_Timer.NewTicker then
    Window.ticker = C_Timer.NewTicker(1, function() Window.tick() end)
  end
  f:Show()
  return f
end

-- Persistence + lock. Window.db is the per-character SavedVariables table,
-- supplied by Window.init (Main passes PrayerTimesDB). All of this is pure
-- enough to drive from the runner with a plain table standing in for the DB.
function Window.init(db)
  Window.db = db
  db.locked = db.locked or false
  local n = db.notify or {}
  if n.beforeMinutes == nil then n.beforeMinutes = 10 end
  if n.atTime == nil then n.atTime = true end
  if n.sound == nil then n.sound = true end
  n.fired = n.fired or {}
  db.notify = n
end

-- Fire any due prayer notifications for `now` (called every tick). Reads
-- settings + the persisted dedupe set from the DB so a /reload never re-fires.
function Window.checkNotifications(now)
  local db = Window.db
  if not (db and db.notify and Window.localTimes and Window.dayKey) then return end
  local n = db.notify
  if n.firedDay ~= Window.dayKey then
    n.fired = {}
    n.firedDay = Window.dayKey
  end
  local five = {}
  for _, p in ipairs(Notifier.PRAYERS) do five[p] = Window.localTimes[p] end
  local events = Notifier.check(five, now.minuteOfDay, n, Window.dayKey, n.fired)
  for _, ev in ipairs(events) do Alerts.fire(ev, n) end
  return events
end

-- Fire a sample notification so the player can see/hear the presentation.
function Window.testNotification()
  Alerts.test(Window.db and Window.db.notify)
end

function Window.savePosition()
  local f = Window.frame
  if not (f and Window.db) then return end
  local point, _, relPoint, x, y = f:GetPoint(1)
  Window.db.position = { point = point, relPoint = relPoint, x = x, y = y }
end

function Window.restorePosition()
  local f = Window.frame
  if not f then return end
  f:ClearAllPoints()
  local p = Window.db and Window.db.position
  if p then
    f:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
  else
    f:SetPoint("CENTER")
  end
end

-- Locked = the window ignores the mouse entirely (can't be dragged, clicks
-- pass through). The OnDragStart guard also checks the flag.
function Window.applyLock()
  local f = Window.frame
  if not f then return end
  f:EnableMouse(not (Window.db and Window.db.locked))
end

function Window.setLocked(locked)
  if Window.db then Window.db.locked = locked and true or false end
  Window.applyLock()
end

function Window.toggleLock()
  Window.setLocked(not (Window.db and Window.db.locked))
end

-- Update highlight + countdown for the current moment, from the cached times.
local function renderNow(now)
  local f = Window.frame
  local sched = Schedule.compute(Window.localTimes, now.minuteOfDay)
  for _, key in ipairs(ORDER) do
    local c = (key == sched.nextKey) and NEXT_COLOR or NORMAL_COLOR
    f.rows[key].label:SetTextColor(c[1], c[2], c[3])
    f.rows[key].time:SetTextColor(c[1], c[2], c[3])
  end
  if sched.nextKey and sched.untilMinutes then
    local untilSec = Schedule.untilSeconds(sched, now.secondOfDay)
    f.countdown:SetText(LABELS[sched.nextKey] .. " in " .. Schedule.formatCountdown(untilSec))
  else
    f.countdown:SetText("--:--")
  end
  Window.checkNotifications(now)
  Window.lastSchedule = sched -- exposed for tests
  return sched
end

-- Full refresh: recompute the day's six times (cached), then render.
function Window.refresh()
  local f = Window.frame
  if not f then return end

  local city = Selection.resolve(Window.db, Window.machineOffset)
  local now = Clock.cityNow(city, nowEpoch())
  local result = Cities.times(city, now.year, now.month, now.day)

  Window.localTimes = {}
  for _, key in ipairs(ORDER) do
    Window.localTimes[key] = result.prayers[key].localMin
    f.rows[key].time:SetText(result.prayers[key].hhmm)
  end
  f.title:SetText(city.name)
  Window.dayKey = string.format("%04d-%02d-%02d", now.year, now.month, now.day)
  return renderNow(now)
end

-- Light per-second update: re-highlight + recount from cached times; on a new
-- local day, fall back to a full refresh so the times themselves update.
function Window.tick()
  local f = Window.frame
  if not f then return end
  local city = Selection.resolve(Window.db, Window.machineOffset)
  local now = Clock.cityNow(city, nowEpoch())
  local dayKey = string.format("%04d-%02d-%02d", now.year, now.month, now.day)
  if dayKey ~= Window.dayKey then return Window.refresh() end
  return renderNow(now)
end

if PrayerTimesNS then PrayerTimesNS.modules.Window = Window end
return Window
