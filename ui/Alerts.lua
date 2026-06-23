-- Alerts.lua
-- Notification presentation (WoW-side): a built-in sound + a small dismissable
-- pop-up (prayer icon + message + an X to close) + a chat line. The message
-- text is built by a pure helper (messageFor) so it is runner-testable; only
-- show()/the pop-up touch WoW globals, which the mock stubs.

local Theme = require("Theme")
local Icons = require("Icons")

local LABELS = {
  fajr = "Fajr", dhuhr = "Dhuhr", asr = "Asr", maghrib = "Maghrib", isha = "Isha",
}

-- Wowhead FileDataID for the alert chime; played on the Master channel so it
-- is audible regardless of the player's SFX volume. Swap this id to retune.
local ALERT_SOUND_FILE = 561542

local Alerts = {}

-- Pure: event -> display string.
function Alerts.messageFor(ev)
  local name = LABELS[ev.prayer] or ev.prayer
  if ev.type == "before" then
    return string.format("%s in %d min", name, ev.minutesUntil or 0)
  end
  return name .. " - it's time"
end

-- Build (once) the dismissable pop-up. A single reusable frame: each alert
-- updates its text/icon and re-shows it, so notices never stack. Movable; the
-- X button hides it. Themed via Theme so it follows the light/dark palette.
local function ensurePopup()
  if Alerts.popup then return Alerts.popup end

  local f = CreateFrame("Frame", "MyPrayerTimesAlert", UIParent)
  f:SetSize(300, 80)
  f:SetPoint("TOP", UIParent, "TOP", 0, -180)
  f:SetFrameStrata("HIGH")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  -- Border + body (body on the BORDER layer so the cream/charcoal fill always
  -- draws over the outline -- the deterministic fix used across the addon).
  local border = f:CreateTexture(nil, "BACKGROUND"); border:SetAllPoints(); Theme.tex(border, "winBorder")
  local bg = f:CreateTexture(nil, "BORDER")
  bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1); Theme.tex(bg, "winBg")
  local accent = f:CreateTexture(nil, "ARTWORK")
  accent:SetPoint("TOPLEFT", 1, -1); accent:SetPoint("TOPRIGHT", -1, -1); accent:SetHeight(3)
  Theme.tex(accent, "gold")

  -- Brand crest straddling the top edge (replaces a text title); on its own
  -- frame above the body so it always draws on top.
  local crestHolder = CreateFrame("Frame", nil, f)
  crestHolder:SetFrameLevel(f:GetFrameLevel() + 5)
  crestHolder:SetSize(90, 90)
  crestHolder:SetPoint("CENTER", f, "TOP", 0, 0) -- centred on the top edge
  local crest = crestHolder:CreateTexture(nil, "OVERLAY")
  crest:SetAllPoints()
  crest:SetTexture("Interface\\AddOns\\MyPrayerTimes\\Media\\logo.tga")

  -- Message centred in the lower part of the box, with the prayer icon to its
  -- left so the icon+text pair reads as one centred group (the +12 shift offsets
  -- the icon's half-width so the group, not just the text, is centred).
  f.msg = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.msg:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
  f.msg:SetPoint("CENTER", f, "CENTER", 12, -16)
  f.msg:SetJustifyH("CENTER"); Theme.txt(f.msg, "text")
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(16, 16); f.icon:SetPoint("RIGHT", f.msg, "LEFT", -8, 0)

  -- X close button (Lucide "x", brightening on hover).
  local close = CreateFrame("Button", nil, f)
  close:SetSize(20, 20); close:SetPoint("TOPRIGHT", -6, -6)
  local cx = close:CreateTexture(nil, "ARTWORK"); cx:SetAllPoints()
  Icons.setUI(cx, "x", unpack(Theme.color("muted")))
  close:SetScript("OnEnter", function() Icons.setUI(cx, "x", unpack(Theme.color("text"))) end)
  close:SetScript("OnLeave", function() Icons.setUI(cx, "x", unpack(Theme.color("muted"))) end)
  close:SetScript("OnClick", function() f:Hide() end)

  f:Hide()
  Alerts.popup = f
  return f
end

-- WoW-side: play sound (unless muted), show the pop-up, print chat.
function Alerts.show(text, settings, iconKey)
  Alerts.lastMessage = text
  Alerts.showCount = (Alerts.showCount or 0) + 1
  if not settings or settings.sound ~= false then
    PlaySoundFile(ALERT_SOUND_FILE, "Master")
  end
  local f = ensurePopup()
  f.msg:SetText(text)
  if iconKey then
    f.icon:Show(); Icons.apply(f.icon, iconKey, false)
  else
    f.icon:Hide()
  end
  f:Show()
  print("|cff33ff99MyPrayerTimes|r: " .. text)
end

function Alerts.fire(ev, settings)
  Alerts.show(Alerts.messageFor(ev), settings, ev.prayer)
end

function Alerts.test(settings)
  Alerts.show("Maghrib in 10 min (test)", settings or {}, "maghrib")
end

if PrayerTimesNS then PrayerTimesNS.modules.Alerts = Alerts end
return Alerts
