-- ui/Icons.lua
-- Per-prayer icon registry (ADR-0007). Each prayer key maps to a bundled icon
-- texture under Media/icons/ (rasterised from Lucide, MIT). Until the final art
-- is added in 3I-2, USE_PLACEHOLDER draws a tinted placeholder so the row layout
-- is verifiable in-game now. Icons.apply is the single place that sets a row's
-- icon, so swapping placeholders for final art is a one-flag / one-line change.

local Theme = require("Theme")

local Icons = {}

Icons.MEDIA = "Interface\\AddOns\\PrayerTimes\\Media\\icons\\"
Icons.USE_PLACEHOLDER = false -- final Lucide .tga art present (Media/icons); see 3I-2

-- Lucide icon name behind each prayer (also the .tga file name for 3I-2).
Icons.LUCIDE = {
  fajr = "moon", sunrise = "sunrise", dhuhr = "sun",
  asr = "sun", maghrib = "sunset", isha = "moon-star",
}

-- Warm per-prayer placeholder tints (pre-dawn -> day -> dusk -> night) so the
-- six slots read distinctly while we wait for the real icons.
Icons.PLACEHOLDER_TINT = {
  fajr    = { 0.45, 0.50, 0.62, 1 }, -- pre-dawn blue
  sunrise = { 0.90, 0.66, 0.32, 1 }, -- sunrise amber
  dhuhr   = { 0.86, 0.72, 0.30, 1 }, -- midday gold
  asr     = { 0.80, 0.62, 0.28, 1 }, -- afternoon gold
  maghrib = { 0.78, 0.45, 0.30, 1 }, -- sunset rust
  isha    = { 0.38, 0.40, 0.55, 1 }, -- night indigo
}

function Icons.path(key)
  return Icons.MEDIA .. (Icons.LUCIDE[key] or key) .. ".tga"
end

-- Chrome / control icons (3I-3): logical name -> Lucide file. Same bundled set,
-- same Media/icons folder. White-on-transparent, so callers tint via
-- SetVertexColor to suit their background.
Icons.UI = {
  settings = "settings", close = "x", minimize = "minus", restore = "plus",
  chevron = "chevron-down", check = "check", trash = "trash-2",
  minus = "minus", plus = "plus",
}

function Icons.uiPath(name)
  return Icons.MEDIA .. (Icons.UI[name] or name) .. ".tga"
end

-- Set a Texture to a chrome icon, optionally tinted (r,g,b in 0..1).
function Icons.setUI(tex, name, r, g, b)
  if not tex then return end
  tex:SetTexture(Icons.uiPath(name))
  if r then tex:SetVertexColor(r, g, b) end
end

-- Apply the icon for `key` to a Texture. With final art, active rows tint gold
-- and the rest a muted brown; placeholders just show their per-prayer tint.
function Icons.apply(tex, key, active)
  if not tex then return end
  if Icons.USE_PLACEHOLDER then
    local t = Icons.PLACEHOLDER_TINT[key] or { 0.72, 0.58, 0.29, 1 }
    tex:SetColorTexture(t[1], t[2], t[3], t[4] or 1)
  else
    tex:SetTexture(Icons.path(key))
    tex:SetVertexColor(unpack(Theme.color(active and "iconActive" or "iconIdle")))
  end
end

if PrayerTimesNS then PrayerTimesNS.modules.Icons = Icons end
return Icons
