-- Window.lua
-- The in-game display window. WoW API calls live only inside functions, so the
-- runner can load this under the mock. Builds a frame with a title and six
-- rows (proper-case label + time), and highlights the next prayer. 2c-2 renders
-- once (static); movable/lockable is 2c-3 and the live ticker is 2c-4.

local Cities = require("Cities")
local Schedule = require("Schedule")
local Clock = require("Clock")

local LABELS = {
  fajr = "Fajr", sunrise = "Sunrise", dhuhr = "Dhuhr",
  asr = "Asr", maghrib = "Maghrib", isha = "Isha",
}
local ORDER = Schedule.ORDER
local DEFAULT_CITY = "Rotterdam" -- temporary hardcoded default for 2c

local NEXT_COLOR = { 0.25, 1.0, 0.4 } -- green highlight for the next prayer
local NORMAL_COLOR = { 1.0, 1.0, 1.0 }

local Window = {}

local function nowEpoch()
  if GetServerTime then return GetServerTime() end
  return time()
end

function Window.create()
  if Window.frame then return Window.frame end

  local f = CreateFrame("Frame", "PrayerTimesFrame", UIParent)
  f:SetSize(190, 210)
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

  Window.frame = f
  Window.restorePosition()
  Window.applyLock()
  Window.refresh()
  f:Show()
  return f
end

-- Persistence + lock. Window.db is the per-character SavedVariables table,
-- supplied by Window.init (Main passes PrayerTimesDB). All of this is pure
-- enough to drive from the runner with a plain table standing in for the DB.
function Window.init(db)
  Window.db = db
  db.locked = db.locked or false
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

-- Recompute and render times + highlight for the current moment.
function Window.refresh()
  local f = Window.frame
  if not f then return end

  local city = Cities.findByName(DEFAULT_CITY)
  local now = Clock.cityNow(city, nowEpoch())
  local result = Cities.times(DEFAULT_CITY, now.year, now.month, now.day)

  local localTimes = {}
  for _, key in ipairs(ORDER) do localTimes[key] = result.prayers[key].localMin end
  local sched = Schedule.compute(localTimes, now.minuteOfDay)

  f.title:SetText(DEFAULT_CITY)
  for _, key in ipairs(ORDER) do
    local row = f.rows[key]
    row.time:SetText(result.prayers[key].hhmm)
    local c = (key == sched.nextKey) and NEXT_COLOR or NORMAL_COLOR
    row.label:SetTextColor(c[1], c[2], c[3])
    row.time:SetTextColor(c[1], c[2], c[3])
  end

  Window.lastSchedule = sched -- exposed for tests
  return sched
end

if PrayerTimesNS then PrayerTimesNS.modules.Window = Window end
return Window
