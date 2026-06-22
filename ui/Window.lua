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
local Icons = require("Icons")

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
local SUNRISE_COLOR = { 0.78, 0.49, 0.18 } -- distinct sunrise amber: a marker, not a prayer

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
  local gt = gear:CreateTexture(nil, "ARTWORK"); gt:SetPoint("CENTER"); gt:SetSize(15, 15)
  Icons.setUI(gt, "settings", unpack(COL.gold))
  gear:SetScript("OnEnter", function() gt:SetVertexColor(1, 0.95, 0.7) end)
  gear:SetScript("OnLeave", function() gt:SetVertexColor(unpack(COL.gold)) end)
  gear:SetScript("OnClick", function()
    local P = require("Picker"); if P and P.toggle then P.toggle() end
  end)
  f.gear = gear

  -- Minimize / restore button (collapses to just the next prayer).
  local minBtn = CreateFrame("Button", nil, f)
  minBtn:SetSize(18, 18); minBtn:SetPoint("RIGHT", gear, "LEFT", -4, 0)
  local mIcon = minBtn:CreateTexture(nil, "ARTWORK"); mIcon:SetPoint("CENTER"); mIcon:SetSize(14, 14)
  Icons.setUI(mIcon, "minimize", unpack(COL.gold))
  minBtn:SetScript("OnEnter", function() mIcon:SetVertexColor(1, 0.95, 0.7) end)
  minBtn:SetScript("OnLeave", function() mIcon:SetVertexColor(unpack(COL.gold)) end)
  minBtn:SetScript("OnClick", function() Window.toggleMinimize() end)
  minBtn.icon = mIcon
  f.minBtn = minBtn

  f.rows = {}
  for i, key in ipairs(ORDER) do
    local y = -32 - (i - 1) * 25
    local row = CreateFrame("Frame", nil, f)
    row:SetPoint("TOPLEFT", 4, y); row:SetPoint("TOPRIGHT", -4, y); row:SetHeight(24)
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(); hl:SetColorTexture(unpack(COL.rowHl)); hl:Hide()
    -- Icon slot (rounded light square) + the per-prayer icon (ADR-0007).
    local iconBg = row:CreateTexture(nil, "BORDER")
    iconBg:SetSize(20, 20); iconBg:SetPoint("LEFT", 6, 0)
    iconBg:SetColorTexture(1, 0.99, 0.96, 0.55)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(13, 13); icon:SetPoint("CENTER", iconBg, "CENTER")
    Icons.apply(icon, key, false)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 34, 0); label:SetJustifyH("LEFT")
    label:SetText(LABELS[key]); label:SetTextColor(unpack(COL.text))
    local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timeText:SetPoint("RIGHT", -10, 0); timeText:SetJustifyH("RIGHT")
    timeText:SetTextColor(unpack(COL.text))
    f.rows[key] = { frame = row, label = label, time = timeText, hl = hl, icon = icon, iconBg = iconBg }
  end

  -- Minimised "hero" line: the next prayer as icon + name + time, mirroring a
  -- main row so it stays aligned. Shown only while minimised; centred in the
  -- band between the header and the footer strip.
  local miniIconBg = f:CreateTexture(nil, "BORDER")
  miniIconBg:SetSize(22, 22); miniIconBg:SetPoint("LEFT", f, "TOPLEFT", 10, -46)
  miniIconBg:SetColorTexture(1, 0.99, 0.96, 0.55); miniIconBg:Hide()
  local miniIcon = f:CreateTexture(nil, "ARTWORK")
  miniIcon:SetSize(15, 15); miniIcon:SetPoint("CENTER", miniIconBg, "CENTER"); miniIcon:Hide()
  local nextLine = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  nextLine:SetPoint("LEFT", miniIconBg, "RIGHT", 8, 0); nextLine:SetTextColor(unpack(COL.text))
  nextLine:Hide()
  local miniTime = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  miniTime:SetPoint("RIGHT", f, "TOPRIGHT", -14, -46); miniTime:SetTextColor(unpack(COL.text))
  miniTime:Hide()
  f.nextLine, f.miniIcon, f.miniIconBg, f.miniTime = nextLine, miniIcon, miniIconBg, miniTime

  -- Countdown sits on a dark footer strip (mirrors the dark header) with white
  -- text, so the most-glanced info stands out against the cream body.
  local footer = f:CreateTexture(nil, "ARTWORK")
  footer:SetPoint("BOTTOMLEFT", 1, 1); footer:SetPoint("BOTTOMRIGHT", -1, 1); footer:SetHeight(26)
  footer:SetColorTexture(unpack(COL.header))
  f.footer = footer
  local countdown = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  countdown:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
  countdown:SetPoint("CENTER", footer, "CENTER", 0, 0)
  countdown:SetTextColor(0.97, 0.96, 0.92)
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
  -- The minimised hero group (icon + name + time) toggles as a unit.
  for _, region in ipairs({ f.nextLine, f.miniIcon, f.miniIconBg, f.miniTime }) do
    if region then region:SetShown(mini and true or false) end
  end
  if f.minBtn and f.minBtn.icon then
    Icons.setUI(f.minBtn.icon, mini and "restore" or "minimize", unpack(COL.gold))
  end
  -- Keep the header fixed while resizing: a CENTER anchor would move the whole
  -- window on minimise/restore. Pin the current top-left, then grow/shrink down.
  local top, left = f:GetTop(), f:GetLeft()
  f:SetHeight(mini and MINIMIZED_H or EXPANDED_H)
  if type(top) == "number" and type(left) == "number" then
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    Window.savePosition()
  end
