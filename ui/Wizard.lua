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
local Methods = require("Methods")
local Icons = require("Icons")
local Theme = require("Theme")
local L = require("Locale").L
local Picker = require("Picker") -- reuse its pure builders + styled components

local Wizard = {}

-- Colours come from the Theme module (ADR-0009).

-- Ordered pages. Only "welcome" has content in 3W-1; the rest are empty cream
-- containers (with a heading) that later checkpoints populate.
local PAGES = {
  { key = "welcome",       title = L["Welcome"],       sub = "About MyPrayerTimes" },
  { key = "location",      title = L["Location"],      sub = "Where are you?" },
  { key = "calculation",   title = L["Calculation"],   sub = "Method & Asr" },
  { key = "notifications", title = L["Notifications"], sub = "Alerts & sound" },
  { key = "finish",        title = L["All set"],       sub = "You're ready" },
}
Wizard.PAGES = PAGES

function Wizard.init(db)
  Wizard.db = db
  if db and not db.notify then
    db.notify = { beforeMinutes = 10, atTime = true, sound = true, fired = {} }
  end
end

-- The wizard is shown on first run only, gated by the persisted flag.
function Wizard.shouldOpen(db)
  return not (db and db.welcomed)
end

-- ----- small self-contained widgets (cream/gold, no Blizzard art) ----------

