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
    row.check:SetText(""); row.hl:Hide()
    row.name, row._selected = nil, false
    if not e then
      row:Hide()
    else
      local isSel = (e.city.name == selCity)
      row.label:SetText(e.city.name); row.name, row._selected = e.city.name, isSel
      if isSel then row.hl:Show(); row.check:SetText("|cffb89254\226\156\147|r") end
      row:Show()
    end
  end
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
  if Picker.methodDropdown then Picker.methodDropdown:updateButton() end
  if Picker.asrRadios then
    local cur = Methods.resolveMadhab(db and db.madhab)
    for _, r in ipairs(Picker.asrRadios) do r:SetChecked(r.key == cur) end
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

  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width, 22)
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
  local pbg = popup:CreateTexture(nil, "BACKGROUND")
  pbg:SetAllPoints(); pbg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
  popup:Hide()
  dd.popup = popup

  dd.rows = {}
  for i = 1, vis do
    local row = CreateFrame("Button", nil, popup)
    row:SetSize(width - 8, DD_ROW_H)
    row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * DD_ROW_H)
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(); hl:SetColorTexture(0.15, 0.5, 0.25, 0.6); hl:Hide()
    row.hl = hl
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 4, 0); label:SetJustifyH("LEFT")
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

  function dd:updateButton() dd.button:SetText(dd:currentLabel()) end

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

