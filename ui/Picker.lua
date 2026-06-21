-- Picker.lua
-- City picker / welcome / settings window (WoW-side widgets). Selection,
-- grouping, search, validation and saved "My Cities" live in the pure modules
-- (Selection, Cities); this file renders them and wires clicks. Logic entry
-- points are exposed so the runner can drive them under the mock.

local Cities = require("Cities")
local Selection = require("Selection")
local Window = require("Window")
local Methods = require("Methods")
local Icons = require("Icons")

local VISIBLE_ROWS = 14
local ROW_HEIGHT = 16

-- Palette (cream / charcoal / gold). Declared up here so every function can use
-- it. Content stays dark on not-yet-restyled tabs so light text reads; each tab
-- is converted to cream + dark text as it is rebuilt (3S-2/3S-4/3S-5).
local COL = {
  header  = { 0.13, 0.11, 0.09, 1 },
  bg      = { 0.07, 0.06, 0.05, 0.97 },
  sidebar = { 0.91, 0.88, 0.81, 1 },
  navHl   = { 0.97, 0.95, 0.90, 1 },
  gold    = { 0.72, 0.58, 0.29, 1 },
  navText = { 0.16, 0.14, 0.11 },
  navSub  = { 0.45, 0.42, 0.36 },
  content = { 0.96, 0.94, 0.88, 1 }, -- cream tab background
  card    = { 0.16, 0.13, 0.10, 1 }, -- dark current-location card
  text    = { 0.16, 0.14, 0.11 },    -- dark body text on cream
  muted   = { 0.45, 0.42, 0.36 },
  rowHl   = { 0.85, 0.78, 0.55, 0.55 }, -- gold row highlight
  cardSel = { 0.91, 0.85, 0.67, 1 },    -- selected option card (light gold)
  cardOff = { 1.0, 0.99, 0.96, 1 },     -- unselected option card (near white)
}

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
  if Picker.headerLoc then
    Picker.headerLoc:SetText(Picker.headerLocationText(Picker.db))
  end
  -- Current-location card (city big, country/source on the right).
  local sel = Selection.get(Picker.db)
  local city, country = "Rotterdam", ""
  if sel then
    if sel.kind == "city" then
      local c = Cities.findByName(sel.name)
      if c then city, country = c.name, c.country else city = sel.name end
    elseif sel.kind == "saved" then
      city, country = sel.name, "saved"
    else
      city, country = "Manual location", ""
    end
  end
  if Picker.cardCity then Picker.cardCity:SetText(city) end
  if Picker.cardCountry then Picker.cardCountry:SetText(country) end
end

-- Selection actions (persist + update main window + indicator + list).
local function afterSelectionChange()
  if Window.refresh then Window.refresh() end
  Picker.updateSelected()
  if Picker.refreshLocation then Picker.refreshLocation() end
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

-- ===== Master-detail city picker (3S-2) ===================================
-- Pure row builders (no widgets): the master column lists My Cities + countries
-- (with counts); the detail column lists the selected country's cities, or flat
-- search matches when the search box has text. The old buildRows (combined list)
-- is kept above for callers/tests that still use it.

