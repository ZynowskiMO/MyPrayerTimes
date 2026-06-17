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

-- Resolve the selection to a city object { name, latitude, longitude,
-- baseUtcOffset, dstRule }. machineOffsetMinutes is an injected function
-- returning the player's live UTC offset in minutes (only used for tz="machine").
function Selection.resolve(db, machineOffsetMinutes)
  local sel = db and db.selectedCity

  if sel and sel.kind == "manual" then
    local city = { name = "Manual", latitude = sel.latitude, longitude = sel.longitude }
    if sel.tz == "fixed" then
      city.baseUtcOffset = sel.baseUtcOffset or 0
      city.dstRule = sel.dstRule or "none"
    else
      -- Machine tz: live offset already includes DST -> model as fixed "none".
      city.baseUtcOffset = (machineOffsetMinutes and machineOffsetMinutes()) or 0
      city.dstRule = "none"
    end
    return city
  end

  local name = (sel and sel.kind == "city" and sel.name) or DEFAULT_CITY
  return Cities.findByName(name) or Cities.findByName(DEFAULT_CITY)
end

if PrayerTimesNS then PrayerTimesNS.modules.Selection = Selection end
return Selection
