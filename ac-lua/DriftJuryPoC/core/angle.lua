--[[
  Pure angle math: no `ac.*` calls anywhere in this file. That's deliberate —
  it's what lets these functions run under a plain `lua` interpreter in
  tests/, without Assetto Corsa, CSP or a car anywhere nearby.
]]

local angle = {}

-- atan2 was split into a separate function pre-5.4 and folded into the
-- two-argument form of math.atan from 5.4 onwards. CSP's Lua runtime isn't
-- guaranteed to match the exact host Lua used for tests, so support both.
local function atan2(y, x)
  if math.atan2 then
    return math.atan2(y, x)
  end
  return math.atan(y, x)
end

-- Normalizes an angle in degrees to (-180, 180].
function angle.normalizeDeg(deg)
  local a = deg % 360
  if a > 180 then
    a = a - 360
  end
  return a
end

-- Computes the signed drift/slip angle in degrees from a car's local-space
-- velocity vector (CSP's `car.localVelocity`).
--
-- Axis convention: CSP documents `car.acceleration` as "X for sideways
-- relative to car, Z for forwards/backwards" — localVelocity is in the same
-- local frame, so we assume the same mapping. This is the one assumption in
-- this file that isn't confirmed by a field-level doc comment; sanity-check
-- it in-game by driving in a straight line and confirming the HUD reads ~0°.
--
-- 0 deg  = travelling exactly where the car is pointed (no slide)
-- +deg   = sliding towards the car's right
-- -deg   = sliding towards the car's left
--
-- Below `minSpeedMs`, the direction of travel is dominated by numerical
-- noise rather than the car's actual motion (this matters most while
-- stationary or crawling out of the pits), so we report the sample as
-- invalid instead of returning a wild atan2 result.
function angle.driftAngleDeg(localVelocity, minSpeedMs)
  minSpeedMs = minSpeedMs or 3 -- ~10.8 km/h
  local vx, vz = localVelocity.x, localVelocity.z
  local speed = math.sqrt(vx * vx + vz * vz)
  if speed < minSpeedMs then
    return 0, false, speed, false
  end
  local deg = math.deg(atan2(vx, vz))
  local isReversing = vz < 0
  return deg, true, speed, isReversing
end

return angle
