local U = require('src.util')
local G = require('src.geometry')
local M = {}

local function average(items, selector)
  if #items == 0 then return 0 end
  local total = 0
  for _, item in ipairs(items) do total = total + selector(item) end
  return total / #items
end

local function interpolateVector(a, b, t)
  return {
    x = U.lerp(a.x, b.x, t),
    y = U.lerp(a.y or 0, b.y or 0, t),
    z = U.lerp(a.z, b.z, t)
  }
end

local function interpolate(a, b, t, targetProgress, pathLength, layout)
  local position = interpolateVector(a.position, b.position, t)
  local projected = G.getProgress(layout.pathWaypoints, position)
  local signedAngle = a.signedAngleDeg + G.signedAngleDelta(a.signedAngleDeg, b.signedAngleDeg) * t
  return {
    timeMilliseconds = U.round(U.lerp(a.timeMilliseconds, b.timeMilliseconds, t)),
    position = position,
    look = interpolateVector(a.look, b.look, t),
    velocity = interpolateVector(a.velocity, b.velocity, t),
    steerAngle = U.round(U.clamp(U.lerp(a.steerAngle, b.steerAngle, t), 0, 255)),
    gas = U.round(U.clamp(U.lerp(a.gas, b.gas, t), 0, 255)),
    signedAngleDeg = signedAngle,
    angleDeg = math.abs(signedAngle),
    speedKmh = U.lerp(a.speedKmh, b.speedKmh, t),
    progress = {
      meters = targetProgress,
      distanceToPathMeters = projected.distanceToPathMeters,
      normalized = pathLength <= 0 and 0 or U.clamp(targetProgress / pathLength, 0, 1),
      segmentIndex = projected.segmentIndex
    },
    frontBumper = interpolateVector(a.frontBumper, b.frontBumper, t),
    rearBumper = interpolateVector(a.rearBumper, b.rearBumper, t),
    rearWheelLeft = interpolateVector(a.rearWheelLeft, b.rearWheelLeft, t),
    rearWheelRight = interpolateVector(a.rearWheelRight, b.rearWheelRight, t),
    rearWheelLeftExact = a.rearWheelLeftExact and b.rearWheelLeftExact,
    rearWheelRightExact = a.rearWheelRightExact and b.rearWheelRightExact,
    exactWheelCoverage = (a.rearWheelLeftExact and b.rearWheelLeftExact and 0.5 or 0)
      + (a.rearWheelRightExact and b.rearWheelRightExact and 0.5 or 0)
  }
end

