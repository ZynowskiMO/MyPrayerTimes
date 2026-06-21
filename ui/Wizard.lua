-- ui/Wizard.lua
-- First-run welcome wizard (ADR-0006). A paged cream/gold window that
-- introduces the addon and walks a new user through location, calculation and
-- notifications, then hands off to the main display. Shown once, gated by
-- PrayerTimesDB.welcomed; finishing or skipping sets that flag. Page CONTENT is
-- filled in over 3W-2..3W-4 by reusing the pure modules; 3W-1 builds the
-- scaffold (framed paged window, Next/Back/Skip, step dots) + the Welcome page.
-- All navigation is exposed as plain functions so the runner can drive it.

local Window = require("Window")
local Cities = require("Cities")
local Selection = require("Selection")
local Picker = require("Picker") -- reuse its pure builders + styled components

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
  -- Fill on the BORDER layer (one above BACKGROUND) so it always draws on top of
  -- the outline regardless of texture creation order.
  local fill = b:CreateTexture(nil, "BORDER")
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

-- ----- Location page (3W-2): reuse Picker's pure builders + Selection -------
-- The wizard keeps its own widget pools but drives them with the same pure row
-- builders (Picker.masterRows/detailRows/defaultCountry) and the same Selection
-- setters as the settings window, so picking a city here persists identically.

local function afterLocationChange()
  if Window.refresh then Window.refresh() end
  if Picker.db and Picker.updateSelected then Picker.updateSelected() end
  Wizard.refreshLocation()
end

function Wizard.selectCity(name)
  Selection.setCity(Wizard.db, name); afterLocationChange()
end

function Wizard.selectSaved(name)
  Selection.setSavedCity(Wizard.db, name); afterLocationChange()
end

function Wizard.selectCountry(country)
  Wizard.locCountry = country; Wizard.dScroll = 0
  if Wizard.searchBox then Wizard.searchBox:SetText("") end -- fires refreshLocation
  Wizard.refreshLocation("")
end

function Wizard.updateLocCard()
  if not Wizard.cardCity then return end
  local sel = Selection.get(Wizard.db)
  local city, country = "Rotterdam", "default"
  if sel then
    if sel.kind == "city" then
      local c = Cities.findByName(sel.name)
      if c then city, country = c.name, c.country else city, country = sel.name, "" end
    elseif sel.kind == "saved" then
      city, country = sel.name, "saved"
    else
      city, country = "Manual location", ""
    end
  end
  Wizard.cardCity:SetText(city); Wizard.cardCountry:SetText(country)
end

function Wizard.refreshLocation(query)
  query = query or (Wizard.searchBox and Wizard.searchBox:GetText()) or ""
  if not Wizard.locCountry then Wizard.locCountry = Picker.defaultCountry(Wizard.db) end
  Wizard.masterData = Picker.masterRows(Wizard.db)
  local rows, searching = Picker.detailRows(Wizard.db, query, Wizard.locCountry)
  Wizard.detailData, Wizard.detailSearching = rows, searching
  Wizard.refreshMaster(); Wizard.refreshDetail(); Wizard.updateLocCard()
end

