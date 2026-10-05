--[[
  Pure scoring math — continuous curves, not thresholds (§41 of the
  blueprint: "20 deg -> 20%, 35 deg -> 60%, ... " rather than a hard
  angle > 45 cutoff). No `ac.*` calls here either.
]]

local scoring = {}

-- Clamps t to [0,1] then eases it with the classic smoothstep
-- (3t^2 - 2t^3): flat start, flat finish, no sudden inflection in between.
-- Used so a value crawling past `min` doesn't feel like it "suddenly
-- started counting".
local function smoothstep(t)
  t = math.max(0, math.min(1, t))
  return t * t * (3 - 2 * t)
end
scoring.smoothstep = smoothstep

-- Continuous 0-100 score for a measured value against a curve of
-- {min, target, max, overshootPenalty?}:
--
--   value <= min            -> 0
--   min < value < target    -> smoothstep ramp, 0..100
--   target <= value <= max  -> 100 (the "did it right" plateau)
--   value > max             -> decays past 100, but never falls off a
--                              cliff straight to 0 (an angle a little too
--                              hot still reads as a good run, just not a
--                              perfect one)
--
-- `overshootPenalty` (default 60) controls how fast the decay above `max`
-- is: at value = 2*max the score is roughly (100 - overshootPenalty).
function scoring.rampScore(value, curve)
  local min, target, max = curve.min, curve.target, curve.max
  assert(min and target and max, 'curve needs min, target and max')
  assert(min < target and target <= max, 'curve must satisfy min < target <= max')

  if value <= min then
    return 0
  end
  if value < target then
    return smoothstep((value - min) / (target - min)) * 100
  end
  if value <= max then
    return 100
  end

  local overshootPenalty = curve.overshootPenalty or 60
  local over = (value - max) / max
  return math.max(0, 100 - over * overshootPenalty)
end

-- Weighted average of named component scores (each already on a 0-100
-- scale). Weights are normalized here so a layout config can express
-- relative importance (e.g. { line = 40, angle = 25, speed = 15, style = 20 })
-- without having to make them sum to exactly 100 itself.
function scoring.combine(components, weights)
  local totalWeight, sum = 0, 0
  for name, value in pairs(components) do
    local w = weights[name] or 0
    sum = sum + value * w
    totalWeight = totalWeight + w
  end
  if totalWeight <= 0 then
    return 0
  end
  return sum / totalWeight
end

return scoring