function M.resampleByProgress(samples, layout, binMeters)
  if #samples == 0 then return {} end
  binMeters = math.max(0.1, binMeters)
  local ordered = U.copy(samples)
  table.sort(ordered, function(a, b) return a.timeMilliseconds < b.timeMilliseconds end)
  local monotonic = {}
  for _, sample in ipairs(ordered) do
    if #monotonic == 0 or sample.progress.meters >= monotonic[#monotonic].progress.meters then
      monotonic[#monotonic + 1] = sample
    end
  end
  if #monotonic < 2 then return monotonic end

  local firstProgress = monotonic[1].progress.meters
  local lastProgress = firstProgress
  for _, sample in ipairs(monotonic) do lastProgress = math.max(lastProgress, sample.progress.meters) end
  local firstTarget = math.ceil(firstProgress / binMeters) * binMeters
  local lastTarget = math.floor(lastProgress / binMeters) * binMeters
  if lastTarget < firstTarget then return { monotonic[1] } end

  local result, upperIndex = {}, 2
  local pathLength = G.pathLength(layout.pathWaypoints)
  local target = firstTarget
  while target <= lastTarget + 0.001 do
    while upperIndex < #monotonic and monotonic[upperIndex].progress.meters < target do
      upperIndex = upperIndex + 1
    end
    local lower, upper = monotonic[math.max(1, upperIndex - 1)], monotonic[upperIndex]
    local span = upper.progress.meters - lower.progress.meters
    local t = span <= 0.001 and 0 or U.clamp((target - lower.progress.meters) / span, 0, 1)
    result[#result + 1] = interpolate(lower, upper, t, target, pathLength, layout)
    target = target + binMeters
  end
  return result
end

local function courseBins(bins, layout, config)
  local pathLength = G.pathLength(layout.pathWaypoints)
  local startAt = config.startExclusionMeters
  local endAt = math.max(startAt, pathLength - config.finishExclusionMeters)
  local result = {}
  for _, sample in ipairs(bins) do
    if sample.progress.meters >= startAt and sample.progress.meters <= endAt then result[#result + 1] = sample end
  end
  return #result > 0 and result or bins
end

local function zoneSector(zone, layout, binMeters)
  if #zone.points == 0 then return { startAt = 0, endAt = 0 } end
  local startAt, endAt = math.huge, -math.huge
  for _, point in ipairs(zone.points) do
    local meters = G.getProgress(layout.pathWaypoints, point).meters
    startAt, endAt = math.min(startAt, meters), math.max(endAt, meters)
  end
  local minimumSpan = math.max(2, binMeters * 2)
  if endAt - startAt < minimumSpan then
    local center = (startAt + endAt) * 0.5
    startAt, endAt = center - minimumSpan * 0.5, center + minimumSpan * 0.5
  end
  return { startAt = startAt, endAt = endAt }
end

local function featureSectors(layout, config)
  local pathLength = G.pathLength(layout.pathWaypoints)
  local sectors = {}
  for _, zone in ipairs(layout.outerZones) do
    local sector = zoneSector(zone, layout, config.progressBinMeters)
    sectors[#sectors + 1] = {
      startAt = math.max(0, sector.startAt - config.judgedFeatureWindowMeters),
      endAt = math.min(pathLength, sector.endAt + config.judgedFeatureWindowMeters)
    }
  end
  for _, clip in ipairs(layout.innerClips) do
    local center = G.getProgress(layout.pathWaypoints, clip.position).meters
    sectors[#sectors + 1] = {
      startAt = math.max(0, center - config.judgedFeatureWindowMeters),
      endAt = math.min(pathLength, center + config.judgedFeatureWindowMeters)
    }
  end
  table.sort(sectors, function(a, b) return a.startAt < b.startAt end)
  local merged = {}
  for _, sector in ipairs(sectors) do
    local previous = merged[#merged]
    if previous and sector.startAt <= previous.endAt then
      previous.endAt = math.max(previous.endAt, sector.endAt)
    else
      merged[#merged + 1] = sector
    end
  end
  return merged
end

local function activeDriftBins(course, layout, config)
  local sectors = featureSectors(layout, config)
  local judged = {}
  for _, sample in ipairs(course) do
    local include = #sectors == 0
    for _, sector in ipairs(sectors) do
      if sample.progress.meters >= sector.startAt and sample.progress.meters <= sector.endAt then
        include = true
        break
      end
    end
    if include then judged[#judged + 1] = sample end
  end
  if #judged == 0 then judged = U.copy(course) end
  if #judged < 2 or config.transitionGraceMeters <= 0 then return judged end

  local transitions, previous = {}, nil
  for _, sample in ipairs(judged) do
    if math.abs(sample.signedAngleDeg) >= config.minimumAngleDeg * 0.5 then
      if previous and ((previous.signedAngleDeg < 0) ~= (sample.signedAngleDeg < 0)) then
        transitions[#transitions + 1] = (previous.progress.meters + sample.progress.meters) * 0.5
      end
      previous = sample
    end
  end

  local active = {}
  for _, sample in ipairs(judged) do
    local include = true
    for _, transition in ipairs(transitions) do
      if math.abs(sample.progress.meters - transition) <= config.transitionGraceMeters then
        include = false
        break
      end
    end
    if include then active[#active + 1] = sample end
  end
  return #active > 0 and active or judged
end

function M.pathCorridorQuality(distanceToRoute, halfWidth, tolerance)
  local outside = math.max(0, distanceToRoute - math.max(0, halfWidth))
  if outside <= 0 then return 1 end
  return 1 - U.clamp(outside / math.max(0.001, tolerance), 0, 1)
end

function M.zonePointQuality(signedDistance, config)
  if signedDistance >= config.outerZoneFullDepthMeters then return 1 end
  if signedDistance >= 0 then
    local depth = signedDistance / config.outerZoneFullDepthMeters
    return config.outerZoneBoundaryQuality + (1 - config.outerZoneBoundaryQuality) * depth
  end
  local outside = -signedDistance
  if outside >= config.outerZoneOutsideToleranceMeters then return 0 end
  return config.outerZoneBoundaryQuality * (1 - outside / config.outerZoneOutsideToleranceMeters)
end

local function pathQuality(bins, layout, config)
  return average(bins, function(sample)
    return M.pathCorridorQuality(
      sample.progress.distanceToPathMeters,
      layout.pathCorridorHalfWidthMeters,
      config.pathCorridorOutsideToleranceMeters)
  end)
end

local function outerZoneQuality(bins, layout, config)
  if #layout.outerZones == 0 then return { average = 1, items = {} } end
  local items = {}
  for _, zone in ipairs(layout.outerZones) do
    local sector = zoneSector(zone, layout, config.progressBinMeters)
    local zoneBins = {}
    for _, sample in ipairs(bins) do
      local left = G.getProgress(layout.pathWaypoints, sample.rearWheelLeft).meters
      local right = G.getProgress(layout.pathWaypoints, sample.rearWheelRight).meters
      if (left >= sector.startAt and left <= sector.endAt)
        or (right >= sector.startAt and right <= sector.endAt) then
        zoneBins[#zoneBins + 1] = sample
      end
    end
    if #zoneBins == 0 then
      items[#items + 1] = 0
    else
      local qualities, entered = {}, false
      for _, sample in ipairs(zoneBins) do
        local left = G.signedDistanceToPolygon(sample.rearWheelLeft, zone.points)
        local right = G.signedDistanceToPolygon(sample.rearWheelRight, zone.points)
        local closest = math.max(left, right)
        entered = entered or closest >= 0
        qualities[#qualities + 1] = M.zonePointQuality(closest, config)
      end
      if not entered then
        items[#items + 1] = 0
      else
        local window = math.min(config.outerZoneBestAdjacentBins, #qualities)
        local placement = 0
        for startIndex = 1, #qualities - window + 1 do
          local total = 0
          for offset = 0, window - 1 do total = total + qualities[startIndex + offset] end
          placement = math.max(placement, total / window)
        end
        local covered = 0
        for _, quality in ipairs(qualities) do
          if quality >= config.outerZoneCoverageQualityThreshold then covered = covered + 1 end
        end
        local hold = U.clamp(
          (covered / #qualities) / math.max(0.01, config.outerZoneFullHoldCoverage), 0, 1)
        local weight = config.outerZonePlacementWeight + config.outerZoneHoldWeight
        items[#items + 1] = weight <= 0 and placement
          or (placement * config.outerZonePlacementWeight + hold * config.outerZoneHoldWeight) / weight
      end
    end
  end
  local total = 0
  for _, quality in ipairs(items) do total = total + quality end
  return { average = total / #items, items = items }
end

local function qualityFromDistance(distance, perfect, maximum)
  if distance <= perfect then return 1 end
  return 1 - U.clamp((distance - perfect) / math.max(0.001, maximum - perfect), 0, 1)
end

local function innerClipQuality(bins, layout, config)
  if #layout.innerClips == 0 then return { average = 1, items = {} } end
  local items = {}
  for _, clip in ipairs(layout.innerClips) do
    local center = G.getProgress(layout.pathWaypoints, clip.position).meters
    local qualities = {}
    for _, sample in ipairs(bins) do
      local frontProgress = G.getProgress(layout.pathWaypoints, sample.frontBumper).meters
      if math.abs(frontProgress - center) <= config.innerClipWindowMeters then
        local outside = math.max(0, G.distance3(sample.frontBumper, clip.position) - clip.radiusMeters)
        qualities[#qualities + 1] = {
          progress = sample.progress.meters,
          quality = qualityFromDistance(outside, 0, config.innerClipMaxDistanceMeters)
        }
      end
    end
    table.sort(qualities, function(a, b) return a.progress < b.progress end)
    local window = math.min(config.innerClipAdjacentBins, #qualities)
    local best = 0
    if window > 0 then
      for startIndex = 1, #qualities - window + 1 do
        local total = 0
        for offset = 0, window - 1 do total = total + qualities[startIndex + offset].quality end
        best = math.max(best, total / window)
      end
    end
    items[#items + 1] = best
  end
  local total = 0
  for _, quality in ipairs(items) do total = total + quality end
  return { average = total / #items, items = items }
end

-- Line (Drift Masters 1.7): points are spread across the outer zones and
-- inner clips, each an equal share; missing one scores 0 for it. Leaving the
-- drawn route ("off line") takes up to lineOffLineWeight of the line.
local function lineQuality(pathValue, zones, clips, config)
  local total, count = 0, 0
  for _, quality in ipairs(zones.items) do total, count = total + quality, count + 1 end
  for _, quality in ipairs(clips.items) do total, count = total + quality, count + 1 end
  if count == 0 then return pathValue end
  local weight = U.clamp(config.lineOffLineWeight, 0, 1)
  return (total / count) * (1 - weight) + pathValue * weight
end

local function angleQuality(bins, config)
  return average(bins, function(sample)
    return U.clamp(
      (sample.angleDeg - config.minimumAngleDeg)
      / math.max(0.001, config.targetAngleDeg - config.minimumAngleDeg), 0, 1)
  end)
end

local function engagement(bins, config)
  return average(bins, function(sample)
    return U.clamp(
      (sample.angleDeg - config.styleMinimumDriftAngleDeg)
      / math.max(0.001, config.styleFullDriftAngleDeg - config.styleMinimumDriftAngleDeg), 0, 1)
  end)
end

local function normalizedCorrection(delta, deadband, range)
  return U.clamp((delta - deadband) / math.max(0.001, range), 0, 1)
end

local function sign(value) return value < 0 and -1 or 1 end

-- Initiation (5): early (reference: the start exclusion, like the
-- initiation cones), rate to angle (how fast the desired angle is reached)
-- and smooth (no angle given back). A drop out of the drift and a second
-- initiation inside the window is a double initiation.
local function initiationQuality(bins, config)
  local startAt
  for index, sample in ipairs(bins) do
    if sample.angleDeg >= config.minimumAngleDeg then startAt = index break end
  end
  if not startAt then return { combined = 0, early = 0, rate = 0, smooth = 0, double = false, meters = nil } end
  local initiated = bins[startAt]
  local meters, side = initiated.progress.meters, sign(initiated.signedAngleDeg)
  local lateBy = meters - config.startExclusionMeters - config.initiationFullMeters
  local early = 1 - U.clamp(lateBy / math.max(0.001, config.initiationZeroMeters - config.initiationFullMeters), 0, 1)

  local rateAngle = config.targetAngleDeg * config.initiationRateAngleShare
  local reachedAfter, drop, dropped, double = nil, 0, false, false
  for index = startAt, #bins do
    local sample, previous = bins[index], bins[index - 1]
    if sample.progress.meters - meters > config.initiationWindowMeters then break end
    if not reachedAfter and sample.angleDeg >= rateAngle then reachedAfter = sample.progress.meters - meters end
    if sign(sample.signedAngleDeg) == side then
      if previous and index > startAt and sign(previous.signedAngleDeg) == side then
        drop = drop + math.max(0, previous.angleDeg - sample.angleDeg - config.angleChangeDeadbandDeg)
      end
      if sample.angleDeg < config.minimumAngleDeg * 0.5 then dropped = true end
      if dropped and sample.angleDeg >= config.minimumAngleDeg then double = true end
    end
  end
  local rate = reachedAfter and 1 - U.clamp((reachedAfter - config.initiationRateFullMeters)
    / math.max(0.001, config.initiationRateZeroMeters - config.initiationRateFullMeters), 0, 1) or 0
  local smooth = 1 - U.clamp(drop / math.max(0.001, config.initiationSmoothDropRangeDeg), 0, 1)
  local combined = (early + rate + smooth) / 3
  if double then combined = combined * config.doubleInitiationFactor end
  return { combined = combined, early = early, rate = rate, smooth = smooth, double = double, meters = meters }
end

-- Transitions (fluidity): each switch from one drift direction to the other,
-- scored on how quickly it rotates (meters spent below the minimum angle)
-- and on going from high angle to high angle (lock to lock).
local function transitionQuality(bins, config)
  local items, last = {}, nil
  for index, sample in ipairs(bins) do
    if sample.angleDeg >= config.minimumAngleDeg then
      if last and sign(bins[last].signedAngleDeg) ~= sign(sample.signedAngleDeg) then
        local fromMeters, toMeters = bins[last].progress.meters, sample.progress.meters
        local gap = toMeters - fromMeters
        local quick = 1 - U.clamp((gap - config.transitionFullMeters)
          / math.max(0.001, config.transitionZeroMeters - config.transitionFullMeters), 0, 1)
        local before, after = 0, 0
        for _, other in ipairs(bins) do
          local at = other.progress.meters
          if at <= fromMeters and fromMeters - at <= config.transitionLockWindowMeters then before = math.max(before, other.angleDeg) end
          if at >= toMeters and at - toMeters <= config.transitionLockWindowMeters then after = math.max(after, other.angleDeg) end
        end
        local lock = U.clamp((math.min(before, after) - config.minimumAngleDeg)
          / math.max(0.001, config.targetAngleDeg - config.minimumAngleDeg), 0, 1)
        items[#items + 1] = (quick + lock) * 0.5
      end
      last = index
    end
  end
  if #items == 0 then return nil end
  return average(items, function(item) return item end)
end

-- Fluidity (10): the car settled and flowing (few abrupt steering, throttle
-- and angle corrections), plus smooth lock-to-lock transitions where the
-- course has them. Commitment (5): pace, keeping it (no big speed drops)
-- and consistent throttle.
local function styleQuality(active, course, config)
  local pace = average(active, function(sample)
    return U.clamp(sample.speedKmh / config.targetSpeedKmh, 0, 1)
  end)
  local settled = 1
  if #active >= 2 then
    settled = 0
    for i = 2, #active do
      local steer = normalizedCorrection(
        math.abs(active[i].steerAngle - active[i - 1].steerAngle),
        config.steeringDeadband, config.steeringCorrectionRange)
      local throttle = normalizedCorrection(
        math.abs(active[i].gas - active[i - 1].gas),
        config.throttleDeadband, config.throttleCorrectionRange)
      local angle = normalizedCorrection(
        math.abs(G.signedAngleDelta(active[i - 1].signedAngleDeg, active[i].signedAngleDeg)),
        config.angleChangeDeadbandDeg, config.angleCorrectionRangeDeg)
      settled = settled + 1 - U.clamp(steer * 0.40 + throttle * 0.25 + angle * 0.35, 0, 1)
    end
    settled = settled / (#active - 1)
  end
  local transitions = transitionQuality(course, config)
  local fluidity = transitions == nil and settled
    or settled * (1 - config.fluidityTransitionWeight) + transitions * config.fluidityTransitionWeight

  local speeds = {}
  for _, sample in ipairs(active) do speeds[#speeds + 1] = sample.speedKmh end
  table.sort(speeds)
  local consistency = 1
  if #speeds > 0 then
    local mean = average(active, function(sample) return sample.speedKmh end)
    local low = speeds[math.max(1, math.floor(#speeds * 0.10))]
    consistency = 1 - U.clamp((mean - low) / math.max(1, mean) / math.max(0.001, config.commitmentDropRange), 0, 1)
  end
  local throttleOn = average(active, function(sample)
    return sample.gas >= config.commitmentThrottleOn * 255 and 1 or 0
  end)
  local throttle = U.clamp(throttleOn / math.max(0.001, config.commitmentFullThrottleShare), 0, 1)
  local weights = config.commitmentPaceWeight + config.commitmentConsistencyWeight + config.commitmentThrottleWeight
  local commitment = weights <= 0 and pace or (pace * config.commitmentPaceWeight
    + consistency * config.commitmentConsistencyWeight + throttle * config.commitmentThrottleWeight) / weights
  return {
    speed = pace, fluidity = fluidity, settled = settled, transitions = transitions,
    commitment = commitment, consistency = consistency, throttle = throttle
  }
end

local function percentageItems(items)
  local result = {}
  for _, item in ipairs(items) do result[#result + 1] = item * 100 end
  return result
end

function M.zero(reason)
  return {
    score = 0, line = 0, angle = 0, styleSpeed = 0, penalties = 0,
    initiation = 0, fluidity = 0, commitment = 0, initiationQuality = 0, initiationMeters = nil,
    doubleInitiation = false,
    averageAngle = 0, averageSpeed = 0, maxAngle = 0,
    targetAngle = 0, targetSpeed = 0, pathQuality = 0, zoneQuality = 0,
    clipQuality = 0, zoneQualities = {}, clipQualities = {},
    angleQuality = 0, speedQuality = 0, fluidityQuality = 0,
    exactWheelCoverage = 0, valid = false, reason = reason or 'Inválida'
  }
end

function M.scoreLead(samples, layout, config, penalties, invalid, reason)
  penalties = penalties or 0
  if invalid or #samples == 0 then return M.zero(reason) end
  local bins = M.resampleByProgress(samples, layout, config.progressBinMeters)
  if #bins == 0 then return M.zero('Sem amostras do percurso') end
  local course = courseBins(bins, layout, config)
  local active = activeDriftBins(course, layout, config)
  local path = pathQuality(course, layout, config)
  local zones = outerZoneQuality(bins, layout, config)
  local clips = innerClipQuality(bins, layout, config)
  local lineValue = lineQuality(path, zones, clips, config)
  local angleValue = angleQuality(active, config)
  local style = styleQuality(active, course, config)
  local engaged = engagement(active, config)
  local start = initiationQuality(bins, config)
  local line = config.leadLinePoints * lineValue
  local angle = config.leadAnglePoints * angleValue
  -- Style splits into its three parts; fluidity and commitment only count
  -- while actually drifting (engagement), initiation measures the drift's start.
  local initiation = config.styleInitiationPoints * start.combined
  local fluidity = config.styleFluidityPoints * style.fluidity * engaged
  local commitment = config.styleCommitmentPoints * style.commitment * engaged
  local styleParts = config.styleInitiationPoints + config.styleFluidityPoints + config.styleCommitmentPoints
  local styleSpeed = styleParts <= 0 and 0
    or (initiation + fluidity + commitment) * config.leadStyleSpeedPoints / styleParts
  local maxAngle = 0
  for _, sample in ipairs(bins) do maxAngle = math.max(maxAngle, sample.angleDeg) end
  return {
    score = U.clamp(line + angle + styleSpeed - penalties, 0, 100),
    line = line,
    angle = angle,
    styleSpeed = styleSpeed,
    initiation = initiation,
    fluidity = fluidity,
    commitment = commitment,
    initiationQuality = start.combined * 100,
    initiationMeters = start.meters,
    doubleInitiation = start.double,
    penalties = penalties,
    averageAngle = average(active, function(sample) return sample.angleDeg end),
    averageSpeed = average(active, function(sample) return sample.speedKmh end),
    maxAngle = maxAngle,
    targetAngle = config.targetAngleDeg,
    targetSpeed = config.targetSpeedKmh,
    pathQuality = path * 100,
    zoneQuality = zones.average * 100,
    clipQuality = clips.average * 100,
    zoneQualities = percentageItems(zones.items),
    clipQualities = percentageItems(clips.items),
    angleQuality = angleValue * 100,
    speedQuality = style.speed * engaged * 100,
    fluidityQuality = style.fluidity * engaged * 100,
    exactWheelCoverage = average(bins, function(sample) return sample.exactWheelCoverage or 0 end) * 100,
    valid = true,
    reason = 'Válida'
  }
end

local function statistics(values)
  table.sort(values)
  if #values == 0 then return { minimum = 0, average = 0, median = 0, percentile75 = 0, maximum = 0 } end
  local total = 0
  for _, value in ipairs(values) do total = total + value end
  local function percentile(fraction)
    if #values == 1 then return values[1] end
    local position = U.clamp(fraction, 0, 1) * (#values - 1)
    local lower = math.floor(position) + 1
    local upper = math.ceil(position) + 1
    return lower == upper and values[lower] or U.lerp(values[lower], values[upper], position - math.floor(position))
  end
  return {
    minimum = values[1],
    average = total / #values,
    median = percentile(0.5),
    percentile75 = percentile(0.75),
    maximum = values[#values]
  }
end

function M.analyzeRun(samples, layout, config)
  local bins = M.resampleByProgress(samples, layout, config.progressBinMeters)
  local course = courseBins(bins, layout, config)
  local active = activeDriftBins(course, layout, config)
  local courseSpeeds, courseAngles, speeds, angles = {}, {}, {}, {}
  for _, sample in ipairs(course) do
    courseSpeeds[#courseSpeeds + 1] = sample.speedKmh
    courseAngles[#courseAngles + 1] = sample.angleDeg
  end
  for _, sample in ipairs(active) do
    speeds[#speeds + 1] = sample.speedKmh
    angles[#angles + 1] = sample.angleDeg
  end
  return {
    durationMilliseconds = #samples < 2 and 0
      or math.max(0, samples[#samples].timeMilliseconds - samples[1].timeMilliseconds),
    rawSampleCount = #samples,
    courseSampleCount = #course,
    judgedSampleCount = #active,
    courseSpeed = statistics(courseSpeeds),
    courseAngle = statistics(courseAngles),
    judgedSpeed = statistics(U.copy(speeds)),
    judgedAngle = statistics(U.copy(angles)),
    driftEngagementQuality = engagement(active, config) * 100,
    judgedSpeeds = speeds,
    judgedAngles = angles
  }
end

return M
