-- run_tests.lua
-- LuaJIT (Lua 5.1) test runner for the PrayerTimes engine.
-- Run from the repository root:   luajit tools/run_tests.lua
--
-- Reports PASS/FAIL per check and exits non-zero on any failure, so this is
-- the one command that decides whether a checkpoint is green. As the engine
-- grows, later checkpoints add the fixture comparison (Rotterdam vs adhan-js)
-- below; for now it exercises MathUtils.

package.path = "engine/?.lua;" .. package.path

local passed, failed = 0, 0

local function check(name, cond)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("  FAIL: " .. name)
  end
end

-- Approximate equality for floating-point results.
local function near(a, b, eps)
  return math.abs(a - b) <= (eps or 1e-9)
end

-- ---- MathUtils ------------------------------------------------------------
local Math = require("MathUtils")

check("degreesToRadians(180) == pi", near(Math.degreesToRadians(180), math.pi))
check("radiansToDegrees(pi) == 180", near(Math.radiansToDegrees(math.pi), 180))
check("normalizeToScale(370,360) == 10", near(Math.normalizeToScale(370, 360), 10))
check("normalizeToScale(-10,360) == 350", near(Math.normalizeToScale(-10, 360), 350))
check("unwindAngle(720) == 0", near(Math.unwindAngle(720), 0))
check("unwindAngle(-90) == 270", near(Math.unwindAngle(-90), 270))
check("quadrantShiftAngle(90) == 90", near(Math.quadrantShiftAngle(90), 90))
check("quadrantShiftAngle(200) == -160", near(Math.quadrantShiftAngle(200), -160))
check("quadrantShiftAngle(-200) == 160", near(Math.quadrantShiftAngle(-200), 160))
check("quadrantShiftAngle(540) == -180", near(Math.quadrantShiftAngle(540), -180))

-- ---- (fixture comparison wired in a later checkpoint) ---------------------

-- ---- Summary --------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