-- Palette (cream / charcoal / gold). Content stays dark in 3S-1 so the existing
-- light-text controls remain readable; each tab is converted to cream + dark
-- text as it is rebuilt (3S-2/3S-4/3S-5), with a final pass in 3S-6.
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

  local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  x:SetPoint("TOPRIGHT", -6, -8)
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
    panel:SetPoint("TOPLEFT", f, "TOPLEFT", 196, -54)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 12)
    Picker.panels[t.key] = panel
  end
  local locP, calcP, notifP = Picker.panels.location, Picker.panels.calculation, Picker.panels.notifications

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

  -- Search across all cities.
  local search = CreateFrame("EditBox", "PrayerTimesPickerSearch", locP, "InputBoxTemplate")
  search:SetSize(434, 22); search:SetPoint("TOPLEFT", 12, -58); search:SetAutoFocus(false)
  search:SetScript("OnTextChanged", function(self) Picker.dScroll = 0; Picker.refreshLocation(self:GetText()) end)
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
    local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    del:SetSize(18, 14); del:SetPoint("RIGHT", -4, 0); del:SetText("x"); del:Hide(); row.delBtn = del
    row:SetScript("OnClick", function(self)
      if self.kind == "country" then Picker.selectCountry(self.country)
      elseif self.kind == "saved" then Picker.selectSaved(self.name) end
    end)
    Picker.masterPool[i] = row
  end

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
    local check = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    check:SetPoint("RIGHT", -8, 0); row.check = check
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 10, 0); label:SetJustifyH("LEFT"); label:SetTextColor(unpack(COL.text)); row.label = label
    row:SetScript("OnClick", function(self) if self.name then Picker.selectCity(self.name) end end)
    Picker.detailPool[i] = row
  end

  local addBtn = CreateFrame("Button", nil, browse, "UIPanelButtonTemplate")
  addBtn:SetSize(232, 22); addBtn:SetPoint("BOTTOMLEFT", 214, 10); addBtn:SetText("+ Add custom location")
  addBtn:SetScript("OnClick", function() Picker.openAddPanel() end)

  -- Add-custom-location form (overlay; logic unchanged from 3R-3). Opaque cream
  -- background, raised above the browse container so nothing shows through.
  local addPanel = CreateFrame("Frame", nil, locP)
  addPanel:SetPoint("TOPLEFT", 6, -86); addPanel:SetPoint("BOTTOMRIGHT", -6, 8)
  addPanel:SetFrameLevel(locP:GetFrameLevel() + 10)
  local apbg = addPanel:CreateTexture(nil, "BACKGROUND"); apbg:SetAllPoints(); apbg:SetColorTexture(unpack(COL.content))
  addPanel:Hide(); Picker.addPanel = addPanel

  local at = addPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  at:SetPoint("TOPLEFT", 8, -6); at:SetText("Add custom location"); at:SetTextColor(unpack(COL.text))

  makeColLabel(addPanel, "Lat", 12, -30)
  makeColLabel(addPanel, "Lon", 68, -30)
  makeColLabel(addPanel, "UTC+/-", 124, -30)
  local boxY = -44
  local latBox = CreateFrame("EditBox", nil, addPanel, "InputBoxTemplate")
  latBox:SetSize(48, 20); latBox:SetPoint("TOPLEFT", 10, boxY); latBox:SetAutoFocus(false)
  local lonBox = CreateFrame("EditBox", nil, addPanel, "InputBoxTemplate")
  lonBox:SetSize(48, 20); lonBox:SetPoint("TOPLEFT", 66, boxY); lonBox:SetAutoFocus(false)
  local offBox = CreateFrame("EditBox", nil, addPanel, "InputBoxTemplate")
  offBox:SetSize(42, 20); offBox:SetPoint("TOPLEFT", 122, boxY); offBox:SetAutoFocus(false)
  local euCheck = CreateFrame("CheckButton", nil, addPanel, "UICheckButtonTemplate")
  euCheck:SetSize(20, 20); euCheck:SetPoint("TOPLEFT", 172, boxY + 1)
  Picker.euCheck = euCheck
  local euText = addPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  euText:SetPoint("LEFT", euCheck, "RIGHT", 0, 0); euText:SetText("EU DST")

  local nameLabelY = boxY - 28
  makeColLabel(addPanel, "Name", 12, nameLabelY)
  local nameBox = CreateFrame("EditBox", nil, addPanel, "InputBoxTemplate")
  nameBox:SetSize(282, 20); nameBox:SetPoint("TOPLEFT", 10, nameLabelY - 14); nameBox:SetAutoFocus(false)
  Picker.nameBox, Picker.latBox, Picker.lonBox, Picker.offsetBox = nameBox, latBox, lonBox, offBox

  local clearErr = function() Picker.clearError() end
  nameBox:SetScript("OnTextChanged", clearErr)
  latBox:SetScript("OnTextChanged", clearErr)
  lonBox:SetScript("OnTextChanged", clearErr)
  offBox:SetScript("OnTextChanged", clearErr)

  local btnY = nameLabelY - 42
  local saveBtn = CreateFrame("Button", nil, addPanel, "UIPanelButtonTemplate")
  saveBtn:SetSize(120, 22); saveBtn:SetPoint("TOPLEFT", 10, btnY); saveBtn:SetText("Save as My City")
  saveBtn:SetScript("OnClick", function()
    local ok = Picker.saveManual(nameBox:GetText(), latBox:GetText(), lonBox:GetText(),
      offBox:GetText(), euCheck:GetChecked())
    if ok then Picker.closeAddPanel() end
  end)
  local useBtn = CreateFrame("Button", nil, addPanel, "UIPanelButtonTemplate")
  useBtn:SetSize(80, 22); useBtn:SetPoint("TOPLEFT", 136, btnY); useBtn:SetText("Use once")
  useBtn:SetScript("OnClick", function()
    local ok = Picker.applyManual(latBox:GetText(), lonBox:GetText(), offBox:GetText())
    if ok then Picker.closeAddPanel() end
  end)
  local backBtn = CreateFrame("Button", nil, addPanel, "UIPanelButtonTemplate")
  backBtn:SetSize(60, 22); backBtn:SetPoint("TOPLEFT", 226, btnY); backBtn:SetText("Back")
  backBtn:SetScript("OnClick", function() Picker.closeAddPanel() end)

  -- Tab order within the add form: Lat -> Lon -> UTC -> Name -> Lat.
  local function tabTo(a, b) a:SetScript("OnTabPressed", function() b:SetFocus() end) end
  tabTo(latBox, lonBox); tabTo(lonBox, offBox); tabTo(offBox, nameBox); tabTo(nameBox, latBox)

  Picker.errorLabel = addPanel:CreateFontString(nil, "OVERLAY", "GameFontRed")
  Picker.errorLabel:SetPoint("TOPLEFT", 10, btnY - 24)

  -- ===== Calculation tab (method dropdown + Asr radio buttons) =====
  local mLabel = calcP:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  mLabel:SetPoint("TOPLEFT", 14, -12); mLabel:SetText("Calculation method")

  Picker.methodDropdown = makeDropdown(calcP, {
    width = 294, rows = 8,
    getOptions = function() return Methods.list() end,
    getCurrent = function() return Methods.resolveMethod(Picker.db and Picker.db.method) end,
    onSelect = function(key) Picker.setMethod(key) end,
  })
  Picker.methodDropdown.button:SetPoint("TOPLEFT", 16, -32)

  local aLabel = calcP:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  aLabel:SetPoint("TOPLEFT", 14, -68); aLabel:SetText("Asr school")

  Picker.asrRadios = {}
  for i, a in ipairs(Methods.asrList()) do
    local radio = CreateFrame("CheckButton", nil, calcP, "UIRadioButtonTemplate")
    radio:SetPoint("TOPLEFT", 18, -88 - (i - 1) * 24)
    radio.key = a.key
    radio:SetScript("OnClick", function() Picker.setMadhab(a.key) end)
    local t = calcP:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("LEFT", radio, "RIGHT", 4, 0); t:SetText(a.label)
    Picker.asrRadios[i] = radio
  end

  -- ===== Notifications tab =====
  local nlabel = notifP:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nlabel:SetPoint("TOPLEFT", 14, -10); nlabel:SetText("Notifications:")

  local beforeBox = CreateFrame("EditBox", nil, notifP, "InputBoxTemplate")
  beforeBox:SetSize(40, 20); beforeBox:SetPoint("TOPLEFT", 20, -32)
  beforeBox:SetAutoFocus(false); beforeBox:SetNumeric(true)
  beforeBox:SetScript("OnTextChanged", function(self) Picker.setBeforeMinutes(self:GetText()) end)
  Picker.beforeBox = beforeBox
  local bLabel = notifP:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bLabel:SetPoint("LEFT", beforeBox, "RIGHT", 6, 0); bLabel:SetText("minutes before (0 = off)")

  local atCheck = CreateFrame("CheckButton", nil, notifP, "UICheckButtonTemplate")
  atCheck:SetPoint("TOPLEFT", 18, -56)
  atCheck:SetScript("OnClick", function(self) Picker.setAtTime(self:GetChecked() and true or false) end)
  Picker.atCheck = atCheck
  local atText = notifP:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  atText:SetPoint("LEFT", atCheck, "RIGHT", 2, 0); atText:SetText("Alert at prayer time")

  local soundCheck = CreateFrame("CheckButton", nil, notifP, "UICheckButtonTemplate")
  soundCheck:SetPoint("TOPLEFT", 18, -80)
  soundCheck:SetScript("OnClick", function(self) Picker.setSound(self:GetChecked() and true or false) end)
  Picker.soundCheck = soundCheck
  local sText = notifP:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sText:SetPoint("LEFT", soundCheck, "RIGHT", 2, 0); sText:SetText("Play sound")

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

if PrayerTimesNS then PrayerTimesNS.modules.Picker = Picker end
return Picker
