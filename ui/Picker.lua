-- Picker.lua
-- City picker / welcome / settings window (WoW-side widgets). Selection,
-- grouping, search, validation and saved "My Cities" live in the pure modules
-- (Selection, Cities); this file renders them and wires clicks. Logic entry
-- points are exposed so the runner can drive them under the mock.

local Cities = require("Cities")
local Selection = require("Selection")
local Window = require("Window")
local Methods = require("Methods")

local VISIBLE_ROWS = 14
local ROW_HEIGHT = 16

local Picker = {}

function Picker.init(db)
  Picker.db = db
  if db then
    if not db.notify then
      db.notify = { beforeMinutes = 10, atTime = true, sound = true, fired = {} }
    end
    db.savedCities = db.savedCities or {}
  end
end

-- Combined picker rows: "My Cities" (saved) first, then the built-in list.
-- Pure (no widgets) so the runner can verify it.
function Picker.buildRows(db, query)
  local rows = {}
  local saved = Selection.getSavedCities(db)
  local matches = {}
  if not query or query == "" then
    matches = saved
  else
    local q = query:lower()
    for _, c in ipairs(saved) do
      if c.name:lower():find(q, 1, true) then matches[#matches + 1] = c end
    end
  end
  if #matches > 0 then
    rows[#rows + 1] = { kind = "header", label = "My Cities" }
    for _, c in ipairs(matches) do rows[#rows + 1] = { kind = "saved", city = c } end
  end
  for _, r in ipairs(Cities.displayList(query)) do rows[#rows + 1] = r end
  return rows
end

local function tzText(entry)
  if entry.tz == "fixed" then
    return string.format("UTC%+d", math.floor((entry.baseUtcOffset or 0) / 60))
  end
  return "my timezone"
end

-- "Selected: ..." indicator text for the active selection.
function Picker.currentSelectionText(db)
  local sel = Selection.get(db)
  if not sel then return "Selected: Rotterdam (default)" end
  if sel.kind == "city" then
    local c = Cities.findByName(sel.name)
    return "Selected: " .. (c and (c.name .. ", " .. c.country) or sel.name)
  elseif sel.kind == "saved" then
    local s = Selection.findSaved(db, sel.name)
    return "Selected: " .. sel.name .. " (saved, " .. (s and tzText(s) or "?") .. ")"
  end
  return string.format("Selected: Manual %.4f, %.4f (%s)", sel.latitude, sel.longitude,
    sel.tz == "fixed" and string.format("UTC%+d", math.floor((sel.baseUtcOffset or 0) / 60)) or "my timezone")
end

function Picker.shouldAutoOpen(db)
  return Selection.get(db) == nil
end

function Picker.clearError()
  if Picker.errorLabel then Picker.errorLabel:SetText("") end
end

function Picker.updateSelected()
  if Picker.selectedLabel then
    Picker.selectedLabel:SetText(Picker.currentSelectionText(Picker.db))
  end
end

-- Selection actions (persist + update main window + indicator + list).
local function afterSelectionChange()
  if Window.refresh then Window.refresh() end
  Picker.updateSelected()
  Picker.refreshList(Picker.searchBox and Picker.searchBox:GetText() or "")
end

function Picker.selectCity(name)
  Selection.setCity(Picker.db, name)
  afterSelectionChange()
end

function Picker.selectSaved(name)
  Selection.setSavedCity(Picker.db, name)
  afterSelectionChange()
end

function Picker.deleteSaved(name)
  Selection.deleteCity(Picker.db, name)
  afterSelectionChange()
end

function Picker.selectCityByName(name)
  local city = Cities.findByName(name)
  if not city then return nil end
  Picker.selectCity(city.name)
  return city.name
end

-- One-off manual location (not saved). Empty fields = no-op (not an error).
function Picker.applyManual(latText, lonText, offsetText)
  if (not latText or latText == "") and (not lonText or lonText == "") then
    Picker.clearError()
    return false
  end
  local lat, lon = tonumber(latText), tonumber(lonText)
  local opts = {}
  if offsetText and offsetText ~= "" then
    local hours = tonumber(offsetText)
    if not hours then return false, "Offset must be a number (hours from UTC)" end
    opts.tz, opts.baseUtcOffset, opts.dstRule = "fixed", math.floor(hours * 60 + 0.5), "none"
  end
  local ok, err = Selection.setManual(Picker.db, lat, lon, opts)
  if ok then
    Picker.clearError(); afterSelectionChange()
  elseif Picker.errorLabel then
    Picker.errorLabel:SetText(err or "Invalid coordinates")
  end
  return ok, err
end

-- Save a named "My City". euDst applies only when an offset is given.
function Picker.saveManual(name, latText, lonText, offsetText, euDst)
  local lat, lon = tonumber(latText), tonumber(lonText)
  local opts = {}
  if offsetText and offsetText ~= "" then
    local hours = tonumber(offsetText)
    if not hours then
      if Picker.errorLabel then Picker.errorLabel:SetText("Offset must be a number") end
      return false, "Offset must be a number"
    end
    opts.tz, opts.baseUtcOffset = "fixed", math.floor(hours * 60 + 0.5)
    opts.dstRule = euDst and "EU" or "none"
  end
  local ok, err, savedName = Selection.saveCity(Picker.db, name, lat, lon, opts)
  if ok then
    Picker.clearError()
    Selection.setSavedCity(Picker.db, savedName)
    afterSelectionChange()
  elseif Picker.errorLabel then
    Picker.errorLabel:SetText(err or "Could not save")
  end
  return ok, err
end

-- Render the current query into the visible row pool, with selection highlight
-- and delete buttons on saved rows.
function Picker.refreshList(query)
  Picker.displayRows = Picker.buildRows(Picker.db, query)
  local maxOffset = math.max(0, #Picker.displayRows - VISIBLE_ROWS)
  Picker.scrollOffset = math.min(Picker.scrollOffset or 0, maxOffset)
  if not Picker.rows then return end
  local sel = Selection.get(Picker.db)
  local selCity = sel and sel.kind == "city" and sel.name or nil
  local selSaved = sel and sel.kind == "saved" and sel.name or nil

  for i = 1, VISIBLE_ROWS do
    local row = Picker.rows[i]
    local entry = Picker.displayRows[Picker.scrollOffset + i]
    if row.delBtn then row.delBtn:Hide() end
    if not entry then
      row.kind, row.cityName, row.entryName, row._selected = nil, nil, nil, false
      if row.hl then row.hl:Hide() end
      row:Hide()
    elseif entry.kind == "header" then
      row.label:SetText("|cffffd100" .. entry.label .. "|r")
      row.kind, row.cityName, row.entryName, row._selected = "header", nil, nil, false
      if row.hl then row.hl:Hide() end
      row:Show()
    elseif entry.kind == "saved" then
      local c = entry.city
      local isSel = (c.name == selSaved)
      local mark = isSel and "> " or "   "
      row.label:SetText(mark .. c.name .. "  |cff888888(" .. tzText(c) .. ")|r")
      row.label:SetTextColor(isSel and 0.3 or 1, 1, isSel and 0.4 or 1)
      row.kind, row.cityName, row.entryName, row._selected = "saved", nil, c.name, isSel
      if row.hl then if isSel then row.hl:Show() else row.hl:Hide() end end
      if row.delBtn then
        row.delBtn:SetScript("OnClick", function() Picker.deleteSaved(c.name) end)
        row.delBtn:Show()
      end
      row:Show()
    else
      local name = entry.city.name
      local isSel = (name == selCity)
      local mark = isSel and "> " or "   "
      row.label:SetText(mark .. name .. "  |cff888888" .. entry.city.country .. "|r")
      row.label:SetTextColor(isSel and 0.3 or 1, 1, isSel and 0.4 or 1)
      row.kind, row.cityName, row.entryName, row._selected = "city", name, nil, isSel
      if row.hl then if isSel then row.hl:Show() else row.hl:Hide() end end
      row:Show()
    end
  end
end

function Picker.scroll(delta)
  Picker.scrollOffset = math.max(0, (Picker.scrollOffset or 0) - delta)
  Picker.refreshList(Picker.searchBox and Picker.searchBox:GetText() or "")
end

-- Notification settings (wired to db.notify, read live by the Notifier).
function Picker.setBeforeMinutes(n)
  if not (Picker.db and Picker.db.notify) then return end
  Picker.db.notify.beforeMinutes = math.max(0, math.floor(tonumber(n) or 0))
end
function Picker.setAtTime(on)
  if Picker.db and Picker.db.notify then Picker.db.notify.atTime = on and true or false end
end
function Picker.setSound(on)
  if Picker.db and Picker.db.notify then Picker.db.notify.sound = on and true or false end
end
function Picker.updateNotifyControls()
  local n = Picker.db and Picker.db.notify
  if not n then return end
  if Picker.beforeBox then Picker.beforeBox:SetText(tostring(n.beforeMinutes or 0)) end
  if Picker.atCheck then Picker.atCheck:SetChecked(n.atTime and true or false) end
  if Picker.soundCheck then Picker.soundCheck:SetChecked(n.sound ~= false) end
end

-- Calculation method + Asr school (persisted in the shared DB, read live by
-- Cities.times via the Methods registry). All pure; the widgets just call these
-- and re-render. Changing either re-runs the engine and refreshes the window.
local function afterCalcChange()
  if Window.refresh then Window.refresh() end
  Picker.updateCalcControls()
end

function Picker.setMethod(key)
  if not Picker.db then return end
  Picker.db.method = Methods.resolveMethod(key)
  afterCalcChange()
end

-- Step through the ordered method list (dir = +1 next / -1 prev), wrapping.
function Picker.cycleMethod(dir)
  local list = Methods.list()
  local cur = Methods.resolveMethod(Picker.db and Picker.db.method)
  local idx = 1
  for i, m in ipairs(list) do if m.key == cur then idx = i; break end end
  idx = ((idx - 1 + (dir or 1)) % #list) + 1
  Picker.setMethod(list[idx].key)
end

function Picker.setMadhab(key)
  if not Picker.db then return end
  Picker.db.madhab = Methods.resolveMadhab(key)
  afterCalcChange()
end

function Picker.toggleMadhab()
  local cur = Methods.resolveMadhab(Picker.db and Picker.db.madhab)
  Picker.setMadhab(cur == "hanafi" and "shafi" or "hanafi")
end

function Picker.updateCalcControls()
  local db = Picker.db
  if Picker.methodLabelFS then
    Picker.methodLabelFS:SetText(Methods.methodLabel(db and db.method))
  end
  if Picker.asrBtn then
    Picker.asrBtn:SetText("Asr school: " .. Methods.madhabLabel(db and db.madhab))
  end
end

local function makeColLabel(f, text, x, y)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
end

function Picker.create()
  if Picker.frame then return Picker.frame end

  local f = CreateFrame("Frame", "PrayerTimesPicker", UIParent)
  f:SetSize(330, 660)
  f:SetPoint("CENTER", UIParent, "CENTER", 235, 0) -- offset from the main window
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.85)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -10)
  title:SetText("PrayerTimes - Select City")

  Picker.selectedLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  Picker.selectedLabel:SetPoint("TOP", 0, -32)

  local search = CreateFrame("EditBox", "PrayerTimesPickerSearch", f, "InputBoxTemplate")
  search:SetSize(290, 20); search:SetPoint("TOP", 0, -54); search:SetAutoFocus(false)
  search:SetScript("OnTextChanged", function(self)
    Picker.scrollOffset = 0
    Picker.refreshList(self:GetText())
  end)
  Picker.searchBox = search

  -- Scrollable row pool (with per-row delete button for saved rows).
  local list = CreateFrame("Frame", nil, f)
  list:SetPoint("TOPLEFT", 14, -80)
  list:SetSize(302, VISIBLE_ROWS * ROW_HEIGHT)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta) Picker.scroll(delta) end)
  Picker.rows = {}
  for i = 1, VISIBLE_ROWS do
    local row = CreateFrame("Button", nil, list)
    row:SetSize(302, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(); hl:SetColorTexture(0.15, 0.5, 0.25, 0.6); hl:Hide()
    row.hl = hl
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 2, 0); label:SetJustifyH("LEFT")
    row.label = label
    local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    del:SetSize(18, 14); del:SetPoint("RIGHT", -2, 0); del:SetText("x"); del:Hide()
    row.delBtn = del
    row:SetScript("OnClick", function(self)
      if self.kind == "saved" and self.entryName then Picker.selectSaved(self.entryName)
      elseif self.cityName then Picker.selectCity(self.cityName) end
    end)
    Picker.rows[i] = row
  end

  -- Manual / save section.
  local mY = -80 - VISIBLE_ROWS * ROW_HEIGHT - 14
  local mlabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  mlabel:SetPoint("TOPLEFT", 14, mY); mlabel:SetText("Add a location (your computer's timezone unless UTC set):")

  makeColLabel(f, "Name", 18, mY - 18)
  makeColLabel(f, "Lat", 124, mY - 18)
  makeColLabel(f, "Lon", 176, mY - 18)
  makeColLabel(f, "UTC+/-", 228, mY - 18)

  local boxY = mY - 32
  local nameBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  nameBox:SetSize(96, 20); nameBox:SetPoint("TOPLEFT", 16, boxY); nameBox:SetAutoFocus(false)
  local latBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  latBox:SetSize(46, 20); latBox:SetPoint("TOPLEFT", 122, boxY); latBox:SetAutoFocus(false)
  local lonBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  lonBox:SetSize(46, 20); lonBox:SetPoint("TOPLEFT", 174, boxY); lonBox:SetAutoFocus(false)
  local offBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  offBox:SetSize(40, 20); offBox:SetPoint("TOPLEFT", 226, boxY); offBox:SetAutoFocus(false)
  Picker.nameBox, Picker.latBox, Picker.lonBox, Picker.offsetBox = nameBox, latBox, lonBox, offBox

  local euCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  euCheck:SetSize(20, 20); euCheck:SetPoint("TOPLEFT", 272, boxY + 1)
  Picker.euCheck = euCheck
  local euText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  euText:SetPoint("LEFT", euCheck, "RIGHT", 0, 0); euText:SetText("EU DST")

  local clearErr = function() Picker.clearError() end
  nameBox:SetScript("OnTextChanged", clearErr)
  latBox:SetScript("OnTextChanged", clearErr)
  lonBox:SetScript("OnTextChanged", clearErr)
  offBox:SetScript("OnTextChanged", clearErr)

  -- Buttons: use once (not saved) and save as a named My City.
  local useBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  useBtn:SetSize(80, 22); useBtn:SetPoint("TOPLEFT", 16, boxY - 26); useBtn:SetText("Use once")
  useBtn:SetScript("OnClick", function()
    Picker.applyManual(latBox:GetText(), lonBox:GetText(), offBox:GetText())
  end)
  local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  saveBtn:SetSize(120, 22); saveBtn:SetPoint("TOPLEFT", 104, boxY - 26); saveBtn:SetText("Save as My City")
  saveBtn:SetScript("OnClick", function()
    Picker.saveManual(nameBox:GetText(), latBox:GetText(), lonBox:GetText(),
      offBox:GetText(), euCheck:GetChecked())
  end)

  -- Tab order across all input fields.
  local function tabTo(a, b) a:SetScript("OnTabPressed", function() b:SetFocus() end) end
  tabTo(search, nameBox); tabTo(nameBox, latBox); tabTo(latBox, lonBox)
  tabTo(lonBox, offBox); tabTo(offBox, search)

  Picker.errorLabel = f:CreateFontString(nil, "OVERLAY", "GameFontRed")
  Picker.errorLabel:SetPoint("TOPLEFT", 16, boxY - 52)

  -- Calculation method (prev/next selector) + Asr school toggle.
  local cY = boxY - 74
  local clabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  clabel:SetPoint("TOPLEFT", 14, cY); clabel:SetText("Calculation method:")

  local prevBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  prevBtn:SetSize(26, 22); prevBtn:SetPoint("TOPLEFT", 18, cY - 22); prevBtn:SetText("<")
  prevBtn:SetScript("OnClick", function() Picker.cycleMethod(-1) end)
  local nextBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  nextBtn:SetSize(26, 22); nextBtn:SetPoint("TOPRIGHT", -18, cY - 22); nextBtn:SetText(">")
  nextBtn:SetScript("OnClick", function() Picker.cycleMethod(1) end)
  local methodLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  methodLabel:SetPoint("TOP", 0, cY - 26); methodLabel:SetWidth(232); methodLabel:SetJustifyH("CENTER")
  Picker.methodLabelFS = methodLabel

  local asrBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  asrBtn:SetSize(294, 22); asrBtn:SetPoint("TOPLEFT", 18, cY - 48); asrBtn:SetText("Asr school: Standard (Shafi)")
  asrBtn:SetScript("OnClick", function() Picker.toggleMadhab() end)
  Picker.asrBtn = asrBtn

  -- Notification controls.
  local nY = cY - 74
  local nlabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nlabel:SetPoint("TOPLEFT", 14, nY); nlabel:SetText("Notifications:")

  local beforeBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  beforeBox:SetSize(40, 20); beforeBox:SetPoint("TOPLEFT", 20, nY - 22)
  beforeBox:SetAutoFocus(false); beforeBox:SetNumeric(true)
  beforeBox:SetScript("OnTextChanged", function(self) Picker.setBeforeMinutes(self:GetText()) end)
  Picker.beforeBox = beforeBox
  local bLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bLabel:SetPoint("LEFT", beforeBox, "RIGHT", 6, 0); bLabel:SetText("minutes before (0 = off)")

  local atCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  atCheck:SetPoint("TOPLEFT", 18, nY - 46)
  atCheck:SetScript("OnClick", function(self) Picker.setAtTime(self:GetChecked() and true or false) end)
  Picker.atCheck = atCheck
  local atText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  atText:SetPoint("LEFT", atCheck, "RIGHT", 2, 0); atText:SetText("Alert at prayer time")

  local soundCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  soundCheck:SetPoint("TOPLEFT", 18, nY - 70)
  soundCheck:SetScript("OnClick", function(self) Picker.setSound(self:GetChecked() and true or false) end)
  Picker.soundCheck = soundCheck
  local sText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sText:SetPoint("LEFT", soundCheck, "RIGHT", 2, 0); sText:SetText("Play sound")

  local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  close:SetSize(80, 24); close:SetPoint("BOTTOM", 0, 16); close:SetText("Close")
  close:SetScript("OnClick", function() Picker.close() end)

  Picker.frame = f
  Picker.scrollOffset = 0
  Picker.updateSelected()
  Picker.updateNotifyControls()
  Picker.updateCalcControls()
  Picker.refreshList("")
  return f
end

function Picker.open()
  Picker.create()
  Picker.clearError()
  Picker.updateSelected()
  Picker.updateNotifyControls()
  Picker.updateCalcControls()
  Picker.refreshList(Picker.searchBox and Picker.searchBox:GetText() or "")
  Picker.frame:Show()
end

function Picker.close()
  if Picker.frame then Picker.frame:Hide() end
end

function Picker.toggle()
  if Picker.frame and Picker.frame:IsShown() then Picker.close() else Picker.open() end
end

if PrayerTimesNS then PrayerTimesNS.modules.Picker = Picker end
return Picker
