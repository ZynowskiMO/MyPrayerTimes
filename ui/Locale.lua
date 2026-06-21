-- ui/Locale.lua
-- Localisation scaffold (Phase 4). English (enUS) is the baseline: for enUS each
-- value equals its key, so wiring a string is simply L["Some text"], and any
-- string not yet routed through L still works (the __index fallback returns the
-- key). Translators add Locale.register("frFR", { ["Location"] = "Lieu", ... }).
-- UI strings migrate onto L incrementally; this checkpoint ships the mechanism,
-- the English catalogue, and a first wired surface (the wizard page titles).

local Locale = {}

local catalogs = {} -- locale -> { key = translated }
local active = {}   -- merged active strings for the chosen locale

-- L: lookup with key-as-fallback, so untranslated / not-yet-wired text is safe.
Locale.L = setmetatable({}, { __index = function(_, k) return active[k] or k end })

function Locale.register(locale, tbl)
  catalogs[locale] = catalogs[locale] or {}
  for k, v in pairs(tbl) do catalogs[locale][k] = v end
end

-- Build the active table: English baseline, overlaid by the chosen locale.
function Locale.use(locale)
  active = {}
  for k, v in pairs(catalogs.enUS or {}) do active[k] = v end
  if locale and locale ~= "enUS" and catalogs[locale] then
    for k, v in pairs(catalogs[locale]) do active[k] = v end
  end
  Locale.current = locale or "enUS"
end

-- English baseline catalogue: the translatable surface. Value == key for enUS.
Locale.register("enUS", {
  -- Sections / wizard pages
  ["Location"] = "Location",
  ["Calculation"] = "Calculation",
  ["Notifications"] = "Notifications",
  ["Welcome"] = "Welcome",
  ["All set"] = "All set",
  -- Buttons
  ["Back"] = "Back",
  ["Next"] = "Next",
  ["Skip"] = "Skip",
  ["Done"] = "Done",
  ["Save as My City"] = "Save as My City",
  ["Use once"] = "Use once",
  ["+ Add custom location"] = "+ Add custom location",
  -- Labels
  ["CALCULATION METHOD"] = "CALCULATION METHOD",
  ["ASR SCHOOL"] = "ASR SCHOOL",
  ["CURRENT LOCATION"] = "CURRENT LOCATION",
  ["Search all cities..."] = "Search all cities...",
})

local function detectLocale()
  if type(GetLocale) == "function" then return GetLocale() end
  return "enUS"
end

Locale.use(detectLocale())

if PrayerTimesNS then
  PrayerTimesNS.modules.Locale = Locale
  PrayerTimesNS.L = Locale.L
end
return Locale
