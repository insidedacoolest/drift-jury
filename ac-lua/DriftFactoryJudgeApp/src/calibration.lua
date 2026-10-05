local U = require('src.util')
local M = {}
M.__index = M

local function statistics(values)
  table.sort(values)
  if #values == 0 then return { minimum = 0, average = 0, median = 0, percentile75 = 0, maximum = 0 } end
  local total = 0
  for _, value in ipairs(values) do total = total + value end
  local function percentile(fraction)
    if #values == 1 then return values[1] end
    local position = fraction * (#values - 1)
    local lower, upper = math.floor(position) + 1, math.ceil(position) + 1
    return lower == upper and values[lower] or U.lerp(values[lower], values[upper], position - math.floor(position))
  end
  return {
    minimum = values[1], average = total / #values, median = percentile(0.5),
    percentile75 = percentile(0.75), maximum = values[#values]
  }
end

function M.new()
  return setmetatable({ active = false, attempts = {}, validRuns = {}, recommendation = nil }, M)
end

function M:start()
  self.active, self.attempts, self.validRuns, self.recommendation = true, {}, {}, nil
end

function M:cancel()
  self.active, self.attempts, self.validRuns, self.recommendation = false, {}, {}, nil
end

function M:add(valid, reason, score, analysis)
  local run = {
    attemptNumber = #self.attempts + 1,
    validRunNumber = valid and (#self.validRuns + 1) or 0,
    valid = valid,
    reason = valid and 'Válida' or reason,
    score = score,
    analysis = analysis
  }
  self.attempts[#self.attempts + 1] = run
  if valid then self.validRuns[#self.validRuns + 1] = run end
  if #self.validRuns >= 5 then self.recommendation = self:createRecommendation() end
  return run
end

function M:createRecommendation()
  local best = U.copy(self.validRuns)
  table.sort(best, function(a, b) return a.score.score > b.score.score end)
  while #best > 3 do table.remove(best) end
  local speeds, angles = {}, {}
  for _, run in ipairs(best) do
    for _, value in ipairs(run.analysis.judgedSpeeds) do speeds[#speeds + 1] = value end
    for _, value in ipairs(run.analysis.judgedAngles) do angles[#angles + 1] = value end
  end
  local speedStats, angleStats = statistics(speeds), statistics(angles)
  local targetSpeed = math.ceil(math.max(0, speedStats.average) / 5) * 5
  local targetAngle = math.max(20, U.round(angleStats.average / 5) * 5)
  local minimumAngle = U.clamp(U.round(targetAngle * 0.36 / 5) * 5, 10, targetAngle - 10)
  local styleMinimum = math.max(10, U.round(targetAngle * 0.27 / 5) * 5)
  local styleFull = U.clamp(U.round(targetAngle * 0.55 / 5) * 5, styleMinimum + 5, targetAngle)
  return {
    targetSpeedKmh = targetSpeed,
    targetAngleDeg = targetAngle,
    minimumAngleDeg = minimumAngle,
    styleMinimumDriftAngleDeg = styleMinimum,
    styleFullDriftAngleDeg = styleFull,
    bestRuns = best
  }
end

return M