end

function Window.setMinimized(on)
  if Window.db then Window.db.minimized = on and true or false end
  Window.applyMinimized()
end

function Window.toggleMinimize()
  Window.setMinimized(not (Window.db and Window.db.minimized))
end

-- Row text colour: dark-on-gold when it's the next event, a distinct sunrise
-- amber for the Sunrise marker (not a prayer), normal dark otherwise.
function Window.rowColor(key, isNext)
  if isNext then return NEXT_COLOR end
  if key == "sunrise" then return SUNRISE_COLOR end
  return NORMAL_COLOR
end

-- Update highlight + countdown for the current moment, from the cached times.
local function renderNow(now)
  local f = Window.frame
  local sched = Schedule.compute(Window.localTimes, now.minuteOfDay)
  for _, key in ipairs(ORDER) do
    local isNext = (key == sched.nextKey)
    local c = Window.rowColor(key, isNext)
    f.rows[key].label:SetTextColor(c[1], c[2], c[3])
    f.rows[key].time:SetTextColor(c[1], c[2], c[3])
    if f.rows[key].hl then
      if isNext then f.rows[key].hl:Show() else f.rows[key].hl:Hide() end
    end
    if f.rows[key].icon then
      Icons.apply(f.rows[key].icon, key, isNext)
      -- Tint the Sunrise icon in its marker colour to match the text (unless next).
      if key == "sunrise" and not isNext then f.rows[key].icon:SetVertexColor(unpack(SUNRISE_COLOR)) end
    end
  end
  -- Footer: the city's current local time + time to the next prayer (no prayer
  -- name -- the highlighted row / minimised hero already names it).
  local clock = string.format("%02d:%02d", math.floor(now.minuteOfDay / 60), now.minuteOfDay % 60)
  if sched.nextKey and sched.untilMinutes then
    local untilSec = Schedule.untilSeconds(sched, now.secondOfDay)
    f.countdown:SetText(clock .. "  \194\183  " .. Schedule.formatCountdown(untilSec))
    -- Minimised hero line: icon + name + time of the next prayer.
    if f.nextLine then f.nextLine:SetText(LABELS[sched.nextKey]) end
    if f.miniTime then f.miniTime:SetText(f.rows[sched.nextKey].time:GetText() or "") end
    if f.miniIcon then Icons.apply(f.miniIcon, sched.nextKey, true) end
  else
    f.countdown:SetText(clock .. "  \194\183  --:--")
    if f.nextLine then f.nextLine:SetText("--:--") end
    if f.miniTime then f.miniTime:SetText("") end
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
