-- Cities.lua
-- Data-layer access to the bundled city list: lookup, search, and the
-- "selected city -> local prayer times" path. Combines the UTC engine
-- (Calculator, recommended high-latitude rule) with Timezone conversion
-- (per-city offset + DST) from ADR-0003. Returns local minute-of-day and
-- HH:MM strings ready for the Phase 2c display layer.

local Calculator = require("Calculator")
local Timezone = require("Timezone")

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

-- Prayer times for a city (table or name) on a date, in the city's local time.
-- Returns nil for an unknown name. Result:
--   { city, offsetMinutes, prayers = { <prayer> = { utc, localMin, hhmm } } }
function Cities.times(cityOrName, year, month, day)
  local city = type(cityOrName) == "table" and cityOrName or Cities.findByName(cityOrName)
  if not city then return nil end

  local coords = { latitude = city.latitude, longitude = city.longitude }
  local utc = Calculator.timesForLocation(year, month, day, coords)
  local offset = Timezone.offsetMinutes(city, year, month, day)

  local prayers = {}
  for _, p in ipairs(PRAYERS) do
    local localMin = Timezone.toLocalMinuteOfDay(utc[p], offset)
    prayers[p] = { utc = utc[p], localMin = localMin, hhmm = Timezone.formatHHMM(localMin) }
  end

  return { city = city, offsetMinutes = offset, prayers = prayers }
end

return Cities
