local scoring = require('scoring')

local function approxEqual(a, b, eps)
  eps = eps or 1e-6
  assert(math.abs(a - b) < eps, string.format('expected %.6f, got %.6f', b, a))
end

local curve = { min = 30, target = 55, max = 65 }

return {
  { name = 'rampScore is 0 at or below min', fn = function()
    approxEqual(scoring.rampScore(30, curve), 0)
    approxEqual(scoring.rampScore(10, curve), 0)
  end },
  { name = 'rampScore is 100 on the plateau between target and max', fn = function()
    approxEqual(scoring.rampScore(55, curve), 100)
    approxEqual(scoring.rampScore(60, curve), 100)
    approxEqual(scoring.rampScore(65, curve), 100)
  end },
  { name = 'rampScore climbs monotonically between min and target', fn = function()
    local prev = -1
    for v = 30, 55, 5 do
      local s = scoring.rampScore(v, curve)
      assert(s >= prev - 1e-9, 'not monotonic at ' .. v)
      prev = s
    end
  end },
  { name = 'rampScore decays past max without cratering to 0', fn = function()
    local s = scoring.rampScore(130, curve) -- exactly 2x max
    assert(s > 30 and s < 50, s) -- ~40 by design (overshootPenalty default 60)
  end },
  { name = 'rampScore never goes negative no matter how extreme the overshoot', fn = function()
    assert(scoring.rampScore(100000, curve) == 0)
  end },
  { name = 'rampScore rejects a curve with min >= target', fn = function()
    local ok = pcall(scoring.rampScore, 50, { min = 60, target = 55, max = 70 })
    assert(not ok)
  end },
  { name = 'combine normalizes weights that do not sum to 100', fn = function()
    local total = scoring.combine({ a = 100, b = 0 }, { a = 1, b = 1 })
    approxEqual(total, 50)
  end },
  { name = 'combine ignores components with no configured weight', fn = function()
    local total = scoring.combine({ a = 100, b = 0, c = 100 }, { a = 1, b = 1 })
    approxEqual(total, 50)
  end },
  { name = 'combine returns 0 when every weight is 0', fn = function()
    approxEqual(scoring.combine({ a = 100 }, { a = 0 }), 0)
  end },
}
