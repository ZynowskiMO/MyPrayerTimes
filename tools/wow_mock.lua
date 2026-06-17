-- wow_mock.lua
-- Minimal hand-rolled WoW API stubs for the luajit test runner -- only the
-- functions our UI actually calls, not a full emulator. Lets ui/Window.lua
-- (2c-2+) load and be exercised outside WoW. WoW-only files (bootstrap.lua,
-- core/Main.lua) are NOT loaded by the runner, so they may use WoW globals
-- freely. Frames/fontstrings record just enough state for tests to assert.

local M = {}
local nowEpoch = 0

local function makeFontString()
  local fs = { _text = "", _shown = true, _points = {} }
  function fs:SetText(t) self._text = t end
  function fs:GetText() return self._text end
  function fs:SetPoint(...) self._points[#self._points + 1] = { ... } end
  function fs:SetTextColor() end
  function fs:SetFont() end
  function fs:SetJustifyH() end
  function fs:Show() self._shown = true end
  function fs:Hide() self._shown = false end
  function fs:IsShown() return self._shown end
  return fs
end

local function makeTexture()
  local tx = { _shown = true }
  function tx:SetAllPoints() end
  function tx:SetColorTexture() end
  function tx:SetTexture() end
  function tx:Show() self._shown = true end
  function tx:Hide() self._shown = false end
  return tx
end

local function makeFrame()
  local f = { _shown = true, _scripts = {}, _movable = false, _mouse = false, _points = {} }
  function f:SetPoint(...) self._points[#self._points + 1] = { ... } end
  function f:ClearAllPoints() self._points = {} end
  function f:GetPoint(i) local p = self._points[i or 1]; if p then return unpack(p) end end
  function f:SetSize(w, h) self._w, self._h = w, h end
  function f:SetWidth(w) self._w = w end
  function f:SetHeight(h) self._h = h end
  function f:Show() self._shown = true end
  function f:Hide() self._shown = false end
  function f:IsShown() return self._shown end
  function f:SetShown(b) self._shown = b and true or false end
  function f:SetMovable(b) self._movable = b end
  function f:IsMovable() return self._movable end
  function f:SetClampedToScreen() end
  function f:SetUserPlaced() end
  function f:EnableMouse(b) self._mouse = b end
  function f:IsMouseEnabled() return self._mouse end
  function f:RegisterForDrag() end
  function f:RegisterEvent() end
  function f:UnregisterEvent() end
  function f:SetScript(name, fn) self._scripts[name] = fn end
  function f:GetScript(name) return self._scripts[name] end
  function f:HookScript(name, fn) self._scripts[name] = fn end
  function f:StartMoving() self._moving = true end
  function f:StopMovingOrSizing() self._moving = false end
  function f:SetFrameStrata() end
  function f:SetBackdrop() end
  function f:SetBackdropColor() end
  function f:CreateFontString() return makeFontString() end
  function f:CreateTexture() return makeTexture() end
  return f
end

function M.install()
  _G.CreateFrame = function() return makeFrame() end
  _G.UIParent = makeFrame()
  _G.C_Timer = {
    _afters = {}, _tickers = {},
    After = function(delay, fn) table.insert(_G.C_Timer._afters, { delay = delay, fn = fn }) end,
    NewTicker = function(interval, fn)
      local t = { interval = interval, fn = fn, _cancelled = false }
      function t:Cancel() self._cancelled = true end
      table.insert(_G.C_Timer._tickers, t)
      return t
    end,
  }
  _G.GetServerTime = function() return nowEpoch end
  _G.time = function() return nowEpoch end
  _G.GameFontNormal = {}
  _G.GameFontHighlight = {}
end

function M.setNow(epoch) nowEpoch = epoch end
function M.makeFrame() return makeFrame() end

return M