local function makeBtn(parent, text, primary)
  local b = CreateFrame("Button", nil, parent)
  local border = b:CreateTexture(nil, "BACKGROUND"); border:SetAllPoints(); Theme.tex(border, "line")
  -- Fill on the BORDER layer (one above BACKGROUND) so it always draws on top of
  -- the outline regardless of texture creation order.
  local fill = b:CreateTexture(nil, "BORDER")
  fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1)
  local baseRole = primary and "btnPrimary" or "btnSecondary"
  local hovRole = primary and "btnPrimaryHover" or "btnSecondaryHover"
  Theme.tex(fill, baseRole)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("CENTER"); fs:SetText(text); Theme.txt(fs, "btnText")
  b:SetScript("OnEnter", function() fill:SetColorTexture(unpack(Theme.color(hovRole))) end)
  b:SetScript("OnLeave", function() fill:SetColorTexture(unpack(Theme.color(baseRole))) end)
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
      d:SetColorTexture(unpack(n == i and Theme.color("gold") or Theme.color("dotOff")))
    end
  end
  if Wizard.backBtn then Wizard.backBtn:SetShown(i > 1) end
  if Wizard.skipBtn then Wizard.skipBtn:SetShown(not Wizard.isLast()) end
  if Wizard.nextBtn then Wizard.nextBtn.label:SetText(Wizard.isLast() and "Done" or "Next") end
  if Wizard.stepText then
    Wizard.stepText:SetText(string.format("STEP %d / %d", i, #PAGES))
  end
  if Wizard.updateSummary then Wizard.updateSummary() end -- keep the Finish page current
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
    row.mark:Hide(); row.hl:Hide(); row.name = nil
    if not e then
      row:Hide()
    else
      row.label:SetText(e.city.name); row.name = e.city.name
      if e.city.name == selCity then row.hl:Show(); row.mark:Show() end
      row:Show()
    end
  end
  if Wizard.detailSB then Wizard.detailSB:update() end
end

function Wizard.scrollMaster(d) Wizard.mScroll = math.max(0, (Wizard.mScroll or 0) - d); Wizard.refreshMaster() end
function Wizard.scrollDetail(d) Wizard.dScroll = math.max(0, (Wizard.dScroll or 0) - d); Wizard.refreshDetail() end

-- Add-custom-location form (same Selection logic as the settings window; opaque
-- cream overlay raised above the browse view so nothing shows through).
function Wizard.clearError()
  if Wizard.errorLabel then Wizard.errorLabel:SetText("") end
end

function Wizard.openAddPanel()
  Wizard.clearError()
  if Wizard.addPanel then Wizard.addPanel:Show() end
end

function Wizard.closeAddPanel()
  if Wizard.addPanel then Wizard.addPanel:Hide() end
end

-- Save a named "My City". euDst applies only when an offset is given.
function Wizard.saveManual(name, latText, lonText, offsetText, euDst)
  local lat, lon = tonumber(latText), tonumber(lonText)
  local opts = {}
  if offsetText and offsetText ~= "" then
    local hours = tonumber(offsetText)
    if not hours then
      if Wizard.errorLabel then Wizard.errorLabel:SetText("Offset must be a number") end
      return false
    end
    opts.tz, opts.baseUtcOffset = "fixed", math.floor(hours * 60 + 0.5)
    opts.dstRule = euDst and "EU" or "none"
  end
  local ok, err, savedName = Selection.saveCity(Wizard.db, name, lat, lon, opts)
  if ok then
    Wizard.clearError()
    Selection.setSavedCity(Wizard.db, savedName)
    afterLocationChange()
  elseif Wizard.errorLabel then
    Wizard.errorLabel:SetText(err or "Could not save")
  end
  return ok
end

-- One-off manual location (not saved). Empty lat+lon = no-op (not an error).
function Wizard.applyManual(latText, lonText, offsetText)
  if (not latText or latText == "") and (not lonText or lonText == "") then
    Wizard.clearError(); return false
  end
  local lat, lon = tonumber(latText), tonumber(lonText)
  local opts = {}
  if offsetText and offsetText ~= "" then
    local hours = tonumber(offsetText)
    if not hours then
      if Wizard.errorLabel then Wizard.errorLabel:SetText("Offset must be a number (hours from UTC)") end
      return false
    end
    opts.tz, opts.baseUtcOffset, opts.dstRule = "fixed", math.floor(hours * 60 + 0.5), "none"
  end
  local ok, err = Selection.setManual(Wizard.db, lat, lon, opts)
  if ok then
    Wizard.clearError(); afterLocationChange()
  elseif Wizard.errorLabel then
    Wizard.errorLabel:SetText(err or "Invalid coordinates")
  end
  return ok
end

-- Build the Location page UI into its panel. Uses the cream/gold palette and
-- styled component factories exported by the settings window.
local function buildLocationPage(panel)
  local C, UI = Picker.COL, Picker.ui
  -- Both columns end at about the same height; the global "Add custom location"
  -- action is a full-width bar below them (built further down).
  local MVIS, DVIS, RH = 7, 6, 18

  -- Current-location card.
  local card = panel:CreateTexture(nil, "BACKGROUND")
  card:SetPoint("TOPLEFT", 24, -54); card:SetSize(472, 42); Theme.tex(card, "card")
  local cl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  cl:SetPoint("TOPLEFT", 36, -60); cl:SetText("CURRENT LOCATION"); Theme.txt(cl, "gold")
  Wizard.cardCity = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  Wizard.cardCity:SetPoint("TOPLEFT", 36, -74); Theme.txt(Wizard.cardCity, "onDark")
  Wizard.cardCountry = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  Wizard.cardCountry:SetPoint("TOPRIGHT", -36, -76); Theme.txt(Wizard.cardCountry, "dimText")

  -- Search across all cities (flat cream field + placeholder).
  local search = CreateFrame("EditBox", "PrayerTimesWizardSearch", panel)
  search:SetSize(472, 24); search:SetPoint("TOPLEFT", 24, -106); search:SetAutoFocus(false)
  search:SetFontObject("GameFontHighlight"); Theme.txt(search, "text"); search:SetTextInsets(10, 10, 0, 0)
  search:SetScript("OnEscapePressed", search.ClearFocus)
  local sb = search:CreateTexture(nil, "BACKGROUND"); sb:SetAllPoints(); Theme.tex(sb, "line")
  local sf = search:CreateTexture(nil, "BORDER")
  sf:SetPoint("TOPLEFT", 1, -1); sf:SetPoint("BOTTOMRIGHT", -1, 1); Theme.tex(sf, "cardOff")
  local ph = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ph:SetPoint("LEFT", 10, 0); ph:SetText("Search all cities..."); Theme.txt(ph, "muted")
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
    local hl = row:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(); Theme.tex(hl, "rowHl"); hl:Hide(); row.hl = hl
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 8, 0); label:SetPoint("RIGHT", row, "RIGHT", -22, 0)
    label:SetJustifyH("LEFT"); label:SetWordWrap(false); Theme.txt(label, "text"); row.label = label
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
  divider:SetWidth(1); Theme.tex(divider, "divider")

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
    local hl = row:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(); Theme.tex(hl, "rowHl"); hl:Hide(); row.hl = hl
    local mark = row:CreateTexture(nil, "OVERLAY")
    mark:SetSize(16, 16); mark:SetPoint("RIGHT", -6, 0)
    Icons.setUI(mark, "check", unpack(Theme.color("gold"))); mark:Hide(); row.mark = mark
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 10, 0); label:SetJustifyH("LEFT"); Theme.txt(label, "text"); row.label = label
    row:SetScript("OnClick", function(self) if self.name then Wizard.selectCity(self.name) end end)
    Wizard.detailPool[i] = row
  end
  Wizard.detailSB = UI.scrollbar(dlist, DVIS, DVIS * RH,
    function() return #(Wizard.detailData or {}) end,
    function() return Wizard.dScroll or 0 end,
    function(o) Wizard.dScroll = o; Wizard.refreshDetail() end)

  -- Global "Add custom location": a full-width bar below BOTH columns, with a
  -- separator, so it reads as "enter your own coordinates" rather than "add a
  -- city to the selected country".
  local addBtn = UI.flatButton(panel, "+ Add custom location", true)
  addBtn:SetHeight(26)
  addBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 24, 12)
  addBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 12)
  addBtn:SetScript("OnClick", function() Wizard.openAddPanel() end)
  local addSep = panel:CreateTexture(nil, "ARTWORK")
  addSep:SetPoint("BOTTOMLEFT", addBtn, "TOPLEFT", 0, 10); addSep:SetPoint("BOTTOMRIGHT", addBtn, "TOPRIGHT", 0, 10)
  addSep:SetHeight(1); Theme.tex(addSep, "divider")

  -- Add-custom-location overlay: opaque cream, raised above the browse view and
  -- mouse-enabled so clicks don't fall through to the lists beneath.
  -- Flush to the page so the form's fields share the same 24px margins as the
  -- card/search/lists above (the cream bg matches the page, so flush is invisible).
  local ap = CreateFrame("Frame", nil, panel)
  ap:SetPoint("TOPLEFT", 0, -50); ap:SetPoint("BOTTOMRIGHT", 0, 8)
  ap:SetFrameLevel(panel:GetFrameLevel() + 10); ap:EnableMouse(true)
  local apbg = ap:CreateTexture(nil, "BACKGROUND"); apbg:SetAllPoints(); Theme.tex(apbg, "content")
  ap:Hide(); Wizard.addPanel = ap

  local at = ap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  at:SetPoint("TOPLEFT", 24, -6); at:SetText("ADD CUSTOM LOCATION"); Theme.txt(at, "gold")

  UI.colLabel(ap, "Lat", 24, -28)
  UI.colLabel(ap, "Lon", 110, -28)
  UI.colLabel(ap, "UTC+/-", 196, -28)
  local boxY = -42
  local latBox = UI.flatEditBox(ap); latBox:SetSize(76, 22); latBox:SetPoint("TOPLEFT", 24, boxY)
  local lonBox = UI.flatEditBox(ap); lonBox:SetSize(76, 22); lonBox:SetPoint("TOPLEFT", 110, boxY)
  local offBox = UI.flatEditBox(ap); offBox:SetSize(62, 22); offBox:SetPoint("TOPLEFT", 196, boxY)
  local euCheck = UI.flatCheck(ap); euCheck:SetPoint("TOPLEFT", 272, boxY - 2)
  local euText = ap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  euText:SetPoint("LEFT", euCheck, "RIGHT", 6, 0); euText:SetText("EU DST"); Theme.txt(euText, "text")

  local nameLabelY = boxY - 30
  UI.colLabel(ap, "Name", 24, nameLabelY)
  local nameBox = UI.flatEditBox(ap); nameBox:SetHeight(22)
  nameBox:SetPoint("TOPLEFT", 24, nameLabelY - 16); nameBox:SetPoint("RIGHT", ap, "RIGHT", -24, 0)
  Wizard.nameBox, Wizard.latBox, Wizard.lonBox, Wizard.offsetBox, Wizard.euCheck =
    nameBox, latBox, lonBox, offBox, euCheck

  local clearErr = function() Wizard.clearError() end
  nameBox:SetScript("OnTextChanged", clearErr); latBox:SetScript("OnTextChanged", clearErr)
  lonBox:SetScript("OnTextChanged", clearErr); offBox:SetScript("OnTextChanged", clearErr)

  local btnY = nameLabelY - 46
  local saveBtn = UI.flatButton(ap, "Save as My City", true)
  saveBtn:SetSize(170, 26); saveBtn:SetPoint("TOPLEFT", 24, btnY)
  saveBtn:SetScript("OnClick", function()
    if Wizard.saveManual(nameBox:GetText(), latBox:GetText(), lonBox:GetText(), offBox:GetText(), euCheck:GetChecked()) then
      Wizard.closeAddPanel()
    end
  end)
  local backBtn = UI.flatButton(ap, "Back")
  backBtn:SetSize(90, 26); backBtn:SetPoint("TOPRIGHT", ap, "TOPRIGHT", -24, btnY)
  backBtn:SetScript("OnClick", function() Wizard.closeAddPanel() end)
  local useBtn = UI.flatButton(ap, "Use once")
  useBtn:SetSize(120, 26); useBtn:SetPoint("LEFT", saveBtn, "RIGHT", 10, 0)
  useBtn:SetScript("OnClick", function()
    if Wizard.applyManual(latBox:GetText(), lonBox:GetText(), offBox:GetText()) then Wizard.closeAddPanel() end
  end)

  local function tabTo(a, b) a:SetScript("OnTabPressed", function() b:SetFocus() end) end
  tabTo(latBox, lonBox); tabTo(lonBox, offBox); tabTo(offBox, nameBox); tabTo(nameBox, latBox)

  Wizard.errorLabel = ap:CreateFontString(nil, "OVERLAY", "GameFontRed")
  Wizard.errorLabel:SetPoint("TOPLEFT", 24, btnY - 24)

  -- Short how-to for the empty space below the form: getting exact coordinates
  -- from Google Maps. Kept brief and word-wrapped to the panel width.
  local helpHead = ap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  helpHead:SetPoint("TOPLEFT", 24, btnY - 46); helpHead:SetText("HOW TO FIND COORDINATES")
  Theme.txt(helpHead, "gold")
  local help = ap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  help:SetPoint("TOPLEFT", 24, btnY - 66); help:SetPoint("RIGHT", ap, "RIGHT", -24, 0)
  help:SetJustifyH("LEFT"); help:SetJustifyV("TOP"); help:SetSpacing(3)
  help:SetText(
    "1. Open Google Maps and right-click your city (or search for it).\n"
    .. "2. Click the latitude, longitude numbers at the top of the menu \226\128\148 "
    .. "the first number is Lat, the second is Lon.\n"
    .. "3. UTC+/- is your offset from GMT (Central Europe = 1). Tick EU DST if "
    .. "your country follows European summer time.")
  Theme.txt(help, "muted")
