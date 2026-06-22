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
    -- structure
    winBorder  = { 0.10, 0.09, 0.07, 1 },
    winBg      = { 0.96, 0.94, 0.88, 0.96 }, -- main window body
    bg         = { 0.07, 0.06, 0.05, 0.97 }, -- settings window dark backing
    content    = { 0.96, 0.94, 0.88, 1 },    -- tab/page body
    header     = { 0.13, 0.11, 0.09, 1 },
    sidebar    = { 0.91, 0.88, 0.81, 1 },
    navHl      = { 0.97, 0.95, 0.90, 1 },
    card       = { 0.16, 0.13, 0.10, 1 },    -- dark current-location card
    line       = { 0.55, 0.50, 0.42, 1 },    -- widget outlines
    divider    = { 0, 0, 0, 0.15 },          -- thin separators
    -- text
    gold       = { 0.72, 0.58, 0.29, 1 },
    text       = { 0.16, 0.14, 0.11, 1 },
    muted      = { 0.45, 0.42, 0.36, 1 },
    nextText   = { 0.20, 0.14, 0.05, 1 },    -- on the gold highlight bar
    sunrise    = { 0.78, 0.49, 0.18, 1 },
    onDark     = { 0.97, 0.96, 0.92, 1 },    -- light text on dark surfaces
    dimText    = { 0.66, 0.62, 0.54, 1 },    -- muted light text on dark surfaces
    -- fills
    rowHl      = { 0.85, 0.78, 0.55, 0.6 },
    slot       = { 1.00, 0.99, 0.96, 0 }, -- transparent: prayer icons sit bare
    cardOff    = { 1.00, 0.99, 0.96, 1 },    -- input/unselected fill
    cardSel    = { 0.91, 0.85, 0.67, 1 },    -- selected option card
    knob       = { 0.98, 0.97, 0.94, 1 },    -- toggle/scrollbar knob
    arrow      = { 0.35, 0.32, 0.27, 1 },    -- dropdown chevron
    iconIdle   = { 0.30, 0.26, 0.20, 1 },
    -- option-card text (selected = high contrast)
    cardTitleOn  = { 0.14, 0.12, 0.09, 1 },
    cardTitleOff = { 0.50, 0.47, 0.41, 1 },
    cardDescOn   = { 0.34, 0.31, 0.26, 1 },
    cardDescOff  = { 0.60, 0.57, 0.51, 1 },
    -- buttons
    btnPrimary       = { 0.80, 0.63, 0.28, 1 },
    btnPrimaryHover  = { 0.88, 0.71, 0.35, 1 },
    btnSecondary     = { 0.88, 0.76, 0.46, 1 },
    btnSecondaryHover= { 0.93, 0.83, 0.55, 1 },
    btnText          = { 0.16, 0.12, 0.06, 1 },
  },
  dark = {
    winBorder  = { 0.02, 0.02, 0.02, 1 },
    winBg      = { 0.14, 0.13, 0.12, 0.97 },
    bg         = { 0.04, 0.04, 0.035, 0.97 },
    content    = { 0.14, 0.13, 0.12, 1 },
    header     = { 0.06, 0.05, 0.04, 1 },
    sidebar    = { 0.10, 0.09, 0.08, 1 },
    navHl      = { 0.20, 0.18, 0.15, 1 },
    card       = { 0.05, 0.045, 0.04, 1 },
    line       = { 0.34, 0.32, 0.28, 1 },
    divider    = { 1, 1, 1, 0.10 },
    gold       = { 0.85, 0.68, 0.35, 1 },
    text       = { 0.90, 0.87, 0.80, 1 },
    muted      = { 0.62, 0.58, 0.50, 1 },
    nextText   = { 0.16, 0.12, 0.05, 1 },
    sunrise    = { 0.95, 0.68, 0.32, 1 },
    onDark     = { 0.95, 0.93, 0.86, 1 },
    dimText    = { 0.66, 0.62, 0.54, 1 },
    rowHl      = { 0.80, 0.66, 0.34, 0.5 },
    slot       = { 1.00, 0.99, 0.96, 0 },
    cardOff    = { 0.20, 0.19, 0.17, 1 },
    cardSel    = { 0.42, 0.34, 0.18, 1 },
    knob       = { 0.92, 0.90, 0.85, 1 },
    arrow      = { 0.72, 0.68, 0.60, 1 },
    iconIdle   = { 0.62, 0.58, 0.50, 1 },
    cardTitleOn  = { 0.95, 0.92, 0.85, 1 },
    cardTitleOff = { 0.58, 0.55, 0.48, 1 },
    cardDescOn   = { 0.82, 0.79, 0.72, 1 },
    cardDescOff  = { 0.55, 0.52, 0.46, 1 },
    btnPrimary       = { 0.82, 0.64, 0.30, 1 },
    btnPrimaryHover  = { 0.90, 0.73, 0.38, 1 },
    btnSecondary     = { 0.55, 0.45, 0.26, 1 },
    btnSecondaryHover= { 0.66, 0.54, 0.32, 1 },
    btnText          = { 0.12, 0.09, 0.04, 1 },
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
