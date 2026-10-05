local angle = require('angle')

local function approxEqual(a, b, eps)
  eps = eps or 1e-6
  assert(math.abs(a - b) < eps, string.format('expected %.6f, got %.6f', b, a))
end

return {
  { name = 'normalizeDeg wraps 270 to -90', fn = function()
    approxEqual(angle.normalizeDeg(270), -90)
  end },
  { name = 'normalizeDeg keeps 90 unchanged', fn = function()
    approxEqual(angle.normalizeDeg(90), 90)
  end },
  { name = 'normalizeDeg wraps -270 to 90', fn = function()
    approxEqual(angle.normalizeDeg(-270), 90)
  end },
  { name = 'driftAngleDeg is ~0 when going straight', fn = function()
    local deg, valid = angle.driftAngleDeg({ x = 0, y = 0, z = 30 })
    approxEqual(deg, 0)
    assert(valid == true)
  end },
  { name = 'driftAngleDeg is positive when sliding to one side', fn = function()
    local deg, valid = angle.driftAngleDeg({ x = 10, y = 0, z = 10 })
    assert(valid)
    approxEqual(deg, 45)
  end },
  { name = 'driftAngleDeg flips sign on the opposite slide', fn = function()
    local deg = angle.driftAngleDeg({ x = -10, y = 0, z = 10 })
    approxEqual(deg, -45)
  end },
  { name = 'driftAngleDeg approaches 90 when nearly sideways', fn = function()
    local deg = angle.driftAngleDeg({ x = 20, y = 0, z = 1 })
    assert(deg > 85 and deg < 90, 'expected close to 90, got ' .. tostring(deg))
  end },
  { name = 'driftAngleDeg flags low speed as invalid instead of noisy', fn = function()
    -- speed = sqrt(0.5^2 + 0.1^2) ~= 0.51 m/s, well under the 3 m/s threshold
    local deg, valid = angle.driftAngleDeg({ x = 0.5, y = 0, z = 0.1 }, 3)
    assert(valid == false)
    approxEqual(deg, 0)
  end },
  { name = 'driftAngleDeg flags reversing', fn = function()
    local _, valid, _, isReversing = angle.driftAngleDeg({ x = 0, y = 0, z = -20 })
    assert(valid)
    assert(isReversing == true)
  end },
}
