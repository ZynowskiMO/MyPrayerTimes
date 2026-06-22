-- ui/Minimap.lua
-- Hand-rolled minimap button (ADR-0008) -- no external libraries. A round button
-- on the minimap edge, draggable around it; left-click toggles the prayer
-- window, right-click opens settings. Position (angle) + hidden state persist in
-- PrayerTimesDB.minimap. WoW calls live inside functions so the runner can load
-- this under the mock.

local Window = require("Window")
local Picker = require("Picker")

local Minimap = {}
local LOGO = "Interface\\AddOns\\PrayerTimes\\Media\\logo.tga"
local CIRCLE_MASK = "Interface\\Masks\\CircleMaskScalable"
local DEFAULT_ANGLE = 220

function Minimap.init(db)
  Minimap.db = db
  if db then
    db.minimap = db.minimap or {}
    if db.minimap.angle == nil then db.minimap.angle = DEFAULT_ANGLE end
    if db.minimap.hide == nil then db.minimap.hide = false end
  end
end

-- Pure: button-centre offset from the minimap centre for a given edge angle.
function Minimap.offset(angleDeg, radius)
  local a = math.rad(angleDeg or DEFAULT_ANGLE)
  return radius * math.cos(a), radius * math.sin(a)
end

local function radius()
  local mw = _G.Minimap and _G.Minimap.GetWidth and _G.Minimap:GetWidth()
  return (type(mw) == "number" and mw / 2 or 70) + 5
end

function Minimap.updatePosition()
  local b = Minimap.button
  if not b then return end
  local angle = Minimap.db and Minimap.db.minimap and Minimap.db.minimap.angle
  local x, y = Minimap.offset(angle, radius())
  b:ClearAllPoints(); b:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

-- Follow the cursor around the minimap edge while dragging; persist the angle.
local function dragUpdate()
  local mx, my = _G.Minimap:GetCenter()
  if type(mx) ~= "number" then return end
  local scale = _G.Minimap:GetEffectiveScale() or 1
  local cx, cy = GetCursorPosition()
  local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
  if Minimap.db and Minimap.db.minimap then Minimap.db.minimap.angle = angle end
  Minimap.updatePosition()
end

function Minimap.setShown(show)
  if Minimap.db and Minimap.db.minimap then Minimap.db.minimap.hide = not show end
  if Minimap.button then
    if show then Minimap.button:Show() else Minimap.button:Hide() end
  end
end

-- Flip visibility (used by /pt minimap).
function Minimap.toggle()
  local hidden = Minimap.db and Minimap.db.minimap and Minimap.db.minimap.hide
  Minimap.setShown(hidden and true or false)
end

local function onClick(_, button)
  if button == "RightButton" then
    if Picker.toggle then Picker.toggle() end
  elseif Window.frame then
    if Window.frame:IsShown() then Window.frame:Hide() else Window.frame:Show() end
  end
end

function Minimap.create()
  if Minimap.button then return Minimap.button end

  local b = CreateFrame("Button", "PrayerTimesMinimapButton", _G.Minimap)
  b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")

  -- The logo already carries its own thick gold ring, so it fills the whole
  -- button (centred) and is masked to a circle -- its ring is the border, no
  -- second WoW ring. NOTE: don't combine SetMask with SetTexCoord.
  -- Inset a little so the logo sits in from the button edge (breathing room),
  -- while the logo still fills its own texture so the mask clips cleanly at its
  -- gold ring (padding the texture instead would show the logo's dark corners).
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2)
  icon:SetTexture(LOGO)
  if icon.SetMask then icon:SetMask(CIRCLE_MASK) end
  b.icon = icon

  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(icon); hl:SetColorTexture(1, 1, 1, 0.12)
  if hl.SetMask then hl:SetMask(CIRCLE_MASK) end

  b:SetScript("OnClick", onClick)
  b:SetScript("OnDragStart", function() b:SetScript("OnUpdate", dragUpdate) end)
  b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(b, "ANCHOR_LEFT")
    GameTooltip:AddLine("PrayerTimes")
    GameTooltip:AddLine("Left-click: show/hide window", 1, 1, 1)
    GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  Minimap.button = b
  Minimap.updatePosition()
  if Minimap.db and Minimap.db.minimap and Minimap.db.minimap.hide then b:Hide() end
  return b
end

if PrayerTimesNS then PrayerTimesNS.modules.Minimap = Minimap end
return Minimap