end

-- ----- Calculation page (3W-3): method dropdown + Asr cards -----------------
-- Same Methods registry and persisted db.method/db.madhab as the settings tab;
-- changing either re-runs the engine and refreshes the main window (and the
-- settings controls if that window has been built).

local function afterCalcChange()
  if Window.refresh then Window.refresh() end
  Wizard.updateCalcControls()
  if Picker.db and Picker.updateCalcControls then Picker.updateCalcControls() end
end

function Wizard.setMethod(key)
  if not Wizard.db then return end
  Wizard.db.method = Methods.resolveMethod(key); afterCalcChange()
end

function Wizard.setMadhab(key)
  if not Wizard.db then return end
  Wizard.db.madhab = Methods.resolveMadhab(key); afterCalcChange()
end

function Wizard.updateCalcControls()
  local C = Picker.COL
  if Wizard.methodDropdown then Wizard.methodDropdown:updateButton() end
  if Wizard.asrCards then
    local cur = Methods.resolveMadhab(Wizard.db and Wizard.db.madhab)
    for _, c in ipairs(Wizard.asrCards) do
      local on = (c.key == cur)
      c._selected = on
      if c.bg then c.bg:SetColorTexture(unpack(on and Theme.color("cardSel") or Theme.color("cardOff"))) end
      if c.border then if on then c.border:Show() else c.border:Hide() end end
      if c.title then c.title:SetTextColor(unpack(on and Theme.color("cardTitleOn") or Theme.color("cardTitleOff"))) end
      if c.desc then c.desc:SetTextColor(unpack(on and Theme.color("cardDescOn") or Theme.color("cardDescOff"))) end
    end
  end
