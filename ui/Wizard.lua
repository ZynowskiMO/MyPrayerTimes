-- ui/Wizard.lua
-- First-run welcome wizard (ADR-0006). A paged cream/gold window that
-- introduces the addon and walks a new user through location, calculation and
-- notifications, then hands off to the main display. Shown once, gated by
-- PrayerTimesDB.welcomed; finishing or skipping sets that flag. Page CONTENT is
-- filled in over 3W-2..3W-4 by reusing the pure modules; 3W-1 builds the
-- scaffold (framed paged window, Next/Back/Skip, step dots) + the Welcome page.
-- All navigation is exposed as plain functions so the runner can drive it.

local Window = require("Window")

local Wizard = {}

-- Palette shared with the settings window (cream / charcoal / gold).
local COL = {
  header = { 0.13, 0.11, 0.09, 1 },
  body   = { 0.96, 0.94, 0.88, 1 }, -- cream
  gold   = { 0.72, 0.58, 0.29, 1 },
  text   = { 0.16, 0.14, 0.11 },
  muted  = { 0.45, 0.42, 0.36 },
  dotOff = { 0.70, 0.66, 0.58, 1 },
}

-- Ordered pages. Only "welcome" has content in 3W-1; the rest are empty cream
-- containers (with a heading) that later checkpoints populate.
local PAGES = {
  { key = "welcome",       title = "Welcome",       sub = "About PrayerTimes" },
  { key = "location",      title = "Location",      sub = "Where are you?" },
  { key = "calculation",   title = "Calculation",   sub = "Method & Asr" },
  { key = "notifications", title = "Notifications",  sub = "Alerts & sound" },
  { key = "finish",        title = "All set",       sub = "You're ready" },
}
Wizard.PAGES = PAGES

function Wizard.init(db)
  Wizard.db = db
end

-- The wizard is shown on first run only, gated by the persisted flag.
function Wizard.shouldOpen(db)
  return not (db and db.welcomed)
end

-- ----- small self-contained widgets (cream/gold, no Blizzard art) ----------

local function makeBtn(parent, text, primary)
  local b = CreateFrame("Button", nil, parent)
  local border = b:CreateTexture(nil, "BACKGROUND"); border:SetAllPoints(); border:SetColorTexture(0.55, 0.50, 0.42, 1)
  local fill = b:CreateTexture(nil, "BACKGROUND")
  fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1)
  local base = primary and { 0.80, 0.63, 0.28, 1 } or { 0.88, 0.76, 0.46, 1 }
  local hov  = primary and { 0.88, 0.71, 0.35, 1 } or { 0.93, 0.83, 0.55, 1 }
  fill:SetColorTexture(unpack(base))
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("CENTER"); fs:SetText(text); fs:SetTextColor(0.16, 0.12, 0.06)
  b:SetScript("OnEnter", function() fill:SetColorTexture(unpack(hov)) end)
  b:SetScript("OnLeave", function() fill:SetColorTexture(unpack(base)) end)
  b.fill, b.label = fill, fs
  return b
end

-- ----- navigation ----------------------------------------------------------

function Wizard.isLast() return Wizard.step == #PAGES end

