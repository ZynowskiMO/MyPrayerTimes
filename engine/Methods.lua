-- Methods.lua
-- The single registry of calculation methods and Asr schools (ADR-0004). Both
-- the settings UI (for its dropdown/labels) and the resolver (for building
-- engine parameters) read from here, so the two can never drift apart.
--
-- Methods.params(methodKey, madhabKey) is the one entry point that turns a
-- persisted pair of keys into a CalculationParameters table. Unknown, stale, or
-- nil keys fall back to the defaults (MWL / Standard) rather than erroring, so a
-- bad saved value can never break the window. Pure Lua: no WoW globals.

local CalculationMethod = require("CalculationMethod")
local Madhab = require("Madhab")

local Methods = {}

Methods.DEFAULT_METHOD = "MuslimWorldLeague"
Methods.DEFAULT_MADHAB = Madhab.Shafi -- "shafi"

-- Ordered for display; default (MWL) first. Keys match CalculationMethod factory
-- names exactly. Labels are user-facing.
local METHOD_LIST = {
  { key = "MuslimWorldLeague", label = "Muslim World League" },
  { key = "Egyptian",          label = "Egyptian General Authority" },
  { key = "Karachi",           label = "University of Islamic Sciences, Karachi" },
  { key = "UmmAlQura",         label = "Umm al-Qura, Makkah" },
  { key = "Dubai",             label = "Dubai" },
  { key = "NorthAmerica",      label = "ISNA (North America)" },
  { key = "Kuwait",            label = "Kuwait" },
  { key = "Qatar",             label = "Qatar" },
  { key = "Singapore",         label = "Singapore" },
  { key = "Tehran",            label = "Institute of Geophysics, Tehran" },
  { key = "Turkey",            label = "Diyanet (Turkey)" },
  { key = "Other",             label = "Other (no angles)" },
}

local ASR_LIST = {
  { key = Madhab.Shafi,  label = "Standard (Shafi)" },
  { key = Madhab.Hanafi, label = "Hanafi" },
}

-- key -> label lookups + a validity set, built once from the ordered lists.
local METHOD_LABEL, METHOD_VALID = {}, {}
for _, m in ipairs(METHOD_LIST) do
  METHOD_LABEL[m.key] = m.label
  METHOD_VALID[m.key] = true
end
local ASR_LABEL, ASR_VALID = {}, {}
for _, a in ipairs(ASR_LIST) do
  ASR_LABEL[a.key] = a.label
  ASR_VALID[a.key] = true
end

function Methods.list() return METHOD_LIST end
function Methods.asrList() return ASR_LIST end

function Methods.isMethod(key) return METHOD_VALID[key] == true end
function Methods.isMadhab(key) return ASR_VALID[key] == true end

-- Resolve to a valid key, falling back to the default for unknown/nil/stale.
function Methods.resolveMethod(key)
  if Methods.isMethod(key) then return key end
  return Methods.DEFAULT_METHOD
end

function Methods.resolveMadhab(key)
  if Methods.isMadhab(key) then return key end
  return Methods.DEFAULT_MADHAB
end

function Methods.methodLabel(key)
  return METHOD_LABEL[Methods.resolveMethod(key)]
end

function Methods.madhabLabel(key)
  return ASR_LABEL[Methods.resolveMadhab(key)]
end

-- Build a CalculationParameters table for a persisted (method, madhab) pair,
-- with safe fallback. This is what the resolver passes to the Calculator.
function Methods.params(methodKey, madhabKey)
  local key = Methods.resolveMethod(methodKey)
  local params = CalculationMethod[key]()
  params.madhab = Methods.resolveMadhab(madhabKey)
  return params
end

if PrayerTimesNS then PrayerTimesNS.modules.Methods = Methods end
return Methods
