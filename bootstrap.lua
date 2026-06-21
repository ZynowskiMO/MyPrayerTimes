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

-- We expose require() globally so the same engine/ui files run unchanged under
-- the LuaJIT test runner (which has a real require). To stay a good citizen on a
-- client with other addons, we do NOT blindly overwrite an existing require:
-- - our require resolves our own modules from the registry first;
-- - any other module name is delegated to whatever require existed before us
--   (so we never break another addon's shim);
-- - and we always install ours, so our own require() calls work even if another
--   addon defined a require first.
local prevRequire = _G.require
local function ptRequire(name)
  local key = name:match("[^.]+$") -- "data.cities" -> "cities"
  local mod = ns.modules[key]
  if mod then return mod end
  if prevRequire then return prevRequire(name) end
  error("PrayerTimes: module '" .. tostring(name)
    .. "' not loaded yet (check .toc order)")
end

ns.require = ptRequire -- namespaced handle, for callers that prefer not to use _G
_G.require = ptRequire