function Wizard.refreshMaster()
  if not Wizard.masterPool then return end
  local data, vis = Wizard.masterData or {}, #Wizard.masterPool
  Wizard.mScroll = math.min(Wizard.mScroll or 0, math.max(0, #data - vis))
  local sel = Selection.get(Wizard.db)
  local selSaved = sel and sel.kind == "saved" and sel.name or nil
  for i = 1, vis do
    local row = Wizard.masterPool[i]
    local e = data[Wizard.mScroll + i]
    row.count:SetText(""); row.hl:Hide(); row.kind, row.country, row.name = nil, nil, nil
    if not e then
      row:Hide()
    elseif e.kind == "myheader" or e.kind == "cheader" then
      row.label:SetText("|cff8a8275" .. e.label .. "|r"); row.kind = "header"; row:Show()
    elseif e.kind == "saved" then
      row.label:SetText(e.city.name); row.kind, row.name = "saved", e.city.name
      if e.city.name == selSaved then row.hl:Show() end; row:Show()
    elseif e.kind == "country" then
      row.label:SetText(e.country); row.count:SetText("|cff8a8275" .. e.count .. "|r")
      row.kind, row.country = "country", e.country
      if e.country == Wizard.locCountry then row.hl:Show() end; row:Show()
    end
  end
  if Wizard.masterSB then Wizard.masterSB:update() end
end

function Wizard.refreshDetail()
  if not Wizard.detailPool then return end
  local data, vis = Wizard.detailData or {}, #Wizard.detailPool
  Wizard.dScroll = math.min(Wizard.dScroll or 0, math.max(0, #data - vis))
  local sel = Selection.get(Wizard.db)
  local selCity = sel and sel.kind == "city" and sel.name or nil
  if Wizard.detailHeader then
    Wizard.detailHeader:SetText("|cffb89254"
      .. (Wizard.detailSearching and "SEARCH RESULTS" or (Wizard.locCountry or "")) .. "|r")
  end
  for i = 1, vis do
    local row = Wizard.detailPool[i]
    local e = data[Wizard.dScroll + i]
    row.check:SetText(""); row.hl:Hide(); row.name = nil
    if not e then
      row:Hide()
    else
      row.label:SetText(e.city.name); row.name = e.city.name
      if e.city.name == selCity then row.hl:Show(); row.check:SetText("|cffb89254\226\156\147|r") end
      row:Show()
    end
  end
  if Wizard.detailSB then Wizard.detailSB:update() end
end

function Wizard.scrollMaster(d) Wizard.mScroll = math.max(0, (Wizard.mScroll or 0) - d); Wizard.refreshMaster() end
function Wizard.scrollDetail(d) Wizard.dScroll = math.max(0, (Wizard.dScroll or 0) - d); Wizard.refreshDetail() end

-- Build the Location page UI into its panel. Uses the cream/gold palette and
-- styled component factories exported by the settings window.
local function buildLocationPage(panel)
  local C, UI = Picker.COL, Picker.ui
  local MVIS, DVIS, RH = 9, 9, 18

  -- Current-location card.
  local card = panel:CreateTexture(nil, "BACKGROUND")
  card:SetPoint("TOPLEFT", 24, -54); card:SetSize(472, 42); card:SetColorTexture(unpack(C.card))
  local cl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  cl:SetPoint("TOPLEFT", 36, -60); cl:SetText("CURRENT LOCATION"); cl:SetTextColor(unpack(C.gold))
  Wizard.cardCity = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  Wizard.cardCity:SetPoint("TOPLEFT", 36, -74); Wizard.cardCity:SetTextColor(0.96, 0.94, 0.88)
  Wizard.cardCountry = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  Wizard.cardCountry:SetPoint("TOPRIGHT", -36, -76); Wizard.cardCountry:SetTextColor(0.70, 0.67, 0.60)

  -- Search across all cities (flat cream field + placeholder).
  local search = CreateFrame("EditBox", "PrayerTimesWizardSearch", panel)
  search:SetSize(472, 24); search:SetPoint("TOPLEFT", 24, -106); search:SetAutoFocus(false)
  search:SetFontObject("GameFontHighlight"); search:SetTextColor(unpack(C.text)); search:SetTextInsets(10, 10, 0, 0)
  search:SetScript("OnEscapePressed", search.ClearFocus)
  local sb = search:CreateTexture(nil, "BACKGROUND"); sb:SetAllPoints(); sb:SetColorTexture(0.55, 0.50, 0.42, 1)
  local sf = search:CreateTexture(nil, "BORDER")
  sf:SetPoint("TOPLEFT", 1, -1); sf:SetPoint("BOTTOMRIGHT", -1, 1); sf:SetColorTexture(unpack(C.cardOff))
  local ph = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ph:SetPoint("LEFT", 10, 0); ph:SetText("Search all cities..."); ph:SetTextColor(0.55, 0.52, 0.46)
  search:SetScript("OnTextChanged", function(self)
    ph:SetShown(self:GetText() == "")
    Wizard.dScroll = 0; Wizard.refreshLocation(self:GetText())
  end)
  Wizard.searchBox = search

  -- Master column: My Cities + countries (with counts).
  local mlist = CreateFrame("Frame", nil, panel)
  mlist:SetPoint("TOPLEFT", 24, -142); mlist:SetSize(200, MVIS * RH)
  mlist:EnableMouseWheel(true); mlist:SetScript("OnMouseWheel", function(_, d) Wizard.scrollMaster(d) end)
  Wizard.masterPool = {}
  for i = 1, MVIS do
    local row = CreateFrame("Button", nil, mlist)
    row:SetSize(200, RH); row:SetPoint("TOPLEFT", 0, -(i - 1) * RH)
    local hl = row:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(); hl:SetColorTexture(unpack(C.rowHl)); hl:Hide(); row.hl = hl
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 8, 0); label:SetJustifyH("LEFT"); label:SetTextColor(unpack(C.text)); row.label = label
    local count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("RIGHT", -8, 0); row.count = count
    row:SetScript("OnClick", function(self)
      if self.kind == "country" then Wizard.selectCountry(self.country)
      elseif self.kind == "saved" then Wizard.selectSaved(self.name) end
    end)
    Wizard.masterPool[i] = row
  end
  Wizard.masterSB = UI.scrollbar(mlist, MVIS, MVIS * RH,
    function() return #(Wizard.masterData or {}) end,
    function() return Wizard.mScroll or 0 end,
    function(o) Wizard.mScroll = o; Wizard.refreshMaster() end)

  local divider = panel:CreateTexture(nil, "ARTWORK")
  divider:SetPoint("TOPLEFT", 234, -140); divider:SetPoint("BOTTOMLEFT", 234, 8)
  divider:SetWidth(1); divider:SetColorTexture(0, 0, 0, 0.15)

  -- Detail column: cities of the selected country (or search results). Header
  -- sits below the search box, aligned with the master's COUNTRIES row.
  Wizard.detailHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  Wizard.detailHeader:SetPoint("TOPLEFT", 244, -144)
  local dlist = CreateFrame("Frame", nil, panel)
  dlist:SetPoint("TOPLEFT", 244, -162); dlist:SetSize(252, DVIS * RH)
  dlist:EnableMouseWheel(true); dlist:SetScript("OnMouseWheel", function(_, d) Wizard.scrollDetail(d) end)
  Wizard.detailPool = {}
  for i = 1, DVIS do
    local row = CreateFrame("Button", nil, dlist)
    row:SetSize(252, RH); row:SetPoint("TOPLEFT", 0, -(i - 1) * RH)
    local hl = row:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(); hl:SetColorTexture(unpack(C.rowHl)); hl:Hide(); row.hl = hl
    local check = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    check:SetPoint("RIGHT", -8, 0); row.check = check
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 10, 0); label:SetJustifyH("LEFT"); label:SetTextColor(unpack(C.text)); row.label = label
    row:SetScript("OnClick", function(self) if self.name then Wizard.selectCity(self.name) end end)
    Wizard.detailPool[i] = row
  end
  Wizard.detailSB = UI.scrollbar(dlist, DVIS, DVIS * RH,
    function() return #(Wizard.detailData or {}) end,
    function() return Wizard.dScroll or 0 end,
    function(o) Wizard.dScroll = o; Wizard.refreshDetail() end)
end

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

  -- Location page (3W-2).
  buildLocationPage(Wizard.pages[2])

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
    -- Raised above the Back/Skip/Next row (button top ~44px) so the dots never
    -- slide underneath the buttons.
    dot:SetPoint("BOTTOM", f, "BOTTOM", -totalW / 2 + (i - 1) * gap, 58)
    dot:SetColorTexture(unpack(COL.dotOff))
    Wizard.dots[i] = dot
  end

  Wizard.frame = f
  Wizard.mScroll, Wizard.dScroll = 0, 0
  Wizard.refreshLocation("")
  Wizard.go(1)
  return f
end

function Wizard.open()
  if Picker.close then Picker.close() end -- never show both windows at once
  Wizard.create()
  Wizard.refreshLocation(Wizard.searchBox and Wizard.searchBox:GetText() or "")
  Wizard.go(1)
  Wizard.frame:Show()
end

function Wizard.close()
  if Wizard.frame then Wizard.frame:Hide() end
end

if PrayerTimesNS then PrayerTimesNS.modules.Wizard = Wizard end
return Wizard
