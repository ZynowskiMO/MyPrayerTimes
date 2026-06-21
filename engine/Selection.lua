-- Selection.lua
-- Pure selected-city model: persists the player's choice (a bundled city by
-- name, or a manual lat/lon entry) in the SavedVariables DB and resolves it to
-- a city object the engine can use. Replaces the hardcoded default.
--
-- Manual-entry timezone (ADR-0003 addendum):
--   tz = "machine" (default) -> uses the player's live machine offset, supplied
--        by an INJECTED machineOffsetMinutes() so this stays runner-testable;
--        modelled as a fixed-offset "none" city refreshed each resolve.
--   tz = "fixed"            -> explicit baseUtcOffset + dstRule override.

local Cities = require("Cities")

local DEFAULT_CITY = "Rotterdam" -- temporary fallback until the 2d-4 picker / first run

local Selection = {}

-- Latitudes at/above the polar circles make the sun fail to cross the horizon
-- at the solstices, so sunrise/sunset (and thus Maghrib) are undefined. The
-- engine has no PolarCircleResolution yet (ADR-0003), so reject beyond this.
local POLAR_LIMIT = 65

-- Validate manual coordinates. Returns ok, errorMessage.
function Selection.validateCoords(lat, lon)
  if type(lat) ~= "number" or type(lon) ~= "number"
      or lat ~= lat or lon ~= lon then -- NaN guard
    return false, "Coordinates must be numbers"
  end
  if lat < -90 or lat > 90 then return false, "Latitude must be between -90 and 90" end
  if lon < -180 or lon > 180 then return false, "Longitude must be between -180 and 180" end
  if lat > POLAR_LIMIT or lat < -POLAR_LIMIT then
    return false, "Polar latitudes (beyond +/-65) are not supported"
  end
  return true
end

function Selection.setCity(db, name)
  db.selectedCity = { kind = "city", name = name }
  return true
end

-- opts.tz = "machine" | "fixed"; for "fixed": opts.baseUtcOffset, opts.dstRule.
function Selection.setManual(db, lat, lon, opts)
  opts = opts or {}
  local ok, err = Selection.validateCoords(lat, lon)
  if not ok then return false, err end
  local sel = { kind = "manual", latitude = lat, longitude = lon, tz = opts.tz or "machine" }
  if sel.tz == "fixed" then
    sel.baseUtcOffset = opts.baseUtcOffset or 0
    sel.dstRule = opts.dstRule or "none"
  end
  db.selectedCity = sel
  return true
end

function Selection.get(db)
  return db and db.selectedCity
end

-- ---- Saved user cities ("My Cities") -------------------------------------

local function trim(s)
  return type(s) == "string" and s:gsub("^%s+", ""):gsub("%s+$", "") or ""
end

-- Sanitise a user-entered name before it is stored and later displayed. WoW
-- interprets "|"-prefixed escape sequences (|c colour, |H clickable hyperlink,
-- |T texture, |n newline), so a crafted name could otherwise inject those into
-- the list, cards or chat output. Stripping every "|" neutralises all of them.
local function sanitizeName(s)
  return (trim(s):gsub("|", ""))
end

function Selection.getSavedCities(db)
  return (db and db.savedCities) or {}
end

function Selection.findSaved(db, name)
  if not (db and db.savedCities and type(name) == "string") then return nil end
  local lname = name:lower()
  for _, c in ipairs(db.savedCities) do
    -- Guard against a hand-edited / corrupt SavedVariables entry whose name is
    -- not a string (c.name:lower() would otherwise error).
    if type(c.name) == "string" and c.name:lower() == lname then return c end
  end
  return nil
end

-- Defence in depth: strip escape sequences from any saved names that predate
-- input sanitisation, so the display paths (lists, cards, header, window title)
-- never render injected colours/hyperlinks/textures even for legacy entries.
function Selection.normalizeSavedNames(db)
  if not (db and type(db.savedCities) == "table") then return end
  for _, c in ipairs(db.savedCities) do
    if type(c.name) == "string" then c.name = (c.name:gsub("|", "")) end
  end
  if db.selectedCity and db.selectedCity.kind == "saved" and type(db.selectedCity.name) == "string" then
    db.selectedCity.name = (db.selectedCity.name:gsub("|", ""))
  end
