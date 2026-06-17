-- bootstrap.lua
-- WoW-only loader shim (NOT loaded by the luajit test runner). The engine and
-- data files use require()/return so they run under the runner; in WoW there
-- is no require(), so this provides one backed by a registry that each file
-- writes into via a guarded one-line export. The .toc load order supplies the
-- dependency order, so by the time a file calls require("Dependency") the
-- dependency has already registered itself.

local addonName, ns = ...

_G.PrayerTimesNS = ns
ns.modules = {}

if not _G.require then
  function _G.require(name)
    local key = name:match("[^.]+$") -- "data.cities" -> "cities"
    local mod = ns.modules[key]
    if not mod then
      error("PrayerTimes: module '" .. tostring(name)
        .. "' not loaded yet (check .toc order)")
    end
    return mod
  end
end