-- Show page `i`, hide the rest, refresh the dots, Back/Skip/Next chrome and the
-- header step text. Clamps to the valid range.
function Wizard.go(i)
  i = math.max(1, math.min(#PAGES, i or 1))
  Wizard.step = i
  if Wizard.pages then
    for n, p in ipairs(Wizard.pages) do p:SetShown(n == i) end
  end
  if Wizard.dots then
    for n, d in ipairs(Wizard.dots) do
      d:SetColorTexture(unpack(n == i and COL.gold or COL.dotOff))
    end
  end
  if Wizard.backBtn then Wizard.backBtn:SetShown(i > 1) end
  if Wizard.skipBtn then Wizard.skipBtn:SetShown(not Wizard.isLast()) end
  if Wizard.nextBtn then Wizard.nextBtn.label:SetText(Wizard.isLast() and "Done" or "Next") end
  if Wizard.stepText then
    Wizard.stepText:SetText(string.format("STEP %d / %d", i, #PAGES))
  end
end

function Wizard.next()
  if Wizard.isLast() then Wizard.finish() else Wizard.go((Wizard.step or 1) + 1) end
end

function Wizard.back() Wizard.go((Wizard.step or 1) - 1) end

-- Skip and Finish both accept whatever is currently set (defaults are valid)
-- and mark the wizard done so it never reappears, then reveal the main window.
function Wizard.complete()
  if Wizard.db then Wizard.db.welcomed = true end
  if Wizard.frame then Wizard.frame:Hide() end
  if Window.frame then Window.frame:Show() end
end

function Wizard.skip() Wizard.complete() end
function Wizard.finish() Wizard.complete() end

-- ----- build ---------------------------------------------------------------

function Wizard.create()
  if Wizard.frame then return Wizard.frame end

  local f = CreateFrame("Frame", "PrayerTimesWizard", UIParent)
  f:SetSize(520, 430)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  local body = f:CreateTexture(nil, "BACKGROUND")
  body:SetAllPoints(); body:SetColorTexture(unpack(COL.body))

  -- Dark header: wordmark + step text.
  local header = f:CreateTexture(nil, "BACKGROUND")
  header:SetPoint("TOPLEFT", 0, 0); header:SetPoint("TOPRIGHT", 0, 0); header:SetHeight(46)
  header:SetColorTexture(unpack(COL.header))
  local wm = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  wm:SetPoint("TOPLEFT", 16, -14); wm:SetText("PrayerTimes"); wm:SetTextColor(unpack(COL.gold))
  Wizard.stepText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  Wizard.stepText:SetPoint("TOPRIGHT", -16, -18)

  -- One frame per page (content area between header and footer).
  Wizard.pages = {}
  for i, p in ipairs(PAGES) do
    local panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -46)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 58)
    local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h:SetPoint("TOPLEFT", 24, -22); h:SetText(p.title); h:SetTextColor(unpack(COL.text))
    panel.heading = h
    Wizard.pages[i] = panel
  end

  -- Welcome page content (3W-1).
  local intro = Wizard.pages[1]:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  intro:SetPoint("TOPLEFT", 24, -64); intro:SetPoint("RIGHT", Wizard.pages[1], "RIGHT", -24, 0)
  intro:SetJustifyH("LEFT"); intro:SetJustifyV("TOP"); intro:SetTextColor(unpack(COL.text))
  intro:SetText(
    "PrayerTimes shows the five daily prayer times for your location, "
    .. "calculated right here in the game \226\128\148 no internet needed.\n\n"
    .. "In the next few steps you'll choose your city, pick a calculation "
    .. "method and Asr school, and set up reminders before each prayer.\n\n"
    .. "You can change any of this later from the settings window. Let's begin.")

  -- Footer: Back (left), step dots (centre), Skip + Next/Done (right).
  Wizard.backBtn = makeBtn(f, "Back")
  Wizard.backBtn:SetSize(90, 28); Wizard.backBtn:SetPoint("BOTTOMLEFT", 16, 16)
  Wizard.backBtn:SetScript("OnClick", function() Wizard.back() end)

  Wizard.nextBtn = makeBtn(f, "Next", true)
  Wizard.nextBtn:SetSize(110, 28); Wizard.nextBtn:SetPoint("BOTTOMRIGHT", -16, 16)
  Wizard.nextBtn:SetScript("OnClick", function() Wizard.next() end)

  Wizard.skipBtn = makeBtn(f, "Skip")
  Wizard.skipBtn:SetSize(90, 28)
  Wizard.skipBtn:SetPoint("RIGHT", Wizard.nextBtn, "LEFT", -10, 0)
  Wizard.skipBtn:SetScript("OnClick", function() Wizard.skip() end)

  -- Step-dot indicator centred along the footer.
  Wizard.dots = {}
  local n = #PAGES
  local gap = 18
  local totalW = (n - 1) * gap
  for i = 1, n do
    local dot = f:CreateTexture(nil, "ARTWORK")
    dot:SetSize(8, 8)
    dot:SetPoint("BOTTOM", f, "BOTTOM", -totalW / 2 + (i - 1) * gap, 24)
    dot:SetColorTexture(unpack(COL.dotOff))
    Wizard.dots[i] = dot
  end

  Wizard.frame = f
  Wizard.go(1)
  return f
end

function Wizard.open()
  Wizard.create()
  Wizard.go(1)
  Wizard.frame:Show()
end

function Wizard.close()
  if Wizard.frame then Wizard.frame:Hide() end
end

if PrayerTimesNS then PrayerTimesNS.modules.Wizard = Wizard end
return Wizard
