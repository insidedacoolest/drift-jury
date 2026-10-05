local U = require('src.util')
local M = {}

local function dot2(a, b)
  return a.x * b.x + a.z * b.z
end

local function length2(value)
  return math.sqrt(value.x * value.x + value.z * value.z)
end

local function sub(a, b)
  return { x = a.x - b.x, y = (a.y or 0) - (b.y or 0), z = a.z - b.z }
end

local function addScaled(a, b, scale)
  return { x = a.x + b.x * scale, y = (a.y or 0) + (b.y or 0) * scale, z = a.z + b.z * scale }
end

function M.distance2(a, b)
  local x, z = a.x - b.x, a.z - b.z
  return math.sqrt(x * x + z * z)
end

function M.distance3(a, b)
  local x, y, z = a.x - b.x, (a.y or 0) - (b.y or 0), a.z - b.z
  return math.sqrt(x * x + y * y + z * z)
end

function M.signedAngleDelta(fromDeg, toDeg)
  return (toDeg - fromDeg + 540) % 360 - 180
end

function M.forwardFromLook(look)
  local length = length2(look)
  if length < 0.0001 then return { x = 0, y = 0, z = 1 } end
  return { x = look.x / length, y = 0, z = look.z / length }
end

function M.headingFromLook(look)
  local forward = M.forwardFromLook(look)
  local angle = -math.deg(math.atan2(forward.x, forward.z))
  return angle < 0 and angle + 360 or angle
end

function M.velocityHeading(velocity, fallback)
  if math.abs(velocity.x) < 1 and math.abs(velocity.z) < 1 then return fallback end
  local angle = -math.deg(math.atan2(velocity.x, velocity.z))
  return angle < 0 and angle + 360 or angle
end

function M.signedSlipAngle(look, velocity)
  local heading = M.headingFromLook(look)
  return M.signedAngleDelta(heading, M.velocityHeading(velocity, heading))
end

function M.offset(position, look, meters)
  local forward = M.forwardFromLook(look)
  return {
    x = position.x + forward.x * meters,
    y = position.y,
    z = position.z + forward.z * meters
  }
end

function M.insideCircle(point, center, radius)
  return M.distance2(point, center) <= radius
end

function M.crossedGate(previous, current, gate)
  local normal = M.forwardFromLook(gate.direction)
  local prev = sub(previous, gate.center)
  local nextValue = sub(current, gate.center)
  local prevSide = dot2(prev, normal)
  local nextSide = dot2(nextValue, normal)
  if prevSide > 0 or nextSide < 0 then return false end
  local t = math.abs(prevSide) / math.max(0.0001, math.abs(prevSide) + math.abs(nextSide))
  local crossing = {
    x = U.lerp(previous.x, current.x, t) - gate.center.x,
    y = 0,
    z = U.lerp(previous.z, current.z, t) - gate.center.z
  }
  local lateral = { x = -normal.z, y = 0, z = normal.x }
  return math.abs(dot2(crossing, lateral)) <= (gate.widthMeters or 14) * 0.5
end

function M.pointInPolygon(point, polygon)
  if #polygon < 3 then return false end
  local inside = false
  local j = #polygon
  for i = 1, #polygon do
    local pi, pj = polygon[i], polygon[j]
    local denominator = pj.z - pi.z
    if math.abs(denominator) < 0.00001 then denominator = denominator < 0 and -0.00001 or 0.00001 end
    local intersects = ((pi.z > point.z) ~= (pj.z > point.z))
      and point.x < (pj.x - pi.x) * (point.z - pi.z) / denominator + pi.x
    if intersects then inside = not inside end
    j = i
  end
  return inside
end

function M.distanceToSegment(point, a, b)
  local ab = sub(b, a)
  local lengthSquared = dot2(ab, ab)
  if lengthSquared <= 0.0001 then return M.distance2(point, a) end
  local t = U.clamp(dot2(sub(point, a), ab) / lengthSquared, 0, 1)
  return M.distance2(point, addScaled(a, ab, t))
