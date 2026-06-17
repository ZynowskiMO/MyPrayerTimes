-- Picker.lua
-- City picker / welcome window (WoW-side widgets). The selection, grouping,
-- search and validation live in the pure modules (Selection, Cities); this
-- file renders them and wires clicks. Logic entry points (selectCity,
-- applyManual, refreshList, currentSelectionText, shouldAutoOpen) are exposed
-- so the runner can drive them under the mock without real widgets.

local Cities = require("Cities")
local Selection = require("Selection")
local Window = require("Window")

local VISIBLE_ROWS = 14
local ROW_HEIGHT = 16

local Picker = {}

function Picker.init(db)
  Picker.db = db
end

-- "Selected: ..." indicator text for the active selection.
function Picker.currentSelectionText(db)
  local sel = Selection.get(db)
  if not sel then return "Selected: Rotterdam (default)" end
  if sel.kind == "city" then
    local c = Cities.findByName(sel.name)
    return "Selected: " .. (c and (c.name .. ", " .. c.country) or sel.name)
  end
  local tz = sel.tz == "fixed"
    and string.format("UTC%+d", math.floor((sel.baseUtcOffset or 0) / 60))
    or "my timezone"
  return string.format("Selected: Manual %.4f, %.4f (%s)", sel.latitude, sel.longitude, tz)
end

function Picker.shouldAutoOpen(db)
  return Selection.get(db) == nil
end

function Picker.updateSelected()
  if Picker.selectedLabel then
    Picker.selectedLabel:SetText(Picker.currentSelectionText(Picker.db))
  end
end

-- Choose a bundled city: persist, update the main window, refresh the indicator.
function Picker.selectCity(name)
  Selection.setCity(Picker.db, name)
  if Window.refresh then Window.refresh() end
  Picker.updateSelected()
end

-- Apply manual coordinates. offsetText empty -> machine tz; a number -> fixed
-- UTC offset (hours) override. Returns ok, errorMessage.
function Picker.applyManual(latText, lonText, offsetText)
  local lat, lon = tonumber(latText), tonumber(lonText)
  local opts = {}
  if offsetText and offsetText ~= "" then
    local hours = tonumber(offsetText)
    if not hours then return false, "Offset must be a number (hours from UTC)" end
    opts.tz = "fixed"
    opts.baseUtcOffset = math.floor(hours * 60 + 0.5)
    opts.dstRule = "none"
  end
  local ok, err = Selection.setManual(Picker.db, lat, lon, opts)
  if ok then
    if Window.refresh then Window.refresh() end
    Picker.updateSelected()
  elseif Picker.errorLabel then
    Picker.errorLabel:SetText(err or "Invalid coordinates")
  end
  return ok, err
end

-- Render the current query into the visible row pool (with scroll offset).
function Picker.refreshList(query)
  Picker.displayRows = Cities.displayList(query)
  local maxOffset = math.max(0, #Picker.displayRows - VISIBLE_ROWS)
  Picker.scrollOffset = math.min(Picker.scrollOffset or 0, maxOffset)
  if not Picker.rows then return end
  for i = 1, VISIBLE_ROWS do
    local row = Picker.rows[i]
    local entry = Picker.displayRows[Picker.scrollOffset + i]
    if not entry then
      row:Hide()
    elseif entry.kind == "header" then
      row.label:SetText("|cffffd100" .. entry.label .. "|r")
      row.cityName = nil
      row:Show()
    else
      row.label:SetText("   " .. entry.city.name .. "  |cff888888" .. entry.city.country .. "|r")
      row.cityName = entry.city.name
      row:Show()
    end
  end
end

function Picker.scroll(delta)
  Picker.scrollOffset = math.max(0, (Picker.scrollOffset or 0) - delta)
  Picker.refreshList(Picker.searchBox and Picker.searchBox:GetText() or "")
end

function Picker.create()
  if Picker.frame then return Picker.frame end

  local f = CreateFrame("Frame", "PrayerTimesPicker", UIParent)
  f:SetSize(320, 420)
  f:SetPoint("CENTER")
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
  search:SetSize(280, 20)
  search:SetPoint("TOP", 0, -54)
  search:SetAutoFocus(false)
  search:SetScript("OnTextChanged", function(self)
    Picker.scrollOffset = 0
    Picker.refreshList(self:GetText())
  end)
  Picker.searchBox = search

  -- Scrollable row pool.
  local list = CreateFrame("Frame", nil, f)
  list:SetPoint("TOPLEFT", 14, -80)
  list:SetSize(292, VISIBLE_ROWS * ROW_HEIGHT)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta) Picker.scroll(delta) end)
  Picker.rows = {}
  for i = 1, VISIBLE_ROWS do
    local row = CreateFrame("Button", nil, list)
    row:SetSize(292, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 2, 0)
    label:SetJustifyH("LEFT")
    row.label = label
    row:SetScript("OnClick", function(self)
      if self.cityName then Picker.selectCity(self.cityName) end
    end)
    Picker.rows[i] = row
  end

  -- Manual entry.
  local manualY = -80 - VISIBLE_ROWS * ROW_HEIGHT - 14
  local mlabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  mlabel:SetPoint("TOPLEFT", 14, manualY)
  mlabel:SetText("Manual: lat / lon (uses your computer's timezone)")

  local latBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  latBox:SetSize(70, 20); latBox:SetPoint("TOPLEFT", 16, manualY - 18); latBox:SetAutoFocus(false)
  local lonBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  lonBox:SetSize(70, 20); lonBox:SetPoint("TOPLEFT", 96, manualY - 18); lonBox:SetAutoFocus(false)
  local offBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  offBox:SetSize(50, 20); offBox:SetPoint("TOPLEFT", 176, manualY - 18); offBox:SetAutoFocus(false)
  Picker.latBox, Picker.lonBox, Picker.offsetBox = latBox, lonBox, offBox

  local offHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  offHint:SetPoint("TOPLEFT", 176, manualY - 2); offHint:SetText("UTC+ (opt)")

  local setBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  setBtn:SetSize(60, 22); setBtn:SetPoint("TOPLEFT", 232, manualY - 17)
  setBtn:SetText("Set")
  setBtn:SetScript("OnClick", function()
    Picker.applyManual(latBox:GetText(), lonBox:GetText(), offBox:GetText())
  end)

  Picker.errorLabel = f:CreateFontString(nil, "OVERLAY", "GameFontRed")
  Picker.errorLabel:SetPoint("TOPLEFT", 16, manualY - 44)

  local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  close:SetSize(80, 24); close:SetPoint("BOTTOM", 0, 12); close:SetText("Close")
  close:SetScript("OnClick", function() Picker.close() end)

  Picker.frame = f
  Picker.scrollOffset = 0
  Picker.updateSelected()
  Picker.refreshList("")
  return f
end

function Picker.open()
  Picker.create()
  Picker.updateSelected()
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
