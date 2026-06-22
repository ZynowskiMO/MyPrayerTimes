-- ui/Theme.lua
-- Theming (ADR-0009). Two palettes (Light = the cream/gold look, Dark) keyed by
-- colour ROLE. UI code paints through Theme.tex/Theme.txt, which apply the
-- active colour now AND record the region, so Theme.set() can repaint everything
-- live. State-dependent colours read Theme.color() at update time, so re-running
-- the registered hooks (window refreshes) repaints them too. Persisted in
-- PrayerTimesDB.theme. Pure colour work -- loads under the test runner.

local Theme = {}

local PALETTES = {
  light = {
    winBorder  = { 0.10, 0.09, 0.07, 1 },
    winBg      = { 0.96, 0.94, 0.88, 0.96 },
    header     = { 0.13, 0.11, 0.09, 1 },
    gold       = { 0.72, 0.58, 0.29, 1 },
    text       = { 0.16, 0.14, 0.11, 1 },     -- normal text on the body
    nextText   = { 0.20, 0.14, 0.05, 1 },     -- text on the gold highlight bar
    sunrise    = { 0.78, 0.49, 0.18, 1 },     -- Sunrise marker
    rowHl      = { 0.85, 0.78, 0.55, 0.7 },   -- next-prayer highlight bar
    slot       = { 1.00, 0.99, 0.96, 0.55 },  -- icon slot
    onDark     = { 0.97, 0.96, 0.92, 1 },     -- text on the dark header/footer
    iconIdle   = { 0.30, 0.26, 0.20, 1 },     -- other prayer icons
  },
  dark = {
    winBorder  = { 0.02, 0.02, 0.02, 1 },
    winBg      = { 0.14, 0.13, 0.12, 0.97 },
    header     = { 0.06, 0.05, 0.04, 1 },
    gold       = { 0.85, 0.68, 0.35, 1 },
    text       = { 0.90, 0.87, 0.80, 1 },
    nextText   = { 0.16, 0.12, 0.05, 1 },
    sunrise    = { 0.95, 0.68, 0.32, 1 },
    rowHl      = { 0.80, 0.66, 0.34, 0.5 },
    slot       = { 1.00, 0.99, 0.96, 0.08 },
    onDark     = { 0.95, 0.93, 0.86, 1 },
    iconIdle   = { 0.60, 0.56, 0.48, 1 },
  },
}

Theme.activeName = "light"

function Theme.color(role)
  local p = PALETTES[Theme.activeName] or PALETTES.light
  return p[role] or PALETTES.light[role] or { 1, 1, 1, 1 }
end

Theme.registry, Theme.hooks = {}, {}

-- Paint a texture fill from a role and remember it for live re-theming.
function Theme.tex(region, role)
  region:SetColorTexture(unpack(Theme.color(role)))
  Theme.registry[#Theme.registry + 1] = { region, "tex", role }
  return region
end

-- Paint a fontstring colour from a role and remember it.
function Theme.txt(fs, role)
  fs:SetTextColor(unpack(Theme.color(role)))
  Theme.registry[#Theme.registry + 1] = { fs, "txt", role }
  return fs
end

-- Modules register a repaint hook for their state-dependent colours.
function Theme.addHook(fn) Theme.hooks[#Theme.hooks + 1] = fn end

function Theme.apply()
  for _, e in ipairs(Theme.registry) do
    if e[2] == "tex" then e[1]:SetColorTexture(unpack(Theme.color(e[3])))
    else e[1]:SetTextColor(unpack(Theme.color(e[3]))) end
  end
  for _, fn in ipairs(Theme.hooks) do fn() end
end

function Theme.set(name)
  if not PALETTES[name] then return false end
  Theme.activeName = name
  if Theme.db then Theme.db.theme = name end
  Theme.apply()
  return true
end

function Theme.init(db)
  Theme.db = db
  if db and PALETTES[db.theme] then Theme.activeName = db.theme end
end

function Theme.current() return Theme.activeName end
function Theme.isDark() return Theme.activeName == "dark" end

if PrayerTimesNS then PrayerTimesNS.modules.Theme = Theme end
return Theme