local function citiesInCountry(country)
  local out = {}
  for _, c in ipairs(Cities.all()) do
    if c.country == country then out[#out + 1] = c end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function Picker.masterRows(db)
  local rows = {}
  local saved = Selection.getSavedCities(db)
  if #saved > 0 then
    rows[#rows + 1] = { kind = "myheader", label = "MY CITIES" }
    for _, c in ipairs(saved) do rows[#rows + 1] = { kind = "saved", city = c } end
  end
  rows[#rows + 1] = { kind = "cheader", label = "COUNTRIES" }
  for _, g in ipairs(Cities.byCountry()) do
    rows[#rows + 1] = { kind = "country", country = g.country, count = #g.cities }
  end
  return rows
end

-- Returns (rows, searching). Searching = the query drove a flat cross-city list.
function Picker.detailRows(db, query, country)
  local rows = {}
  if query and query ~= "" then
    for _, c in ipairs(Cities.search(query)) do rows[#rows + 1] = { kind = "city", city = c } end
    return rows, true
  end
  if country then
    for _, c in ipairs(citiesInCountry(country)) do rows[#rows + 1] = { kind = "city", city = c } end
  end
  return rows, false
end

-- Country to pre-select: the current city's country, else the first country.
function Picker.defaultCountry(db)
  local sel = Selection.get(db)
  if sel and sel.kind == "city" then
    local c = Cities.findByName(sel.name)
    if c then return c.country end
  end
  local g = Cities.byCountry()[1]
  return g and g.country
end

-- Recompute + render both columns from the current query/selected country.
function Picker.refreshLocation(query)
  query = query or (Picker.searchBox and Picker.searchBox:GetText()) or ""
  if not Picker.selectedCountry then Picker.selectedCountry = Picker.defaultCountry(Picker.db) end
  Picker.masterData = Picker.masterRows(Picker.db)
  local rows, searching = Picker.detailRows(Picker.db, query, Picker.selectedCountry)
  Picker.detailData, Picker.detailSearching = rows, searching
  Picker.refreshMaster()
  Picker.refreshDetail()
  Picker.updateSelected()
end

function Picker.selectCountry(country)
  Picker.selectedCountry = country
  Picker.dScroll = 0
  if Picker.searchBox then Picker.searchBox:SetText("") end -- fires refreshLocation
  Picker.refreshLocation("")
end

function Picker.refreshMaster()
  if not Picker.masterPool then return end
  local data, vis = Picker.masterData or {}, #Picker.masterPool
  Picker.mScroll = math.min(Picker.mScroll or 0, math.max(0, #data - vis))
  local sel = Selection.get(Picker.db)
  local selSaved = sel and sel.kind == "saved" and sel.name or nil
  for i = 1, vis do
    local row = Picker.masterPool[i]
    local e = data[Picker.mScroll + i]
    row.delBtn:Hide(); row.count:SetText(""); row.hl:Hide()
    row.kind, row.country, row.name, row._selected = nil, nil, nil, false
    if not e then
      row:Hide()
    elseif e.kind == "myheader" or e.kind == "cheader" then
      row.label:SetText("|cff8a8275" .. e.label .. "|r"); row.kind = "header"; row:Show()
    elseif e.kind == "saved" then
      local isSel = (e.city.name == selSaved)
      row.label:SetText(e.city.name); row.kind, row.name, row._selected = "saved", e.city.name, isSel
      if isSel then row.hl:Show() end
      row.delBtn:SetScript("OnClick", function() Picker.deleteSaved(e.city.name) end); row.delBtn:Show()
      row:Show()
    elseif e.kind == "country" then
      local isSel = (e.country == Picker.selectedCountry)
      row.label:SetText(e.country); row.count:SetText("|cff8a8275" .. e.count .. "|r")
      row.kind, row.country, row._selected = "country", e.country, isSel
      if isSel then row.hl:Show() end
      row:Show()
    end
  end
  if Picker.masterSB then Picker.masterSB:update() end
end

function Picker.refreshDetail()
  if not Picker.detailPool then return end
  local data, vis = Picker.detailData or {}, #Picker.detailPool
  Picker.dScroll = math.min(Picker.dScroll or 0, math.max(0, #data - vis))
  local sel = Selection.get(Picker.db)
  local selCity = sel and sel.kind == "city" and sel.name or nil
  if Picker.detailHeader then
    Picker.detailHeader:SetText("|cffb89254"
      .. (Picker.detailSearching and "SEARCH RESULTS" or (Picker.selectedCountry or "")) .. "|r")
  end
  for i = 1, vis do
    local row = Picker.detailPool[i]
    local e = data[Picker.dScroll + i]
    row.mark:Hide(); row.hl:Hide()
    row.name, row._selected = nil, false
    if not e then
      row:Hide()
    else
      local isSel = (e.city.name == selCity)
      row.label:SetText(e.city.name); row.name, row._selected = e.city.name, isSel
      if isSel then row.hl:Show(); row.mark:Show() end
      row:Show()
    end
  end
  if Picker.detailSB then Picker.detailSB:update() end
end

function Picker.scrollMaster(delta)
  Picker.mScroll = math.max(0, (Picker.mScroll or 0) - delta)
  Picker.refreshMaster()
end

function Picker.scrollDetail(delta)
  Picker.dScroll = math.max(0, (Picker.dScroll or 0) - delta)
  Picker.refreshDetail()
end

-- The "Add custom location" form replaces the master-detail browse view while
-- open (browse hidden so nothing shows through behind the cream form).
function Picker.openAddPanel()
  Picker.clearError()
  if Picker.browse then Picker.browse:Hide() end
  if Picker.addPanel then Picker.addPanel:Show() end
end

function Picker.closeAddPanel()
  if Picker.addPanel then Picker.addPanel:Hide() end
  if Picker.browse then Picker.browse:Show() end
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
  if Picker.beforeValue then
    local m = n.beforeMinutes or 0
    Picker.beforeValue:SetText(m == 0 and "Off" or (m .. " min"))
  end
  if Picker.atToggle then Picker.atToggle:update() end
  if Picker.soundToggle then Picker.soundToggle:update() end
end

-- Step the before-minutes value (stepper buttons); clamps at 0 = Off.
function Picker.stepBeforeMinutes(delta)
  local n = Picker.db and Picker.db.notify
  if not n then return end
  Picker.setBeforeMinutes((n.beforeMinutes or 0) + delta)
  Picker.updateNotifyControls()
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
  if Picker.methodDropdown then Picker.methodDropdown:updateButton() end
  if Picker.asrCards then
    local cur = Methods.resolveMadhab(db and db.madhab)
    for _, c in ipairs(Picker.asrCards) do
      local on = (c.key == cur)
      c._selected = on
      if c.bg then c.bg:SetColorTexture(unpack(on and COL.cardSel or COL.cardOff)) end
      if c.border then if on then c.border:Show() else c.border:Hide() end end
      if c.title then c.title:SetTextColor(unpack(on and COL.gold or COL.text)) end
    end
  end
end

local function makeColLabel(f, text, x, y)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
end

-- Reusable row-pool dropdown (no Blizzard dropdown widget -- stable on Retail +
-- Classic). A button shows the current value; clicking opens an anchored,
-- scrollable list built from the same pooled-row + highlight pattern as the
-- city list, with a full-screen click-catcher to close on click-away. All
-- state lives on the returned table and the option list / current value are
-- supplied by callbacks, so the runner can drive open/close/select/scroll under
-- the mock. opts = { width, rows, getOptions()->{{key,label}..},
-- getCurrent()->key, onSelect(key) }.
local DD_ROW_H = 16
local function makeDropdown(parent, opts)
  local dd = { isOpen = false, scrollOffset = 0 }
  local vis = opts.rows or 8
  local width = opts.width or 240

  -- Flat cream button: border + cream fill + left label + a v arrow. (No
  -- Blizzard button template, so it matches the cream palette.)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(width, 26)
  local bborder = button:CreateTexture(nil, "BACKGROUND"); bborder:SetAllPoints(); bborder:SetColorTexture(0.55, 0.50, 0.42, 1)
  local bfill = button:CreateTexture(nil, "BORDER")
  bfill:SetPoint("TOPLEFT", 1, -1); bfill:SetPoint("BOTTOMRIGHT", -1, 1); bfill:SetColorTexture(unpack(COL.cardOff))
  local blabel = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  blabel:SetPoint("LEFT", 10, 0); blabel:SetPoint("RIGHT", -24, 0); blabel:SetJustifyH("LEFT"); blabel:SetTextColor(unpack(COL.text))
  dd.labelFS = blabel
  -- Down-arrow texture (a Unicode glyph renders as a "tofu" box in WoW's font).
  local barrow = button:CreateTexture(nil, "OVERLAY")
  barrow:SetSize(13, 13); barrow:SetPoint("RIGHT", -8, 0)
  Icons.setUI(barrow, "chevron", 0.35, 0.32, 0.27)
  button:SetScript("OnEnter", function() bfill:SetColorTexture(unpack(COL.cardSel)) end)
  button:SetScript("OnLeave", function() bfill:SetColorTexture(unpack(COL.cardOff)) end)
  dd.button = button

  -- Full-screen catcher: clicking outside the open list closes it. Parented to
  -- the button so it disappears when the button (tab/window) is hidden.
  local catcher = CreateFrame("Button", nil, button)
  catcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT")
  catcher:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT")
  catcher:SetFrameStrata("FULLSCREEN")
  catcher:Hide()
  catcher:SetScript("OnClick", function() dd:close() end)
  dd.catcher = catcher

  local popup = CreateFrame("Frame", nil, button)
  popup:SetSize(width, vis * DD_ROW_H + 8)
  popup:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
  popup:SetFrameStrata("FULLSCREEN_DIALOG")
  popup:EnableMouseWheel(true)
  popup:SetScript("OnMouseWheel", function(_, delta) dd:scroll(delta) end)
  local pborder = popup:CreateTexture(nil, "BACKGROUND")
  pborder:SetAllPoints(); pborder:SetColorTexture(0.55, 0.50, 0.42, 1)
  local pbg = popup:CreateTexture(nil, "BORDER")
  pbg:SetPoint("TOPLEFT", 1, -1); pbg:SetPoint("BOTTOMRIGHT", -1, 1); pbg:SetColorTexture(unpack(COL.cardOff))
  popup:Hide()
  dd.popup = popup

  dd.rows = {}
  for i = 1, vis do
    local row = CreateFrame("Button", nil, popup)
    row:SetSize(width - 8, DD_ROW_H)
    row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * DD_ROW_H)
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(); hl:SetColorTexture(unpack(COL.rowHl)); hl:Hide()
    row.hl = hl
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 6, 0); label:SetJustifyH("LEFT"); label:SetTextColor(unpack(COL.text))
    row.label = label
    row:SetScript("OnClick", function(self) if self.key then dd:select(self.key) end end)
    dd.rows[i] = row
  end

  function dd:currentLabel()
    local cur = opts.getCurrent()
    for _, o in ipairs(opts.getOptions()) do
      if o.key == cur then return o.label end
    end
    return "Select..."
  end

  function dd:updateButton() dd.labelFS:SetText(dd:currentLabel()) end

  function dd:renderRows()
    local options = opts.getOptions()
    local cur = opts.getCurrent()
    local maxOffset = math.max(0, #options - vis)
    dd.scrollOffset = math.min(dd.scrollOffset, maxOffset)
    for i = 1, vis do
      local row = dd.rows[i]
      local o = options[dd.scrollOffset + i]
      if not o then
        row.key, row._selected = nil, false
        row.hl:Hide(); row:Hide()
      else
        local isSel = (o.key == cur)
        row.key, row._selected = o.key, isSel
        row.label:SetText((isSel and "> " or "   ") .. o.label)
        if isSel then row.hl:Show() else row.hl:Hide() end
        row:Show()
      end
    end
  end

  function dd:open()
    dd.isOpen = true
    dd.scrollOffset = 0
    dd:renderRows()
    dd.catcher:Show(); dd.popup:Show()
  end

  function dd:close()
    dd.isOpen = false
    dd.popup:Hide(); dd.catcher:Hide()
  end

  function dd:toggle() if dd.isOpen then dd:close() else dd:open() end end

  function dd:scroll(delta)
    dd.scrollOffset = math.max(0, dd.scrollOffset - delta)
    dd:renderRows()
  end

  function dd:select(key)
    dd:close()
    if opts.onSelect then opts.onSelect(key) end
    dd:updateButton()
  end

  button:SetScript("OnClick", function() dd:toggle() end)
  dd:updateButton()
  return dd
end

-- Reusable faux-pill toggle (no Blizzard art): a track that turns gold when on
-- with a thumb that slides right. getter()/onToggle(bool) wire it to the DB;
-- state lives on the returned table so the runner can drive it under the mock.
local function makeToggle(parent, getter, onToggle)
  local t = {}
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(46, 22)
  local track = btn:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints()
  local thumb = btn:CreateTexture(nil, "ARTWORK"); thumb:SetSize(18, 18)
  t.btn, t.track, t.thumb = btn, track, thumb
  function t:update()
    local on = getter() and true or false
    t.on = on
    if on then track:SetColorTexture(unpack(COL.gold)) else track:SetColorTexture(0.62, 0.60, 0.54, 1) end
    thumb:ClearAllPoints(); thumb:SetPoint(on and "RIGHT" or "LEFT", on and -2 or 2, 0)
    thumb:SetColorTexture(0.98, 0.97, 0.94)
  end
  btn:SetScript("OnClick", function() onToggle(not (getter() and true or false)); t:update() end)
  t:update()
  return t
end

-- Reusable proportional scrollbar for a row-pool list. A faint track with a
-- gold thumb sized by visible/total and positioned by the scroll offset; the
-- thumb is draggable (cursor-delta mapping) and hides itself when everything
-- fits. getCount/getOffset/setOffset wire it to the list's state.
local function makeScrollbar(listFrame, vis, height, getCount, getOffset, setOffset)
  local sb = {}
  local track = listFrame:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", 10, 0)
  track:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", 10, 0)
  track:SetWidth(6); track:SetColorTexture(0, 0, 0, 0.10)
  local thumb = CreateFrame("Button", nil, listFrame)
  thumb:SetWidth(6)
  local tt = thumb:CreateTexture(nil, "ARTWORK"); tt:SetAllPoints(); tt:SetColorTexture(unpack(COL.gold))
  sb.track, sb.thumb = track, thumb

  function sb:update()
    local count = getCount() or 0
    local maxOff = math.max(0, count - vis)
    if maxOff <= 0 then track:Hide(); thumb:Hide(); return end
    track:Show(); thumb:Show()
    local th = math.max(16, height * vis / count)
    local off = math.min(getOffset() or 0, maxOff)
    local y = -(off / maxOff) * (height - th)
    thumb:SetSize(6, th)
    thumb:ClearAllPoints(); thumb:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", 10, y)
    sb.thumbH = th
  end

  thumb:RegisterForDrag("LeftButton")
  thumb:SetScript("OnMouseDown", function()
    local _, sy = GetCursorPosition()
    sb._startY, sb._startOff = sy, getOffset() or 0
    thumb:SetScript("OnUpdate", function()
      -- Self-terminate if the button was released anywhere off the thumb (then
      -- OnMouseUp never fired) -- otherwise the drag leaks and the list would
      -- keep scrolling as the mouse merely moves over it.
      if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        thumb:SetScript("OnUpdate", nil); return
      end
      local _, cy = GetCursorPosition()
      local scale = UIParent:GetEffectiveScale() or 1
      local dy = (sb._startY - cy) / scale
      local count = getCount() or 0
      local maxOff = math.max(0, count - vis)
      local th = math.max(16, height * vis / count)
      local range = math.max(1, height - th)
      local off = math.floor(sb._startOff + (dy / range) * maxOff + 0.5)
      setOffset(math.max(0, math.min(maxOff, off)))
    end)
  end)
  thumb:SetScript("OnMouseUp", function() thumb:SetScript("OnUpdate", nil) end)

  sb:update()
  return sb
end

-- Flat button matching the cream/gold palette (replaces the red Blizzard
-- UIPanelButtonTemplate). primary=true -> gold fill; otherwise cream. Returns a
-- plain Button; the caller sets size/point/OnClick.
-- iconName (optional): show a centered Lucide icon instead of text (e.g. a
-- minus/plus stepper or a trash button), tinted dark to match the button text.
local function makeFlatButton(parent, text, primary, iconName)
  local b = CreateFrame("Button", nil, parent)
  local border = b:CreateTexture(nil, "BACKGROUND"); border:SetAllPoints(); border:SetColorTexture(0.55, 0.50, 0.42, 1)
  -- Fill on the BORDER layer (one above BACKGROUND) so it always draws over the
  -- outline regardless of texture creation order.
  local fill = b:CreateTexture(nil, "BORDER")
  fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1)
  -- Gold buttons (primary = deeper gold, secondary = lighter gold).
  local base = primary and { 0.80, 0.63, 0.28, 1 } or { 0.88, 0.76, 0.46, 1 }
  local hov = primary and { 0.88, 0.71, 0.35, 1 } or { 0.93, 0.83, 0.55, 1 }
  fill:SetColorTexture(unpack(base))
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("CENTER"); fs:SetText(text)
  fs:SetTextColor(0.16, 0.12, 0.06)
  if iconName then
    fs:SetText("")
    local ic = b:CreateTexture(nil, "OVERLAY"); ic:SetPoint("CENTER"); ic:SetSize(13, 13)
    Icons.setUI(ic, iconName, 0.16, 0.12, 0.06)
    b.icon = ic
  end
  b:SetScript("OnEnter", function() fill:SetColorTexture(unpack(hov)) end)
  b:SetScript("OnLeave", function() fill:SetColorTexture(unpack(base)) end)
  b.fill, b.label = fill, fs
  return b
end

-- Flat cream input box (replaces the gray Blizzard InputBoxTemplate skin).
local function makeFlatEditBox(parent)
  local eb = CreateFrame("EditBox", nil, parent)
  eb:SetAutoFocus(false)
  eb:SetFontObject("GameFontHighlight"); eb:SetTextColor(unpack(COL.text)); eb:SetTextInsets(8, 8, 0, 0)
  eb:SetScript("OnEscapePressed", eb.ClearFocus)
  local bd = eb:CreateTexture(nil, "BACKGROUND"); bd:SetAllPoints(); bd:SetColorTexture(0.55, 0.50, 0.42, 1)
  local fl = eb:CreateTexture(nil, "BORDER")
  fl:SetPoint("TOPLEFT", 1, -1); fl:SetPoint("BOTTOMRIGHT", -1, 1); fl:SetColorTexture(unpack(COL.cardOff))
  return eb
end

-- Flat cream checkbox (replaces UICheckButtonTemplate). A gold inner square
-- shows when checked; exposes GetChecked/SetChecked like a CheckButton.
local function makeFlatCheck(parent)
  local c = CreateFrame("Button", nil, parent)
  c:SetSize(18, 18)
  local bd = c:CreateTexture(nil, "BACKGROUND"); bd:SetAllPoints(); bd:SetColorTexture(0.55, 0.50, 0.42, 1)
  local fl = c:CreateTexture(nil, "BORDER")
  fl:SetPoint("TOPLEFT", 1, -1); fl:SetPoint("BOTTOMRIGHT", -1, 1); fl:SetColorTexture(unpack(COL.cardOff))
  local mark = c:CreateTexture(nil, "OVERLAY")
  mark:SetPoint("CENTER"); mark:SetSize(16, 16); Icons.setUI(mark, "check", unpack(COL.gold)); mark:Hide()
  c._checked = false
  function c:GetChecked() return self._checked end
  function c:SetChecked(v) self._checked = v and true or false; if self._checked then mark:Show() else mark:Hide() end end
  c:SetScript("OnClick", function(self) self:SetChecked(not self._checked) end)
  return c
end

-- Settings redesign (ADR-0005, Approach B): a dark header, a persistent left
-- sidebar (title + subtitle per section, active item marked with a gold bar +
-- lighter background), and a content area on the right hosting one panel at a
-- time. 3S-1 builds this chrome; each section's content is restyled in 3S-2..6.
-- Skin is the approximation pass: solid-colour textures only, no bundled art.
local TABS = {
  { key = "location",      label = "Location",      sub = "Pick where you are" },
  { key = "calculation",   label = "Calculation",   sub = "Method & Asr" },
  { key = "notifications", label = "Notifications", sub = "Alerts & sound" },
}

-- Switch sections: show one panel, hide the others, and mark the active sidebar
-- item (gold bar + lighter background). Runner-drivable via IsShown().
function Picker.showTab(name)
  if not Picker.panels then return end
  if not Picker.panels[name] then name = "location" end
  Picker.activeTab = name
  for key, panel in pairs(Picker.panels) do
    if key == name then panel:Show() else panel:Hide() end
  end
  if Picker.navItems then
    for key, n in pairs(Picker.navItems) do
      if key == name then n.hl:Show(); n.bar:Show() else n.hl:Hide(); n.bar:Hide() end
    end
  end
end

-- Compact "City . Country" for the header. Reuses the selection model.
function Picker.headerLocationText(db)
  local sel = Selection.get(db)
  if not sel then return "Rotterdam" end
  if sel.kind == "city" then
    local c = Cities.findByName(sel.name)
    return c and (c.name .. " \194\183 " .. c.country) or sel.name
  elseif sel.kind == "saved" then
    return sel.name
  end
  return "Manual location"
end

function Picker.create()
  if Picker.frame then return Picker.frame end

  local f = CreateFrame("Frame", "PrayerTimesPicker", UIParent)
  f:SetSize(660, 560)
  f:SetPoint("CENTER", UIParent, "CENTER", 150, 0)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(unpack(COL.bg))

  -- Dark header bar: wordmark + "SETTINGS", current location (right), close X.
  local header = f:CreateTexture(nil, "BACKGROUND")
  header:SetPoint("TOPLEFT", 0, 0); header:SetPoint("TOPRIGHT", 0, 0); header:SetHeight(46)
  header:SetColorTexture(unpack(COL.header))

  local wm = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  wm:SetPoint("TOPLEFT", 16, -14); wm:SetText("PrayerTimes"); wm:SetTextColor(unpack(COL.gold))
  local wmSub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  wmSub:SetPoint("LEFT", wm, "RIGHT", 6, -1); wmSub:SetText("SETTINGS")

  Picker.headerLoc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  Picker.headerLoc:SetPoint("TOPRIGHT", -44, -16); Picker.headerLoc:SetTextColor(unpack(COL.gold))

  local x = CreateFrame("Button", nil, f)
  x:SetSize(26, 26); x:SetPoint("TOPRIGHT", -10, -10)
  local xi = x:CreateTexture(nil, "OVERLAY"); xi:SetPoint("CENTER"); xi:SetSize(16, 16)
  Icons.setUI(xi, "close", unpack(COL.gold))
  x:SetScript("OnEnter", function() xi:SetVertexColor(1, 0.9, 0.6) end)
  x:SetScript("OnLeave", function() xi:SetVertexColor(unpack(COL.gold)) end)
  x:SetScript("OnClick", function() Picker.close() end)

  -- Left sidebar.
  local side = f:CreateTexture(nil, "BACKGROUND")
  side:SetPoint("TOPLEFT", 0, -46); side:SetPoint("BOTTOMLEFT", 0, 0); side:SetWidth(188)
  side:SetColorTexture(unpack(COL.sidebar))

  -- Sidebar nav items + content panels.
  Picker.navItems, Picker.tabButtons, Picker.panels = {}, {}, {}
  for i, t in ipairs(TABS) do
    local btn = CreateFrame("Button", nil, f)
    btn:SetSize(188, 58)
    btn:SetPoint("TOPLEFT", 0, -46 - (i - 1) * 58)
    local hl = btn:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(); hl:SetColorTexture(unpack(COL.navHl)); hl:Hide()
    local bar = btn:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 0, 0); bar:SetPoint("BOTTOMLEFT", 0, 0); bar:SetWidth(4)
    bar:SetColorTexture(unpack(COL.gold)); bar:Hide()
    local title = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 16, -12); title:SetText(t.label); title:SetTextColor(unpack(COL.navText))
    local sub = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", 16, -30); sub:SetText(t.sub); sub:SetTextColor(unpack(COL.navSub))
    btn:SetScript("OnClick", function() Picker.showTab(t.key) end)
    Picker.navItems[t.key] = { btn = btn, hl = hl, bar = bar }
    Picker.tabButtons[t.key] = btn -- back-compat alias

    local panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT", f, "TOPLEFT", 189, -46)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    Picker.panels[t.key] = panel
  end
  local locP, calcP, notifP = Picker.panels.location, Picker.panels.calculation, Picker.panels.notifications

  -- Thin divider between the cream sidebar and the cream content.
  local vdiv = f:CreateTexture(nil, "ARTWORK")
  vdiv:SetPoint("TOPLEFT", 188, -46); vdiv:SetPoint("BOTTOMLEFT", 188, 0)
  vdiv:SetWidth(1); vdiv:SetColorTexture(0, 0, 0, 0.18)

  -- ===== Location tab (master-detail: country -> city, search, card) =====
  local MVIS, DVIS, RH = 20, 18, 18
  local locBg = locP:CreateTexture(nil, "BACKGROUND")
  locBg:SetAllPoints(); locBg:SetColorTexture(unpack(COL.content))

  -- Legacy indicator kept (hidden) so updateSelected + older tests still work.
  Picker.selectedLabel = locP:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  Picker.selectedLabel:SetPoint("TOPLEFT", 0, 0); Picker.selectedLabel:Hide()

  -- Current-location card.
  local card = locP:CreateTexture(nil, "BACKGROUND")
  card:SetPoint("TOPLEFT", 6, -4); card:SetSize(442, 46); card:SetColorTexture(unpack(COL.card))
  local cl = locP:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  cl:SetPoint("TOPLEFT", 20, -10); cl:SetText("CURRENT LOCATION"); cl:SetTextColor(unpack(COL.gold))
  Picker.cardCity = locP:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  Picker.cardCity:SetPoint("TOPLEFT", 20, -24); Picker.cardCity:SetTextColor(0.96, 0.94, 0.88)
  Picker.cardCountry = locP:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  Picker.cardCountry:SetPoint("TOPRIGHT", -16, -26); Picker.cardCountry:SetTextColor(0.70, 0.67, 0.60)

  -- Search across all cities -- a flat cream field (no Blizzard InputBox skin)
  -- with a placeholder shown while empty.
  local search = CreateFrame("EditBox", "PrayerTimesPickerSearch", locP)
  search:SetSize(434, 24); search:SetPoint("TOPLEFT", 12, -58); search:SetAutoFocus(false)
  search:SetFontObject("GameFontHighlight"); search:SetTextColor(unpack(COL.text))
  search:SetTextInsets(10, 10, 0, 0)
  search:SetScript("OnEscapePressed", search.ClearFocus)
  local sborder = search:CreateTexture(nil, "BACKGROUND"); sborder:SetAllPoints(); sborder:SetColorTexture(0.55, 0.50, 0.42, 1)
  local sfill = search:CreateTexture(nil, "BORDER")
  sfill:SetPoint("TOPLEFT", 1, -1); sfill:SetPoint("BOTTOMRIGHT", -1, 1); sfill:SetColorTexture(unpack(COL.cardOff))
  local ph = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ph:SetPoint("LEFT", 10, 0); ph:SetText("Search all cities..."); ph:SetTextColor(0.55, 0.52, 0.46)
  search:SetScript("OnTextChanged", function(self)
    ph:SetShown(self:GetText() == "")
    Picker.dScroll = 0; Picker.refreshLocation(self:GetText())
  end)
  Picker.searchBox = search

  -- Browse container (master + detail). Hidden as a unit when the add-custom
  -- form is open, so nothing shows through behind the form.
  local browse = CreateFrame("Frame", nil, locP)
  browse:SetAllPoints(locP)
  Picker.browse = browse

  -- Master column: My Cities + countries (with counts).
  local mlist = CreateFrame("Frame", nil, browse)
  mlist:SetPoint("TOPLEFT", 8, -90); mlist:SetSize(196, MVIS * RH)
  mlist:EnableMouseWheel(true); mlist:SetScript("OnMouseWheel", function(_, d) Picker.scrollMaster(d) end)
  Picker.masterPool = {}
  for i = 1, MVIS do
    local row = CreateFrame("Button", nil, mlist)
    row:SetSize(196, RH); row:SetPoint("TOPLEFT", 0, -(i - 1) * RH)
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(); hl:SetColorTexture(unpack(COL.rowHl)); hl:Hide(); row.hl = hl
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 8, 0); label:SetJustifyH("LEFT"); label:SetTextColor(unpack(COL.text)); row.label = label
    local count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("RIGHT", -8, 0); row.count = count
    local del = makeFlatButton(row, "", false, "trash")
    del:SetSize(18, 16); del:SetPoint("RIGHT", -4, 0); del:Hide(); row.delBtn = del
    row:SetScript("OnClick", function(self)
      if self.kind == "country" then Picker.selectCountry(self.country)
      elseif self.kind == "saved" then Picker.selectSaved(self.name) end
    end)
    Picker.masterPool[i] = row
  end
  Picker.masterSB = makeScrollbar(mlist, MVIS, MVIS * RH,
    function() return #(Picker.masterData or {}) end,
    function() return Picker.mScroll or 0 end,
    function(o) Picker.mScroll = o; Picker.refreshMaster() end)

  -- Divider.
  local divider = browse:CreateTexture(nil, "ARTWORK")
  divider:SetPoint("TOPLEFT", 208, -88); divider:SetPoint("BOTTOMLEFT", 208, 40)
  divider:SetWidth(1); divider:SetColorTexture(0, 0, 0, 0.15)

  -- Detail column: cities of the selected country (or search results).
  Picker.detailHeader = browse:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  Picker.detailHeader:SetPoint("TOPLEFT", 216, -92)
  local dlist = CreateFrame("Frame", nil, browse)
  dlist:SetPoint("TOPLEFT", 214, -110); dlist:SetSize(232, DVIS * RH)
  dlist:EnableMouseWheel(true); dlist:SetScript("OnMouseWheel", function(_, d) Picker.scrollDetail(d) end)
  Picker.detailPool = {}
  for i = 1, DVIS do
    local row = CreateFrame("Button", nil, dlist)
    row:SetSize(232, RH); row:SetPoint("TOPLEFT", 0, -(i - 1) * RH)
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(); hl:SetColorTexture(unpack(COL.rowHl)); hl:Hide(); row.hl = hl
    local mark = row:CreateTexture(nil, "OVERLAY")
    mark:SetSize(16, 16); mark:SetPoint("RIGHT", -6, 0)
    Icons.setUI(mark, "check", unpack(COL.gold)); mark:Hide(); row.mark = mark
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 10, 0); label:SetJustifyH("LEFT"); label:SetTextColor(unpack(COL.text)); row.label = label
    row:SetScript("OnClick", function(self) if self.name then Picker.selectCity(self.name) end end)
    Picker.detailPool[i] = row
  end
  Picker.detailSB = makeScrollbar(dlist, DVIS, DVIS * RH,
    function() return #(Picker.detailData or {}) end,
    function() return Picker.dScroll or 0 end,
    function(o) Picker.dScroll = o; Picker.refreshDetail() end)

  local addBtn = makeFlatButton(browse, "+ Add custom location", true)
  addBtn:SetSize(232, 24); addBtn:SetPoint("BOTTOMLEFT", 214, 10)
  addBtn:SetScript("OnClick", function() Picker.openAddPanel() end)

  -- Add-custom-location form (overlay; logic unchanged from 3R-3). Opaque cream
  -- background, raised above the browse container so nothing shows through.
  local addPanel = CreateFrame("Frame", nil, locP)
  addPanel:SetPoint("TOPLEFT", 6, -86); addPanel:SetPoint("BOTTOMRIGHT", -6, 8)
  addPanel:SetFrameLevel(locP:GetFrameLevel() + 10)
  local apbg = addPanel:CreateTexture(nil, "BACKGROUND"); apbg:SetAllPoints(); apbg:SetColorTexture(unpack(COL.content))
  addPanel:Hide(); Picker.addPanel = addPanel

  local at = addPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  at:SetPoint("TOPLEFT", 10, -8); at:SetText("ADD CUSTOM LOCATION"); at:SetTextColor(unpack(COL.gold))

  -- Coordinates row, spread across the width; EU DST to the right.
  makeColLabel(addPanel, "Lat", 12, -32)
  makeColLabel(addPanel, "Lon", 98, -32)
  makeColLabel(addPanel, "UTC+/-", 184, -32)
  local boxY = -46
  local latBox = makeFlatEditBox(addPanel)
  latBox:SetSize(76, 22); latBox:SetPoint("TOPLEFT", 10, boxY)
  local lonBox = makeFlatEditBox(addPanel)
  lonBox:SetSize(76, 22); lonBox:SetPoint("TOPLEFT", 96, boxY)
  local offBox = makeFlatEditBox(addPanel)
  offBox:SetSize(62, 22); offBox:SetPoint("TOPLEFT", 182, boxY)
  local euCheck = makeFlatCheck(addPanel)
  euCheck:SetPoint("TOPLEFT", 258, boxY - 2)
  Picker.euCheck = euCheck
  local euText = addPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  euText:SetPoint("LEFT", euCheck, "RIGHT", 6, 0); euText:SetText("EU DST"); euText:SetTextColor(unpack(COL.text))

  -- Name on its own full-width line.
  local nameLabelY = boxY - 30
  makeColLabel(addPanel, "Name", 12, nameLabelY)
  local nameBox = makeFlatEditBox(addPanel)
  nameBox:SetHeight(22)
  nameBox:SetPoint("TOPLEFT", 10, nameLabelY - 16); nameBox:SetPoint("RIGHT", addPanel, "RIGHT", -10, 0)
  Picker.nameBox, Picker.latBox, Picker.lonBox, Picker.offsetBox = nameBox, latBox, lonBox, offBox

  local clearErr = function() Picker.clearError() end
  nameBox:SetScript("OnTextChanged", clearErr)
  latBox:SetScript("OnTextChanged", clearErr)
  lonBox:SetScript("OnTextChanged", clearErr)
  offBox:SetScript("OnTextChanged", clearErr)

  -- Buttons spread across the width: Save (left), Use once (mid), Back (right).
  local btnY = nameLabelY - 46
  local saveBtn = makeFlatButton(addPanel, "Save as My City", true)
  saveBtn:SetSize(170, 26); saveBtn:SetPoint("TOPLEFT", 10, btnY)
  saveBtn:SetScript("OnClick", function()
    local ok = Picker.saveManual(nameBox:GetText(), latBox:GetText(), lonBox:GetText(),
      offBox:GetText(), euCheck:GetChecked())
    if ok then Picker.closeAddPanel() end
  end)
  local backBtn = makeFlatButton(addPanel, "Back")
  backBtn:SetSize(90, 26); backBtn:SetPoint("TOPRIGHT", addPanel, "TOPRIGHT", -10, btnY)
  backBtn:SetScript("OnClick", function() Picker.closeAddPanel() end)
  local useBtn = makeFlatButton(addPanel, "Use once")
  useBtn:SetSize(120, 26); useBtn:SetPoint("LEFT", saveBtn, "RIGHT", 10, 0)
  useBtn:SetScript("OnClick", function()
    local ok = Picker.applyManual(latBox:GetText(), lonBox:GetText(), offBox:GetText())
    if ok then Picker.closeAddPanel() end
  end)

  -- Tab order within the add form: Lat -> Lon -> UTC -> Name -> Lat.
  local function tabTo(a, b) a:SetScript("OnTabPressed", function() b:SetFocus() end) end
  tabTo(latBox, lonBox); tabTo(lonBox, offBox); tabTo(offBox, nameBox); tabTo(nameBox, latBox)

  Picker.errorLabel = addPanel:CreateFontString(nil, "OVERLAY", "GameFontRed")
  Picker.errorLabel:SetPoint("TOPLEFT", 10, btnY - 24)

  -- ===== Calculation tab (method dropdown + Asr description cards) =====
  local calcBg = calcP:CreateTexture(nil, "BACKGROUND")
  calcBg:SetAllPoints(); calcBg:SetColorTexture(unpack(COL.content))

  local mLabel = calcP:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  mLabel:SetPoint("TOPLEFT", 16, -16); mLabel:SetText("CALCULATION METHOD"); mLabel:SetTextColor(unpack(COL.gold))

  Picker.methodDropdown = makeDropdown(calcP, {
    width = 430, rows = 10,
    getOptions = function() return Methods.list() end,
    getCurrent = function() return Methods.resolveMethod(Picker.db and Picker.db.method) end,
    onSelect = function(key) Picker.setMethod(key) end,
  })
  Picker.methodDropdown.button:SetPoint("TOPLEFT", 16, -34)

  local aLabel = calcP:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  aLabel:SetPoint("TOPLEFT", 16, -78); aLabel:SetText("ASR SCHOOL"); aLabel:SetTextColor(unpack(COL.gold))

  -- Two selectable description cards, one per school (mutually exclusive).
  local ASR_DESC = {
    shafi = "Shafi'i, Maliki, Hanbali -- shadow = object length.",
    hanafi = "Shadow = twice the object length.",
  }
  Picker.asrCards = {}
  local cardW = 210
  for i, a in ipairs(Methods.asrList()) do
    local card = CreateFrame("Button", nil, calcP)
    card:SetSize(cardW, 72); card:SetPoint("TOPLEFT", 16 + (i - 1) * (cardW + 10), -96)
    card.key = a.key
    local cbg = card:CreateTexture(nil, "BACKGROUND"); cbg:SetAllPoints(); cbg:SetColorTexture(unpack(COL.cardOff))
    card.bg = cbg
    local barT = card:CreateTexture(nil, "ARTWORK")
    barT:SetPoint("TOPLEFT", 0, 0); barT:SetPoint("BOTTOMLEFT", 0, 0); barT:SetWidth(3)
    barT:SetColorTexture(unpack(COL.gold)); barT:Hide(); card.border = barT
    local ct = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ct:SetPoint("TOPLEFT", 12, -12); ct:SetText(a.label); ct:SetTextColor(unpack(COL.text)); card.title = ct
    local cd = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cd:SetPoint("TOPLEFT", 12, -32); cd:SetWidth(cardW - 24); cd:SetJustifyH("LEFT")
    cd:SetText(ASR_DESC[a.key] or ""); cd:SetTextColor(unpack(COL.muted))
    card:SetScript("OnClick", function() Picker.setMadhab(a.key) end)
    Picker.asrCards[i] = card
  end

  -- ===== Notifications tab (stepper + toggle switches) =====
  local notifBg = notifP:CreateTexture(nil, "BACKGROUND")
  notifBg:SetAllPoints(); notifBg:SetColorTexture(unpack(COL.content))

  -- Row helper: title + description, returns the row's y for the control.
  local function notifRow(y, title, desc)
    local t = notifP:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 16, y); t:SetText(title); t:SetTextColor(unpack(COL.text))
    local d = notifP:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d:SetPoint("TOPLEFT", 16, y - 18); d:SetWidth(300); d:SetJustifyH("LEFT")
    d:SetText(desc); d:SetTextColor(unpack(COL.muted))
  end
  local function separator(y)
    local s = notifP:CreateTexture(nil, "ARTWORK")
    s:SetPoint("TOPLEFT", 16, y); s:SetPoint("TOPRIGHT", -16, y); s:SetHeight(1)
    s:SetColorTexture(0, 0, 0, 0.12)
  end

  local nlabel = notifP:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nlabel:SetPoint("TOPLEFT", 16, -16); nlabel:SetText("REMINDER BEFORE PRAYER"); nlabel:SetTextColor(unpack(COL.gold))

  -- Before-prayer minutes stepper.
  notifRow(-36, "Alert before each prayer", "Applies to all five daily prayers. Set to Off to disable.")
  local minusBtn = makeFlatButton(notifP, "", false, "minus")
  minusBtn:SetSize(28, 24); minusBtn:SetPoint("TOPRIGHT", -120, -34)
  minusBtn:SetScript("OnClick", function() Picker.stepBeforeMinutes(-1) end)
  Picker.beforeValue = notifP:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  Picker.beforeValue:SetPoint("TOPRIGHT", -56, -40); Picker.beforeValue:SetWidth(58); Picker.beforeValue:SetJustifyH("CENTER")
  Picker.beforeValue:SetTextColor(unpack(COL.text))
  local plusBtn = makeFlatButton(notifP, "", false, "plus")
  plusBtn:SetSize(28, 24); plusBtn:SetPoint("TOPRIGHT", -16, -34)
  plusBtn:SetScript("OnClick", function() Picker.stepBeforeMinutes(1) end)

  separator(-84)

  -- Alert exactly at prayer time.
  notifRow(-100, "Alert exactly at prayer time", "Fire a notice the moment each prayer enters.")
  Picker.atToggle = makeToggle(notifP,
    function() return Picker.db and Picker.db.notify and Picker.db.notify.atTime end,
    function(v) Picker.setAtTime(v) end)
  Picker.atToggle.btn:SetPoint("TOPRIGHT", -16, -100)

  separator(-148)

  -- Notification sound.
  notifRow(-164, "Notification sound", "Play a chime with each alert.")
  Picker.soundToggle = makeToggle(notifP,
    function() return Picker.db and Picker.db.notify and Picker.db.notify.sound ~= false end,
    function(v) Picker.setSound(v) end)
  Picker.soundToggle.btn:SetPoint("TOPRIGHT", -16, -164)

  Picker.frame = f
  Picker.mScroll, Picker.dScroll = 0, 0
  Picker.showTab("location")
  Picker.updateSelected()
  Picker.updateNotifyControls()
  Picker.updateCalcControls()
  Picker.refreshLocation("")
  return f
end

function Picker.open()
  Picker.create()
  Picker.clearError()
  Picker.showTab(Picker.activeTab or "location")
  Picker.updateSelected()
  Picker.updateNotifyControls()
  Picker.updateCalcControls()
  Picker.closeAddPanel()
  Picker.refreshLocation(Picker.searchBox and Picker.searchBox:GetText() or "")
  Picker.frame:Show()
end

function Picker.close()
  if Picker.frame then Picker.frame:Hide() end
end

function Picker.toggle()
  if Picker.frame and Picker.frame:IsShown() then Picker.close() else Picker.open() end
end

-- Styled component factories + palette, exposed so the welcome wizard (ADR-0006)
-- reuses the exact same cream/gold widgets instead of duplicating them. Pure
-- builders (masterRows/detailRows/defaultCountry) are already on Picker above.
Picker.COL = COL
Picker.ui = {
  flatButton = makeFlatButton,
  flatEditBox = makeFlatEditBox,
  flatCheck = makeFlatCheck,
  scrollbar = makeScrollbar,
  dropdown = makeDropdown,
  toggle = makeToggle,
  colLabel = makeColLabel,
}

if PrayerTimesNS then PrayerTimesNS.modules.Picker = Picker end
return Picker
