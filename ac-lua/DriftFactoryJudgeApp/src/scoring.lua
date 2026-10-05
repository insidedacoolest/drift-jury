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

local function availableLine(pathValue, zones, clips, layout, config)
  local weighted, weights = pathValue * config.pathLineWeight, config.pathLineWeight
  if #layout.outerZones > 0 then
    weighted, weights = weighted + zones * config.outerZoneLineWeight, weights + config.outerZoneLineWeight
  end
  if #layout.innerClips > 0 then
    weighted, weights = weighted + clips * config.innerClipLineWeight, weights + config.innerClipLineWeight
  end
  return weights <= 0 and 1 or weighted / weights
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

local function weightedStyle(speed, fluidity, config)
  local total = config.speedStyleWeight + config.fluidityStyleWeight
  return total <= 0 and 1
    or (speed * config.speedStyleWeight + fluidity * config.fluidityStyleWeight) / total
end

local function styleQuality(bins, config)
  local speed = average(bins, function(sample)
    return U.clamp(sample.speedKmh / config.targetSpeedKmh, 0, 1)
  end)
  if #bins < 2 then return { speed = speed, fluidity = 1, combined = weightedStyle(speed, 1, config) } end
  local fluidity = 0
  for i = 2, #bins do
    local steer = normalizedCorrection(
      math.abs(bins[i].steerAngle - bins[i - 1].steerAngle),
      config.steeringDeadband, config.steeringCorrectionRange)
    local throttle = normalizedCorrection(
      math.abs(bins[i].gas - bins[i - 1].gas),
      config.throttleDeadband, config.throttleCorrectionRange)
    local angle = normalizedCorrection(
      math.abs(G.signedAngleDelta(bins[i - 1].signedAngleDeg, bins[i].signedAngleDeg)),
      config.angleChangeDeadbandDeg, config.angleCorrectionRangeDeg)
    local correction = steer * 0.40 + throttle * 0.25 + angle * 0.35
    fluidity = fluidity + 1 - U.clamp(correction, 0, 1)
  end
  fluidity = fluidity / (#bins - 1)
  return { speed = speed, fluidity = fluidity, combined = weightedStyle(speed, fluidity, config) }
end

local function percentageItems(items)
  local result = {}
  for _, item in ipairs(items) do result[#result + 1] = item * 100 end
  return result
end

function M.zero(reason)
  return {
    score = 0, line = 0, angle = 0, styleSpeed = 0, penalties = 0,
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
  local lineQuality = availableLine(path, zones.average, clips.average, layout, config)
  local angleValue = angleQuality(active, config)
  local style = styleQuality(active, config)
  local engaged = engagement(active, config)
  local line = config.leadLinePoints * lineQuality
  local angle = config.leadAnglePoints * angleValue
  local styleSpeed = config.leadStyleSpeedPoints * style.combined * engaged
  local maxAngle = 0
  for _, sample in ipairs(bins) do maxAngle = math.max(maxAngle, sample.angleDeg) end
  return {
    score = U.clamp(line + angle + styleSpeed - penalties, 0, 100),
    line = line,
    angle = angle,
    styleSpeed = styleSpeed,
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
    reason = 'Valid'
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