end

local ASR_DESC = {
  shafi = "Shafi'i, Maliki, Hanbali -- Asr begins when an object's shadow equals its own length. The common choice.",
  hanafi = "Hanafi -- Asr begins when the shadow is twice the object's length, so Asr (and Maghrib) fall later.",
}

local function buildCalculationPage(panel)
  local C, UI = Picker.COL, Picker.ui

  local mLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  mLabel:SetPoint("TOPLEFT", 24, -58); mLabel:SetText("CALCULATION METHOD"); Theme.txt(mLabel, "gold")

  -- Content spans the page's 24px margins (left 24, right edge 496 = 520 - 24).
  Wizard.methodDropdown = UI.dropdown(panel, {
    width = 472, rows = 10,
    getOptions = function() return Methods.list() end,
    getCurrent = function() return Methods.resolveMethod(Wizard.db and Wizard.db.method) end,
    onSelect = function(key) Wizard.setMethod(key) end,
  })
  Wizard.methodDropdown.button:SetPoint("TOPLEFT", 24, -76)

  local mHint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  mHint:SetPoint("TOPLEFT", 24, -108); mHint:SetWidth(472); mHint:SetJustifyH("LEFT")
  mHint:SetText("Sets the Fajr/Isha twilight angles. Default (Muslim World League) suits most of Europe.")
  Theme.txt(mHint, "muted")

  local aLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  aLabel:SetPoint("TOPLEFT", 24, -146); aLabel:SetText("ASR SCHOOL"); Theme.txt(aLabel, "gold")

  Wizard.asrCards = {}
  local cardW = 230 -- two cards + 12 gap span the 472 content width (right edge 496)
  for i, a in ipairs(Methods.asrList()) do
    local card = CreateFrame("Button", nil, panel)
    card:SetSize(cardW, 88); card:SetPoint("TOPLEFT", 24 + (i - 1) * (cardW + 12), -164)
    card.key = a.key
    local cbg = card:CreateTexture(nil, "BACKGROUND"); cbg:SetAllPoints(); Theme.tex(cbg, "cardOff"); card.bg = cbg
    local barT = card:CreateTexture(nil, "ARTWORK")
    barT:SetPoint("TOPLEFT", 0, 0); barT:SetPoint("BOTTOMLEFT", 0, 0); barT:SetWidth(3)
    Theme.tex(barT, "gold"); barT:Hide(); card.border = barT
    local ct = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ct:SetPoint("TOPLEFT", 12, -12); ct:SetText(a.label); Theme.txt(ct, "text"); card.title = ct
    local cd = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cd:SetPoint("TOPLEFT", 12, -32); cd:SetWidth(cardW - 24); cd:SetJustifyH("LEFT")
    cd:SetText(ASR_DESC[a.key] or ""); Theme.txt(cd, "cardDescOff"); card.desc = cd
    card:SetScript("OnClick", function() Wizard.setMadhab(a.key) end)
    Wizard.asrCards[i] = card
  end
