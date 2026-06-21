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
local Picker = require("Picker") -- reuse its pure builders + styled components

local Wizard = {}

-- Palette shared with the settings window (cream / charcoal / gold).
local COL = {
  header = { 0.30, 0.22, 0.12, 1 }, -- warm brown title bar, distinct from cream
  headerAccent = { 0.72, 0.58, 0.29, 1 },
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
  -- Master (countries) has no button beneath it, so it runs taller — its bottom
  -- lines up with the Add-custom button's bottom edge, using the otherwise empty
  -- left-column space. Detail stays shorter to leave room for the Add button.
  local MVIS, DVIS, RH = 9, 6, 18

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
    local mark = row:CreateTexture(nil, "OVERLAY")
    mark:SetSize(20, 20); mark:SetPoint("RIGHT", -6, 0)
    mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check"); mark:Hide(); row.mark = mark
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 10, 0); label:SetJustifyH("LEFT"); label:SetTextColor(unpack(C.text)); row.label = label
    row:SetScript("OnClick", function(self) if self.name then Wizard.selectCity(self.name) end end)
    Wizard.detailPool[i] = row
  end
  Wizard.detailSB = UI.scrollbar(dlist, DVIS, DVIS * RH,
    function() return #(Wizard.detailData or {}) end,
    function() return Wizard.dScroll or 0 end,
    function(o) Wizard.dScroll = o; Wizard.refreshDetail() end)

  -- "+ Add custom location" opens the add-form overlay. Anchored just below the
  -- detail list (fixed gap) so it never crowds the step dots near the footer.
  local addBtn = UI.flatButton(panel, "+ Add custom location", true)
  addBtn:SetSize(252, 24); addBtn:SetPoint("TOPRIGHT", dlist, "BOTTOMRIGHT", 0, -12)
  addBtn:SetScript("OnClick", function() Wizard.openAddPanel() end)

  -- Add-custom-location overlay: opaque cream, raised above the browse view and
  -- mouse-enabled so clicks don't fall through to the lists beneath.
  local ap = CreateFrame("Frame", nil, panel)
  ap:SetPoint("TOPLEFT", 24, -50); ap:SetPoint("BOTTOMRIGHT", -24, 8)
  ap:SetFrameLevel(panel:GetFrameLevel() + 10); ap:EnableMouse(true)
  local apbg = ap:CreateTexture(nil, "BACKGROUND"); apbg:SetAllPoints(); apbg:SetColorTexture(unpack(C.content))
  ap:Hide(); Wizard.addPanel = ap

  local at = ap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  at:SetPoint("TOPLEFT", 4, -6); at:SetText("ADD CUSTOM LOCATION"); at:SetTextColor(unpack(C.gold))

  UI.colLabel(ap, "Lat", 6, -28)
  UI.colLabel(ap, "Lon", 92, -28)
  UI.colLabel(ap, "UTC+/-", 178, -28)
  local boxY = -42
  local latBox = UI.flatEditBox(ap); latBox:SetSize(76, 22); latBox:SetPoint("TOPLEFT", 4, boxY)
  local lonBox = UI.flatEditBox(ap); lonBox:SetSize(76, 22); lonBox:SetPoint("TOPLEFT", 90, boxY)
  local offBox = UI.flatEditBox(ap); offBox:SetSize(62, 22); offBox:SetPoint("TOPLEFT", 176, boxY)
  local euCheck = UI.flatCheck(ap); euCheck:SetPoint("TOPLEFT", 252, boxY - 2)
  local euText = ap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  euText:SetPoint("LEFT", euCheck, "RIGHT", 6, 0); euText:SetText("EU DST"); euText:SetTextColor(unpack(C.text))

  local nameLabelY = boxY - 30
  UI.colLabel(ap, "Name", 6, nameLabelY)
  local nameBox = UI.flatEditBox(ap); nameBox:SetHeight(22)
  nameBox:SetPoint("TOPLEFT", 4, nameLabelY - 16); nameBox:SetPoint("RIGHT", ap, "RIGHT", -4, 0)
  Wizard.nameBox, Wizard.latBox, Wizard.lonBox, Wizard.offsetBox, Wizard.euCheck =
    nameBox, latBox, lonBox, offBox, euCheck

  local clearErr = function() Wizard.clearError() end
  nameBox:SetScript("OnTextChanged", clearErr); latBox:SetScript("OnTextChanged", clearErr)
  lonBox:SetScript("OnTextChanged", clearErr); offBox:SetScript("OnTextChanged", clearErr)

  local btnY = nameLabelY - 46
  local saveBtn = UI.flatButton(ap, "Save as My City", true)
  saveBtn:SetSize(170, 26); saveBtn:SetPoint("TOPLEFT", 4, btnY)
  saveBtn:SetScript("OnClick", function()
    if Wizard.saveManual(nameBox:GetText(), latBox:GetText(), lonBox:GetText(), offBox:GetText(), euCheck:GetChecked()) then
      Wizard.closeAddPanel()
    end
  end)
  local backBtn = UI.flatButton(ap, "Back")
  backBtn:SetSize(90, 26); backBtn:SetPoint("TOPRIGHT", ap, "TOPRIGHT", -4, btnY)
  backBtn:SetScript("OnClick", function() Wizard.closeAddPanel() end)
  local useBtn = UI.flatButton(ap, "Use once")
  useBtn:SetSize(120, 26); useBtn:SetPoint("LEFT", saveBtn, "RIGHT", 10, 0)
  useBtn:SetScript("OnClick", function()
    if Wizard.applyManual(latBox:GetText(), lonBox:GetText(), offBox:GetText()) then Wizard.closeAddPanel() end
  end)

  local function tabTo(a, b) a:SetScript("OnTabPressed", function() b:SetFocus() end) end
  tabTo(latBox, lonBox); tabTo(lonBox, offBox); tabTo(offBox, nameBox); tabTo(nameBox, latBox)

  Wizard.errorLabel = ap:CreateFontString(nil, "OVERLAY", "GameFontRed")
  Wizard.errorLabel:SetPoint("TOPLEFT", 4, btnY - 24)
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
      if c.bg then c.bg:SetColorTexture(unpack(on and C.cardSel or C.cardOff)) end
      if c.border then if on then c.border:Show() else c.border:Hide() end end
      if c.title then c.title:SetTextColor(unpack(on and C.gold or C.text)) end
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
  mLabel:SetPoint("TOPLEFT", 24, -58); mLabel:SetText("CALCULATION METHOD"); mLabel:SetTextColor(unpack(C.gold))

  Wizard.methodDropdown = UI.dropdown(panel, {
    width = 448, rows = 10,
    getOptions = function() return Methods.list() end,
    getCurrent = function() return Methods.resolveMethod(Wizard.db and Wizard.db.method) end,
    onSelect = function(key) Wizard.setMethod(key) end,
  })
  Wizard.methodDropdown.button:SetPoint("TOPLEFT", 24, -76)

  local mHint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  mHint:SetPoint("TOPLEFT", 24, -108); mHint:SetWidth(448); mHint:SetJustifyH("LEFT")
  mHint:SetText("Sets the Fajr/Isha twilight angles. Default (Muslim World League) suits most of Europe.")
  mHint:SetTextColor(unpack(C.muted))

  local aLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  aLabel:SetPoint("TOPLEFT", 24, -146); aLabel:SetText("ASR SCHOOL"); aLabel:SetTextColor(unpack(C.gold))

  Wizard.asrCards = {}
  local cardW = 226
  for i, a in ipairs(Methods.asrList()) do
    local card = CreateFrame("Button", nil, panel)
    card:SetSize(cardW, 88); card:SetPoint("TOPLEFT", 24 + (i - 1) * (cardW + 12), -164)
    card.key = a.key
    local cbg = card:CreateTexture(nil, "BACKGROUND"); cbg:SetAllPoints(); cbg:SetColorTexture(unpack(C.cardOff)); card.bg = cbg
    local barT = card:CreateTexture(nil, "ARTWORK")
    barT:SetPoint("TOPLEFT", 0, 0); barT:SetPoint("BOTTOMLEFT", 0, 0); barT:SetWidth(3)
    barT:SetColorTexture(unpack(C.gold)); barT:Hide(); card.border = barT
    local ct = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ct:SetPoint("TOPLEFT", 12, -12); ct:SetText(a.label); ct:SetTextColor(unpack(C.text)); card.title = ct
    local cd = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cd:SetPoint("TOPLEFT", 12, -32); cd:SetWidth(cardW - 24); cd:SetJustifyH("LEFT")
    cd:SetText(ASR_DESC[a.key] or ""); cd:SetTextColor(unpack(C.muted))
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
    t:SetPoint("TOPLEFT", 24, y); t:SetText(title); t:SetTextColor(unpack(C.text))
    local d = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d:SetPoint("TOPLEFT", 24, y - 18); d:SetWidth(360); d:SetJustifyH("LEFT")
    d:SetText(desc); d:SetTextColor(unpack(C.muted))
  end
  local function separator(y)
    local s = panel:CreateTexture(nil, "ARTWORK")
    s:SetPoint("TOPLEFT", 24, y); s:SetPoint("TOPRIGHT", -24, y); s:SetHeight(1)
    s:SetColorTexture(0, 0, 0, 0.12)
  end

  local nlabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nlabel:SetPoint("TOPLEFT", 24, -58); nlabel:SetText("REMINDER BEFORE PRAYER"); nlabel:SetTextColor(unpack(C.gold))

  -- Before-prayer minutes stepper.
  notifRow(-80, "Alert before each prayer", "Applies to all five daily prayers. Set to Off to disable.")
  local minusBtn = UI.flatButton(panel, "-")
  minusBtn:SetSize(28, 24); minusBtn:SetPoint("TOPRIGHT", -128, -78)
  minusBtn:SetScript("OnClick", function() Wizard.stepBeforeMinutes(-1) end)
  Wizard.beforeValue = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  Wizard.beforeValue:SetPoint("TOPRIGHT", -64, -84); Wizard.beforeValue:SetWidth(58); Wizard.beforeValue:SetJustifyH("CENTER")
  Wizard.beforeValue:SetTextColor(unpack(C.text))
  local plusBtn = UI.flatButton(panel, "+")
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
  local accent = f:CreateTexture(nil, "ARTWORK")
  accent:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0); accent:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
  accent:SetHeight(2); accent:SetColorTexture(unpack(COL.headerAccent))
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

  -- Location (3W-2) + Calculation (3W-3) + Notifications (3W-4) pages.
  buildLocationPage(Wizard.pages[2])
  buildCalculationPage(Wizard.pages[3])
  buildNotificationsPage(Wizard.pages[4])

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
    dot:SetColorTexture(unpack(COL.dotOff))
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

if PrayerTimesNS then PrayerTimesNS.modules.Wizard = Wizard end
return Wizard
