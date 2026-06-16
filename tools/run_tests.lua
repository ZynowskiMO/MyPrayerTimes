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

-- ---- Astronomical: Julian Day vs Meeus textbook values -------------------
local Astro = require("Astronomical")

-- J2000 epoch: 2000 Jan 1, 12:00 UT  ->  JD 2451545.0 (exact)
check("julianDay J2000 == 2451545.0",
  near(Astro.julianDay(2000, 1, 1, 12), 2451545.0, 1e-6))
-- Meeus, Astronomical Algorithms, Example 7.a: 1957 Oct 4.81 -> 2436116.31
check("julianDay 1957-10-04.81 == 2436116.31",
  near(Astro.julianDay(1957, 10, 4, 0.81 * 24), 2436116.31, 1e-6))
-- Meeus 7.b: 1987 Jan 27.0 -> 2446822.5
check("julianDay 1987-01-27.0 == 2446822.5",
  near(Astro.julianDay(1987, 1, 27, 0), 2446822.5, 1e-6))

-- julianCentury at J2000 is 0 by definition.
check("julianCentury(2451545) == 0", near(Astro.julianCentury(2451545.0), 0, 1e-12))

-- Solar-longitude helpers must run and stay normalized to [0, 360).
local Tj2000 = Astro.julianCentury(2451545.0)
local function inRange360(x) return x >= 0 and x < 360 end
check("meanSolarLongitude in [0,360)", inRange360(Astro.meanSolarLongitude(Tj2000)))
check("meanSolarAnomaly in [0,360)", inRange360(Astro.meanSolarAnomaly(Tj2000)))
check("apparentSolarLongitude in [0,360)",
  inRange360(Astro.apparentSolarLongitude(Tj2000, Astro.meanSolarLongitude(Tj2000))))
check("meanSiderealTime in [0,360)", inRange360(Astro.meanSiderealTime(Tj2000)))

-- ---- (fixture comparison wired in a later checkpoint) ---------------------

-- ---- Summary --------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