end

-- ----- Notifications page (3W-4): stepper + toggle switches -----------------
-- Wired to db.notify exactly like the settings tab; the Notifier reads it live,
-- so no engine/window refresh is needed when these change.

function Wizard.setBeforeMinutes(n)
  if not (Wizard.db and Wizard.db.notify) then return end
  Wizard.db.notify.beforeMinutes = math.max(0, math.floor(tonumber(n) or 0))
end
function Wizard.setAtTime(on)
  if Wizard.db and Wizard.db.notify then Wizard.db.notify.atTime = on and true or false end
end
function Wizard.setSound(on)
  if Wizard.db and Wizard.db.notify then Wizard.db.notify.sound = on and true or false end
end

function Wizard.updateNotifyControls()
  local n = Wizard.db and Wizard.db.notify
  if not n then return end
  if Wizard.beforeValue then
    local m = n.beforeMinutes or 0
    Wizard.beforeValue:SetText(m == 0 and "Off" or (m .. " min"))
  end
  if Wizard.atToggle then Wizard.atToggle:update() end
  if Wizard.soundToggle then Wizard.soundToggle:update() end
  if Wizard.themeToggle then Wizard.themeToggle:update() end
end

function Wizard.stepBeforeMinutes(delta)
  local n = Wizard.db and Wizard.db.notify
  if not n then return end
  Wizard.setBeforeMinutes((n.beforeMinutes or 0) + delta)
  Wizard.updateNotifyControls()
end