end

-- Save a named manual location. opts.tz = "machine" (default) | "fixed"
-- (+ opts.baseUtcOffset, opts.dstRule). Returns ok, errorMessage, savedName.
function Selection.saveCity(db, name, lat, lon, opts)
  opts = opts or {}
  name = sanitizeName(name)
  if name == "" then return false, "Enter a name for the city" end
  local ok, err = Selection.validateCoords(lat, lon)
  if not ok then return false, err end
  db.savedCities = db.savedCities or {}
  if Selection.findSaved(db, name) then
    return false, "A saved city named '" .. name .. "' already exists"
  end
  local entry = { name = name, latitude = lat, longitude = lon, tz = opts.tz or "machine" }
  if entry.tz == "fixed" then
    entry.baseUtcOffset = opts.baseUtcOffset or 0
    entry.dstRule = opts.dstRule or "none"
  end
  table.insert(db.savedCities, entry)
  return true, nil, name
end

function Selection.deleteCity(db, name)
  if not (db and db.savedCities and type(name) == "string") then return false end
  local lname = name:lower()
  for i, c in ipairs(db.savedCities) do
    if type(c.name) == "string" and c.name:lower() == lname then
      table.remove(db.savedCities, i)
      if db.selectedCity and db.selectedCity.kind == "saved"
          and db.selectedCity.name:lower() == lname then
        db.selectedCity = nil -- fall back to default
      end
      return true
    end
  end
  return false
end

-- Rename a saved city (nice-to-have). Returns ok, errorMessage.
function Selection.renameCity(db, oldName, newName)
  local entry = Selection.findSaved(db, oldName)
  if not entry then return false, "No such saved city" end
  newName = sanitizeName(newName)
  if newName == "" then return false, "Enter a name" end
  if newName:lower() ~= oldName:lower() and Selection.findSaved(db, newName) then
    return false, "A saved city named '" .. newName .. "' already exists"
  end
  if db.selectedCity and db.selectedCity.kind == "saved"
      and db.selectedCity.name:lower() == oldName:lower() then
    db.selectedCity.name = newName
  end
  entry.name = newName
  return true
end

function Selection.setSavedCity(db, name)
  db.selectedCity = { kind = "saved", name = name }
  return true
end

-- Build a city object from coordinates + a tz spec (shared by manual + saved).
local function buildTzCity(name, lat, lon, tz, baseUtcOffset, dstRule, machineOffsetMinutes)
  local city = { name = name, latitude = lat, longitude = lon }
  if tz == "fixed" then
    city.baseUtcOffset = baseUtcOffset or 0
    city.dstRule = dstRule or "none"
  else
    -- Machine tz: live offset already includes DST -> model as fixed "none".
    city.baseUtcOffset = (machineOffsetMinutes and machineOffsetMinutes()) or 0
    city.dstRule = "none"
  end
  return city
end

-- Resolve the selection to a city object { name, latitude, longitude,
-- baseUtcOffset, dstRule }. machineOffsetMinutes is an injected function
-- returning the player's live UTC offset in minutes (only used for tz="machine").
function Selection.resolve(db, machineOffsetMinutes)
  local sel = db and db.selectedCity

  if sel and sel.kind == "manual" then
    return buildTzCity("Manual", sel.latitude, sel.longitude,
      sel.tz, sel.baseUtcOffset, sel.dstRule, machineOffsetMinutes)
  elseif sel and sel.kind == "saved" then
    local s = Selection.findSaved(db, sel.name)
    if s then
      return buildTzCity(s.name, s.latitude, s.longitude,
        s.tz, s.baseUtcOffset, s.dstRule, machineOffsetMinutes)
    end
  end

  local name = (sel and sel.kind == "city" and sel.name) or DEFAULT_CITY
  return Cities.findByName(name) or Cities.findByName(DEFAULT_CITY)
end

if PrayerTimesNS then PrayerTimesNS.modules.Selection = Selection end
return Selection
