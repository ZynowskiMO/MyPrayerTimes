-- Alerts.lua
-- Notification presentation (WoW-side): a built-in sound + a center-screen
-- RaidNotice alert + a chat line. The message text is built by a pure helper
-- (messageFor) so it is runner-testable; only show() touches WoW globals,
-- which the mock stubs.

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

-- WoW-side: play sound (unless muted), show center-screen alert, print chat.
function Alerts.show(text, settings)
  if not settings or settings.sound ~= false then
    PlaySoundFile(ALERT_SOUND_FILE, "Master")
  end
  if RaidNotice_AddMessage and RaidWarningFrame then
    local color = ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 1, b = 1 }
    RaidNotice_AddMessage(RaidWarningFrame, text, color)
  end
  print("|cff33ff99PrayerTimes|r: " .. text)
end

function Alerts.fire(ev, settings)
  Alerts.show(Alerts.messageFor(ev), settings)
end

function Alerts.test(settings)
  Alerts.show("test alert - this is how a prayer notification looks", settings or {})
end

if PrayerTimesNS then PrayerTimesNS.modules.Alerts = Alerts end
return Alerts