end

function M.signedDistanceToPolygon(point, polygon)
  if #polygon < 3 then return -math.huge end
  local distance = math.huge
  for i = 1, #polygon do
    distance = math.min(distance, M.distanceToSegment(point, polygon[i], polygon[i % #polygon + 1]))
  end
  return M.pointInPolygon(point, polygon) and distance or -distance
end

function M.pathLength(path)
  local length = 0
  for i = 2, #path do length = length + M.distance2(path[i - 1], path[i]) end
  return length
end

function M.getProgress(path, point, firstSegment, lastSegment)
  if #path == 0 then return { meters = 0, distanceToPathMeters = 0, normalized = 0, segmentIndex = 0 } end
  if #path == 1 then
    return { meters = 0, distanceToPathMeters = M.distance2(path[1], point), normalized = 0, segmentIndex = 0 }
  end

  firstSegment = U.clamp(firstSegment or 0, 0, #path - 2)
  lastSegment = U.clamp(lastSegment or (#path - 2), firstSegment, #path - 2)
  local bestDistance, bestAlong, bestSegment = math.huge, 0, firstSegment
  local traversed = 0
  for luaIndex = 1, #path - 1 do
    local segmentIndex = luaIndex - 1
    local a, b = path[luaIndex], path[luaIndex + 1]
    local ab = sub(b, a)
    local length = length2(ab)
    if length > 0.0001 then
      if segmentIndex >= firstSegment and segmentIndex <= lastSegment then
        local t = U.clamp(dot2(sub(point, a), ab) / dot2(ab, ab), 0, 1)
        local closest = addScaled(a, ab, t)
        local distance = M.distance2(point, closest)
        if distance < bestDistance then
          bestDistance = distance
          bestAlong = traversed + length * t
          bestSegment = segmentIndex
        end
      end
      traversed = traversed + length
    end
  end

  if bestDistance == math.huge then bestDistance = M.distance2(path[1], point) end
  return {
    meters = bestAlong,
    distanceToPathMeters = bestDistance,
    normalized = traversed <= 0 and 0 or U.clamp(bestAlong / traversed, 0, 1),
    segmentIndex = bestSegment
  }
end

function M.createOffsetPath(path, offsetMeters, maxMiterMultiplier)
  if #path < 2 or math.abs(offsetMeters) <= 0.0001 then return U.copy(path) end
  maxMiterMultiplier = maxMiterMultiplier or 2
  local result = {}
  local maxMiter = math.abs(offsetMeters) * math.max(1, maxMiterMultiplier)

  local function direction(segment)
    local delta = sub(path[segment + 2], path[segment + 1])
    local length = length2(delta)
    return length <= 0.0001 and { x = 0, z = 1 } or { x = delta.x / length, z = delta.z / length }
  end

  for i = 1, #path do
    local previous = direction(math.max(0, i - 2))
    local following = direction(math.min(#path - 2, i - 1))
    local pNormal = { x = previous.z, z = -previous.x }
    local nNormal = { x = following.z, z = -following.x }
    local normal = { x = pNormal.x + nNormal.x, z = pNormal.z + nNormal.z }
    local normalLength = math.sqrt(normal.x * normal.x + normal.z * normal.z)
    if normalLength <= 0.0001 then normal, normalLength = nNormal, 1 end
    normal.x, normal.z = normal.x / normalLength, normal.z / normalLength
    local denominator = math.abs(normal.x * nNormal.x + normal.z * nNormal.z)
    local miter = math.min(math.abs(offsetMeters) / math.max(0.25, denominator), maxMiter)
    if offsetMeters < 0 then miter = -miter end
    result[i] = { x = path[i].x + normal.x * miter, y = path[i].y, z = path[i].z + normal.z * miter }
  end
  return result
end

return M
