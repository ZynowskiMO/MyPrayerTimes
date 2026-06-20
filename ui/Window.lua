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
local Methods = require("Methods")

local LABELS = {
  fajr = "Fajr", sunrise = "Sunrise", dhuhr = "Dhuhr",
  asr = "Asr", maghrib = "Maghrib", isha = "Isha",
}
local ORDER = Schedule.ORDER

-- Cream/gold palette matching the settings window (ADR-0005 redesign).
local COL = {
  border  = { 0.10, 0.09, 0.07, 1 },
  header  = { 0.13, 0.11, 0.09, 1 },
  bg      = { 0.96, 0.94, 0.88, 0.96 },
  gold    = { 0.72, 0.58, 0.29, 1 },
  text    = { 0.16, 0.14, 0.11 },
  rowHl   = { 0.85, 0.78, 0.55, 0.7 },
}
local NEXT_COLOR = { 0.20, 0.14, 0.05 }  -- dark text on the gold next-row bar
local NORMAL_COLOR = { 0.16, 0.14, 0.11 } -- dark text on cream

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
  f:SetSize(206, 226)
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

  -- Cream card with a dark border + a dark header strip.
  local border = f:CreateTexture(nil, "BACKGROUND")
  border:SetAllPoints(); border:SetColorTexture(unpack(COL.border))
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1); bg:SetColorTexture(unpack(COL.bg))
  local header = f:CreateTexture(nil, "ARTWORK")
  header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1); header:SetHeight(26)
  header:SetColorTexture(unpack(COL.header))

  -- City name (gold) + a gear button that opens settings.
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("LEFT", header, "LEFT", 10, 0); title:SetTextColor(unpack(COL.gold))
  f.title = title

  local gear = CreateFrame("Button", nil, f)
  gear:SetSize(18, 18); gear:SetPoint("RIGHT", header, "RIGHT", -8, 0)
  local gt = gear:CreateTexture(nil, "ARTWORK"); gt:SetAllPoints()
  gt:SetTexture("Interface\\Buttons\\UI-OptionsButton")
  gear:SetScript("OnEnter", function() gt:SetVertexColor(1, 0.95, 0.7) end)
  gear:SetScript("OnLeave", function() gt:SetVertexColor(1, 1, 1) end)
  gear:SetScript("OnClick", function()
    local P = require("Picker"); if P and P.toggle then P.toggle() end
  end)
  f.gear = gear

  -- Minimize / restore button (collapses to just the next prayer).
  local minBtn = CreateFrame("Button", nil, f)
  minBtn:SetSize(18, 18); minBtn:SetPoint("RIGHT", gear, "LEFT", -4, 0)
  local mfs = minBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  mfs:SetPoint("CENTER", 0, 2); mfs:SetText("_"); mfs:SetTextColor(unpack(COL.gold))
  minBtn:SetScript("OnEnter", function() mfs:SetTextColor(1, 0.95, 0.7) end)
  minBtn:SetScript("OnLeave", function() mfs:SetTextColor(unpack(COL.gold)) end)
  minBtn:SetScript("OnClick", function() Window.toggleMinimize() end)
  minBtn.label = mfs
  f.minBtn = minBtn

  f.rows = {}
  for i, key in ipairs(ORDER) do
    local y = -32 - (i - 1) * 25
    local row = CreateFrame("Frame", nil, f)
    row:SetPoint("TOPLEFT", 4, y); row:SetPoint("TOPRIGHT", -4, y); row:SetHeight(24)
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(); hl:SetColorTexture(unpack(COL.rowHl)); hl:Hide()
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 10, 0); label:SetJustifyH("LEFT")
    label:SetText(LABELS[key]); label:SetTextColor(unpack(COL.text))
    local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timeText:SetPoint("RIGHT", -10, 0); timeText:SetJustifyH("RIGHT")
    timeText:SetTextColor(unpack(COL.text))
    f.rows[key] = { frame = row, label = label, time = timeText, hl = hl }
  end

  -- Compact next-prayer line, shown only while minimized.
  local nextLine = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  nextLine:SetPoint("TOPLEFT", 12, -36); nextLine:SetTextColor(unpack(COL.text))
  nextLine:Hide()
  f.nextLine = nextLine

  local countdown = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  countdown:SetPoint("BOTTOM", 0, 10)
  countdown:SetTextColor(unpack(COL.gold))
  f.countdown = countdown

  Window.frame = f
  Window.restorePosition()
  Window.applyLock()
  Window.refresh()
  Window.applyMinimized()
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
  db.minimized = db.minimized or false
  db.method = Methods.resolveMethod(db.method) -- default MWL; sanitise stale keys
  db.madhab = Methods.resolveMadhab(db.madhab) -- default Standard (Shafi)
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

-- Minimized = hide the six rows and show only the next-prayer line + countdown,
-- shrinking the frame. Persisted in the DB.
local EXPANDED_H, MINIMIZED_H = 226, 92

function Window.applyMinimized()
  local f = Window.frame
  if not f then return end
  local mini = Window.db and Window.db.minimized
  for _, key in ipairs(ORDER) do f.rows[key].frame:SetShown(not mini) end
  if f.nextLine then f.nextLine:SetShown(mini and true or false) end
  if f.minBtn and f.minBtn.label then f.minBtn.label:SetText(mini and "+" or "_") end
  f:SetHeight(mini and MINIMIZED_H or EXPANDED_H)
end

function Window.setMinimized(on)
  if Window.db then Window.db.minimized = on and true or false end
  Window.applyMinimized()
end

function Window.toggleMinimize()
  Window.setMinimized(not (Window.db and Window.db.minimized))
end

-- Update highlight + countdown for the current moment, from the cached times.
local function renderNow(now)
  local f = Window.frame
  local sched = Schedule.compute(Window.localTimes, now.minuteOfDay)
  for _, key in ipairs(ORDER) do
    local isNext = (key == sched.nextKey)
    local c = isNext and NEXT_COLOR or NORMAL_COLOR
    f.rows[key].label:SetTextColor(c[1], c[2], c[3])
    f.rows[key].time:SetTextColor(c[1], c[2], c[3])
    if f.rows[key].hl then
      if isNext then f.rows[key].hl:Show() else f.rows[key].hl:Hide() end
    end
  end
  if sched.nextKey and sched.untilMinutes then
    local untilSec = Schedule.untilSeconds(sched, now.secondOfDay)
    f.countdown:SetText(LABELS[sched.nextKey] .. " in " .. Schedule.formatCountdown(untilSec))
    if f.nextLine then
      f.nextLine:SetText(LABELS[sched.nextKey] .. "   " .. (f.rows[sched.nextKey].time:GetText() or ""))
    end
  else
    f.countdown:SetText("--:--")
    if f.nextLine then f.nextLine:SetText("--:--") end
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
  local db = Window.db or {} -- create() may run before init; Methods handles nil
  local result = Cities.times(city, now.year, now.month, now.day,
    { method = db.method, madhab = db.madhab })

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