local function buildNotificationsPage(panel)
  local C, UI = Picker.COL, Picker.ui

  local function notifRow(y, title, desc)
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 24, y); t:SetText(title); Theme.txt(t, "text")
    local d = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d:SetPoint("TOPLEFT", 24, y - 18); d:SetWidth(360); d:SetJustifyH("LEFT")
    d:SetText(desc); Theme.txt(d, "muted")
  end
  local function separator(y)
    local s = panel:CreateTexture(nil, "ARTWORK")
    s:SetPoint("TOPLEFT", 24, y); s:SetPoint("TOPRIGHT", -24, y); s:SetHeight(1)
    Theme.tex(s, "divider")
  end

  local nlabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nlabel:SetPoint("TOPLEFT", 24, -58); nlabel:SetText("REMINDER BEFORE PRAYER"); Theme.txt(nlabel, "gold")

  -- Before-prayer minutes stepper.
  notifRow(-80, "Alert before each prayer", "Applies to all five daily prayers. Set to Off to disable.")
  local minusBtn = UI.flatButton(panel, "", false, "minus")
  minusBtn:SetSize(28, 24); minusBtn:SetPoint("TOPRIGHT", -128, -78)
  minusBtn:SetScript("OnClick", function() Wizard.stepBeforeMinutes(-1) end)
  Wizard.beforeValue = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  Wizard.beforeValue:SetPoint("TOPRIGHT", -64, -84); Wizard.beforeValue:SetWidth(58); Wizard.beforeValue:SetJustifyH("CENTER")
  Theme.txt(Wizard.beforeValue, "text")
  local plusBtn = UI.flatButton(panel, "", false, "plus")
  plusBtn:SetSize(28, 24); plusBtn:SetPoint("TOPRIGHT", -24, -78)
  plusBtn:SetScript("OnClick", function() Wizard.stepBeforeMinutes(1) end)

  separator(-118)

  notifRow(-134, "Alert exactly at prayer time", "Fire a notice the moment each prayer enters.")
  Wizard.atToggle = UI.toggle(panel,
    function() return Wizard.db and Wizard.db.notify and Wizard.db.notify.atTime end,
    function(v) Wizard.setAtTime(v) end)
  Wizard.atToggle.btn:SetPoint("TOPRIGHT", -24, -134)

  separator(-186)

  notifRow(-202, "Notification sound", "Play a chime with each alert.")
  Wizard.soundToggle = UI.toggle(panel,
    function() return Wizard.db and Wizard.db.notify and Wizard.db.notify.sound ~= false end,
    function(v) Wizard.setSound(v) end)
  Wizard.soundToggle.btn:SetPoint("TOPRIGHT", -24, -202)

  separator(-254)

  notifRow(-270, "Dark theme", "Use a dark colour palette across the addon.")
  Wizard.themeToggle = UI.toggle(panel,
    function() return Theme.isDark() end,
    function(v) Theme.set(v and "dark" or "light") end)
  Wizard.themeToggle.btn:SetPoint("TOPRIGHT", -24, -270)
end

-- ----- Finish page (3W-4): summary of the choices --------------------------

function Wizard.selectionText(db)
  local sel = Selection.get(db)
  if not sel then return "Rotterdam, Netherlands (default)" end
  if sel.kind == "city" then
    local c = Cities.findByName(sel.name)
    return c and (c.name .. ", " .. c.country) or sel.name
  elseif sel.kind == "saved" then
    return sel.name .. " (saved)"
  end
  return "Manual location"
end

