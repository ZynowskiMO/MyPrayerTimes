-- Cities.lua
-- Data-layer access to the bundled city list: lookup, search, and the
-- "selected city -> local prayer times" path. Combines the UTC engine
-- (Calculator, recommended high-latitude rule) with Timezone conversion
-- (per-city offset + DST) from ADR-0003. Returns local minute-of-day and
-- HH:MM strings ready for the Phase 2c display layer.

local Calculator = require("Calculator")
local Timezone = require("Timezone")
local Methods = require("Methods")

-- Directory-qualified token avoids a case-insensitive-filesystem clash
-- between data/cities.lua and engine/Cities.lua in the test harness.
-- (In WoW the list is loaded via the .toc, not require; wired in 2c.)
local CITY_LIST = require("data.cities")

local PRAYERS = { "fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha" }

local Cities = {}

function Cities.all()
  return CITY_LIST
end

-- Exact, case-insensitive name match.
function Cities.findByName(name)
  if type(name) ~= "string" then return nil end
  local needle = name:lower()
  for _, city in ipairs(CITY_LIST) do
    if city.name:lower() == needle then return city end
  end
  return nil
end

-- Case-insensitive substring search over name and country, name-sorted.
function Cities.search(query)
  local results = {}
  if type(query) ~= "string" or query == "" then return results end
  local needle = query:lower()
  for _, city in ipairs(CITY_LIST) do
    if city.name:lower():find(needle, 1, true)
        or city.country:lower():find(needle, 1, true) then
      results[#results + 1] = city
    end
  end
  table.sort(results, function(a, b) return a.name < b.name end)
  return results
end

-- Cities grouped by country for the picker: an array of { country, cities },
-- countries sorted A-Z and each country's cities sorted by name.
function Cities.byCountry()
  local groups = {}
  for _, city in ipairs(CITY_LIST) do
    groups[city.country] = groups[city.country] or {}
    table.insert(groups[city.country], city)
  end
  local ordered = {}
  for country, list in pairs(groups) do
    table.sort(list, function(a, b) return a.name < b.name end)
    ordered[#ordered + 1] = { country = country, cities = list }
  end
  table.sort(ordered, function(a, b) return a.country < b.country end)
  return ordered
end

-- Flat row list for the picker. Empty query -> country headers + their cities;
-- non-empty -> flat sorted matches. Each row is {kind="header",label=} or
-- {kind="city",city=}. Pure (the WoW picker just renders these rows).
function Cities.displayList(query)
  local rows = {}
  if not query or query == "" then
    for _, group in ipairs(Cities.byCountry()) do
      rows[#rows + 1] = { kind = "header", label = group.country }
      for _, c in ipairs(group.cities) do rows[#rows + 1] = { kind = "city", city = c } end
    end
  else
    for _, c in ipairs(Cities.search(query)) do
      rows[#rows + 1] = { kind = "city", city = c }
    end
  end
  return rows
end

-- Prayer times for a city (table or name) on a date, in the city's local time.
-- Returns nil for an unknown name. opts.method / opts.madhab select the
-- calculation method + Asr school (keys from Methods); unknown/nil fall back to
-- the defaults (MWL / Standard), so omitting opts preserves the original
-- behaviour exactly. Result:
--   { city, offsetMinutes, prayers = { <prayer> = { utc, localMin, hhmm } } }
function Cities.times(cityOrName, year, month, day, opts)
  local city = type(cityOrName) == "table" and cityOrName or Cities.findByName(cityOrName)
  if not city then return nil end

  opts = opts or {}
  local coords = { latitude = city.latitude, longitude = city.longitude }
  local params = Methods.params(opts.method, opts.madhab)
  local utc = Calculator.timesForLocation(year, month, day, coords, { params = params })
  local offset = Timezone.offsetMinutes(city, year, month, day)

  local prayers = {}
  for _, p in ipairs(PRAYERS) do
    local u = utc[p]
    if u == nil then -- non-finite time (e.g. polar) -> fail safe
      prayers[p] = { utc = nil, localMin = nil, hhmm = "--:--" }
    else
      local localMin = Timezone.toLocalMinuteOfDay(u, offset)
      prayers[p] = { utc = u, localMin = localMin, hhmm = Timezone.formatHHMM(localMin) }
    end
  end

  return { city = city, offsetMinutes = offset, prayers = prayers }
end

if PrayerTimesNS then PrayerTimesNS.modules.Cities = Cities end
return Cities