function Wizard.notifyText(db)
  local n = (db and db.notify) or {}
  local parts = {}
  local before = n.beforeMinutes or 0
  parts[#parts + 1] = before == 0 and "no advance alert" or (before .. " min before")
  if n.atTime ~= false then parts[#parts + 1] = "at prayer time" end
  parts[#parts + 1] = (n.sound ~= false) and "sound on" or "sound off"
  return table.concat(parts, "  \194\183  ")
end

function Wizard.updateSummary()
  if not Wizard.sumLocation then return end
  local db = Wizard.db
  Wizard.sumLocation:SetText(Wizard.selectionText(db))
  Wizard.sumMethod:SetText(Methods.methodLabel(Methods.resolveMethod(db and db.method)))
  Wizard.sumAsr:SetText(Methods.madhabLabel(Methods.resolveMadhab(db and db.madhab)))
  Wizard.sumNotify:SetText(Wizard.notifyText(db))
end

local function buildFinishPage(panel)
  local C = Picker.COL

  local intro = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  intro:SetPoint("TOPLEFT", 24, -60); intro:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
  intro:SetJustifyH("LEFT"); Theme.txt(intro, "text")
  intro:SetText("You're all set. Here's what MyPrayerTimes will use:")

  local function sumRow(y, labelText)
    local l = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", 24, y); l:SetText(labelText); Theme.txt(l, "gold")
    local v = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    v:SetPoint("TOPLEFT", 150, y); v:SetWidth(340); v:SetJustifyH("LEFT"); Theme.txt(v, "text")
    return v
  end
  Wizard.sumLocation = sumRow(-104, "Location")
  Wizard.sumMethod   = sumRow(-132, "Method")
  Wizard.sumAsr      = sumRow(-160, "Asr school")
  Wizard.sumNotify   = sumRow(-188, "Reminders")

  local note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", 24, -228); note:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
  note:SetJustifyH("LEFT"); Theme.txt(note, "muted")
  note:SetText("Click Done to start. You can change any of this later from the settings window (/pt settings).")
end

-- A small, static preview of the main window for the Welcome page, so the first
-- screen has visual weight rather than text over empty space. Decorative only:
-- fixed sample values, no logic.
local PREVIEW_ROWS = {
  { key = "fajr",    label = "Fajr",    time = "04:20" },
  { key = "dhuhr",   label = "Dhuhr",   time = "13:45" },
  { key = "maghrib", label = "Maghrib", time = "22:06", isNext = true },
}
local function buildWelcomePreview(panel)
  local C = Picker.COL
  local PW, PH = 290, 148
  local pv = CreateFrame("Frame", nil, panel)
  pv:SetSize(PW, PH); pv:SetPoint("TOP", panel, "TOP", 0, -170)
  local border = pv:CreateTexture(nil, "BACKGROUND"); border:SetAllPoints(); Theme.tex(border, "winBorder")
  local bg = pv:CreateTexture(nil, "BORDER")
  bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1); Theme.tex(bg, "winBg")

  local hdr = pv:CreateTexture(nil, "ARTWORK")
  hdr:SetPoint("TOPLEFT", 1, -1); hdr:SetPoint("TOPRIGHT", -1, -1); hdr:SetHeight(24)
  Theme.tex(hdr, "header")
  local wm = pv:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  wm:SetPoint("LEFT", hdr, "LEFT", 8, 0); wm:SetText("MyPrayerTimes"); Theme.txt(wm, "gold")
  local cty = pv:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  cty:SetPoint("RIGHT", hdr, "RIGHT", -8, 0); cty:SetText("Rotterdam")

  for i, s in ipairs(PREVIEW_ROWS) do
    local y = -28 - (i - 1) * 26
    local row = CreateFrame("Frame", nil, pv)
    row:SetPoint("TOPLEFT", 6, y); row:SetPoint("TOPRIGHT", -6, y); row:SetHeight(24)
    if s.isNext then
      local hl = row:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(); Theme.tex(hl, "rowHl")
    end
    local slot = row:CreateTexture(nil, "BORDER"); slot:SetSize(18, 18); slot:SetPoint("LEFT", 6, 0)
    Theme.tex(slot, "slot")
    local icon = row:CreateTexture(nil, "ARTWORK"); icon:SetSize(12, 12); icon:SetPoint("CENTER", slot, "CENTER")
    Icons.apply(icon, s.key, s.isNext)
    local nm = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nm:SetPoint("LEFT", 32, 0); nm:SetText(s.label); Theme.txt(nm, "text")
    local tm = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tm:SetPoint("RIGHT", -10, 0); tm:SetText(s.time); Theme.txt(tm, "text")
  end

  local ftr = pv:CreateTexture(nil, "ARTWORK")
  ftr:SetPoint("BOTTOMLEFT", 1, 1); ftr:SetPoint("BOTTOMRIGHT", -1, 1); ftr:SetHeight(22)
  Theme.tex(ftr, "header")
  local cd = pv:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  cd:SetPoint("CENTER", ftr, "CENTER", 0, 0); cd:SetText("20:30  \194\183  1:35:43"); Theme.txt(cd, "onDark")

  -- Brand crest centred on the preview's top edge: the coin rises above it, the
  -- banner overlaps the header. On its own frame above the preview rows so it
  -- always draws on top.
  local crest = CreateFrame("Frame", nil, pv)
  crest:SetFrameLevel(pv:GetFrameLevel() + 20)
  crest:SetSize(104, 104)
  crest:SetPoint("CENTER", pv, "TOP", 0, -8)
  local crestTex = crest:CreateTexture(nil, "OVERLAY")
  crestTex:SetAllPoints()
  crestTex:SetTexture("Interface\\AddOns\\MyPrayerTimes\\Media\\logo.tga")

  Wizard.welcomePreview = pv
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
  body:SetAllPoints(); Theme.tex(body, "content")

  -- Dark header on the BORDER layer (above the cream body fill) so it always
  -- draws over it -- same deterministic fix used across the addon.
  local header = f:CreateTexture(nil, "BORDER")
  header:SetPoint("TOPLEFT", 0, 0); header:SetPoint("TOPRIGHT", 0, 0); header:SetHeight(46)
  Theme.tex(header, "wizHeader")
  local accent = f:CreateTexture(nil, "ARTWORK")
  accent:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0); accent:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
  accent:SetHeight(2); Theme.tex(accent, "gold")
  -- Header text: wordmark | SETUP (left) + step text (right), all the same size
  -- and vertically centred on the header, with a thin divider bar (matches the
  -- settings window header).
  local HFONT = 14
  local wm = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  wm:SetFont("Fonts\\FRIZQT__.TTF", HFONT, "")
  wm:SetPoint("LEFT", header, "LEFT", 16, 0); wm:SetText("MyPrayerTimes"); Theme.txt(wm, "gold")
  local wmBar = f:CreateTexture(nil, "OVERLAY")
  wmBar:SetSize(1, 16); wmBar:SetPoint("LEFT", wm, "RIGHT", 9, 0); Theme.tex(wmBar, "line")
  local wmSub = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  wmSub:SetFont("Fonts\\FRIZQT__.TTF", HFONT, "")
  wmSub:SetPoint("LEFT", wmBar, "RIGHT", 9, 0); wmSub:SetText("SETUP"); Theme.txt(wmSub, "dimText")
  Wizard.stepText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  Wizard.stepText:SetFont("Fonts\\FRIZQT__.TTF", HFONT, "")
  Wizard.stepText:SetPoint("RIGHT", header, "RIGHT", -16, 0); Theme.txt(Wizard.stepText, "dimText")


  -- One frame per page (content area between header and footer).
  Wizard.pages = {}
  for i, p in ipairs(PAGES) do
    -- Bottom edge raised to 68 (from 58) so the page content clears the step
    -- dots with the same gap the dots have to the footer buttons below them.
    local panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -36)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 68)
    local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h:SetPoint("TOPLEFT", 24, -22); h:SetText(p.title); Theme.txt(h, "text")
    panel.heading = h
    Wizard.pages[i] = panel
  end

  -- Welcome page content (3W-1).
  local intro = Wizard.pages[1]:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  intro:SetPoint("TOPLEFT", 24, -64); intro:SetPoint("RIGHT", Wizard.pages[1], "RIGHT", -24, 0)
  intro:SetJustifyH("LEFT"); intro:SetJustifyV("TOP"); Theme.txt(intro, "text")
  intro:SetText(
    "MyPrayerTimes shows the five daily prayer times for your location, "
    .. "calculated right here in the game \226\128\148 no internet needed.\n"
    .. "Let's set up your city, calculation method and reminders.")
  -- A small preview of the main window fills the rest of the first screen.
  buildWelcomePreview(Wizard.pages[1])

  -- Location (3W-2) + Calculation (3W-3) + Notifications (3W-4) pages.
  buildLocationPage(Wizard.pages[2])
  buildCalculationPage(Wizard.pages[3])
  buildNotificationsPage(Wizard.pages[4])
  buildFinishPage(Wizard.pages[5])

  -- Footer: Skip set apart on the left; Back + Next grouped together on the
  -- right (so the two navigation buttons sit side by side and Skip can't be hit
  -- by mistake when reaching for Back).
  Wizard.skipBtn = makeBtn(f, "Skip")
  Wizard.skipBtn:SetSize(90, 28); Wizard.skipBtn:SetPoint("BOTTOMLEFT", 16, 16)
  Wizard.skipBtn:SetScript("OnClick", function() Wizard.skip() end)

  Wizard.nextBtn = makeBtn(f, "Next", true)
  Wizard.nextBtn:SetSize(110, 28); Wizard.nextBtn:SetPoint("BOTTOMRIGHT", -16, 16)
  Wizard.nextBtn:SetScript("OnClick", function() Wizard.next() end)

  Wizard.backBtn = makeBtn(f, "Back")
  Wizard.backBtn:SetSize(90, 28)
  Wizard.backBtn:SetPoint("RIGHT", Wizard.nextBtn, "LEFT", -10, 0)
  Wizard.backBtn:SetScript("OnClick", function() Wizard.back() end)

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
    Theme.tex(dot, "dotOff")
    Wizard.dots[i] = dot
  end

  Wizard.frame = f
  Wizard.mScroll, Wizard.dScroll = 0, 0
  Wizard.refreshLocation("")
  Wizard.updateCalcControls()
  Wizard.updateNotifyControls()
  Wizard.go(1)
  return f
end

function Wizard.open()
  if Picker.close then Picker.close() end -- never show both windows at once
  Wizard.create()
  Wizard.closeAddPanel()
  Wizard.refreshLocation(Wizard.searchBox and Wizard.searchBox:GetText() or "")
  Wizard.updateCalcControls()
  Wizard.updateNotifyControls()
  Wizard.go(1)
  Wizard.frame:Show()
end

function Wizard.close()
  if Wizard.frame then Wizard.frame:Hide() end
end

-- Repaint the state-dependent colours on a theme change (the static chrome is
-- handled by Theme.apply's registry); only matters while the wizard is built.
function Wizard.applyTheme()
  if not Wizard.frame then return end
  Wizard.go(Wizard.step or 1)        -- step dots
  if Wizard.refreshLocation then Wizard.refreshLocation() end
  if Wizard.updateCalcControls then Wizard.updateCalcControls() end
  if Wizard.updateNotifyControls then Wizard.updateNotifyControls() end
end
Theme.addHook(function() Wizard.applyTheme() end)

if PrayerTimesNS then PrayerTimesNS.modules.Wizard = Wizard end
return Wizard
