--[[
  Pure geometry for drift-zone corridors. A corridor is an ordered list of
  {x, z, width} control points (world-space, ground plane) — see §11 of the
  architecture blueprint for why corridors were chosen over fixed boxes:
  a drift line snakes, a box doesn't.

  No `ac.*` calls here either — same reasoning as core/angle.lua.
]]

local zones = {}

-- Closest point on segment (ax,az)-(bx,bz) to point (px,pz), clamped to the
-- segment (t in [0,1]). Standard projection-and-clamp.
local function closestPointOnSegment(px, pz, ax, az, bx, bz)
  local abx, abz = bx - ax, bz - az
  local abLenSq = abx * abx + abz * abz
  if abLenSq < 1e-9 then
    return ax, az, 0
  end
  local t = ((px - ax) * abx + (pz - az) * abz) / abLenSq
  t = math.max(0, math.min(1, t))
  return ax + abx * t, az + abz * t, t
end

-- Projects a world-space point (px, pz) onto a corridor and returns:
--   depth         0..1 — how centered the point is (1 = dead center of the
--                 corridor at that point, 0 = at or beyond the edge). This
--                 is what the scoring engine reads as "how well was the
--                 zone filled", per §11/§42 of the blueprint.
--   lateralOffset signed distance from the centerline, in meters. Sign is
--                 an internal convention (see tests) — consistent, not
--                 meant to be read as "left"/"right" without also knowing
--                 the corridor's own direction.
--   width         corridor width at the closest point (interpolated between
--                 the two nearest control points).
--
-- Zone *activation* (was the car in this zone at all) is a separate
-- question, answered by zones.isActiveAtPoint below — not by this function.
function zones.project(px, pz, corridor)
  assert(corridor and #corridor >= 2, 'corridor needs at least 2 points')

  local best = nil
  for i = 1, #corridor - 1 do
    local a, b = corridor[i], corridor[i + 1]
    local cx, cz, segT = closestPointOnSegment(px, pz, a.x, a.z, b.x, b.z)
    local dx, dz = px - cx, pz - cz
    local distSq = dx * dx + dz * dz
    if not best or distSq < best.distSq then
      local abx, abz = b.x - a.x, b.z - a.z
      local segLen = math.sqrt(abx * abx + abz * abz)
      local cross = abx * dz - abz * dx
      local signedOffset = segLen > 1e-9 and (cross / segLen) or 0
      local width = a.width + (b.width - a.width) * segT
      best = { distSq = distSq, signedOffset = signedOffset, width = width }
    end
  end

  local halfWidth = math.max(best.width, 1e-6) / 2
  local depth = 1 - math.min(1, math.abs(best.signedOffset) / halfWidth)

  return {
    depth = math.max(0, depth),
    lateralOffset = best.signedOffset,
    width = best.width,
  }
end

-- Raw (unclamped) segment parameter t, plus the segment's length. t < 0
-- means (px,pz) projects behind (ax,az); t > 1 means beyond (bx,bz).
local function rawSegmentT(px, pz, ax, az, bx, bz)
  local abx, abz = bx - ax, bz - az
  local abLenSq = abx * abx + abz * abz
  if abLenSq < 1e-9 then
    return 0, 0
  end
  local t = ((px - ax) * abx + (pz - az) * abz) / abLenSq
  return t, math.sqrt(abLenSq)
end

-- Says whether a world-space point is within the corridor's own drawn span
-- — i.e. not extending past the first point against the corridor's entry
-- direction, nor past the last point along its exit direction. Uses only
-- the corridor's own geometry (no AI spline needed), which is what makes
-- this work on tracks that don't have one, unlike the splinePosition-based
-- check this replaces. `margin` (meters) lets the zone arm a touch early
-- and disarm a touch late, same purpose as the old SPLINE_MARGIN.
--
-- A point far to the side of the corridor (but between its ends) still
-- counts as active — that's intentional, `zones.project` already scores it
-- with a depth near 0, which is what "drifted way off the line" should
-- look like, not "zone never activated".
function zones.isActiveAtPoint(px, pz, corridor, margin)
  margin = margin or 0
  assert(corridor and #corridor >= 2, 'corridor needs at least 2 points')

  local first, second = corridor[1], corridor[2]
  local tStart, lenStart = rawSegmentT(px, pz, first.x, first.z, second.x, second.z)
  if tStart < 0 and -tStart * lenStart > margin then
    return false
  end

  local last, beforeLast = corridor[#corridor], corridor[#corridor - 1]
  local tEnd, lenEnd = rawSegmentT(px, pz, beforeLast.x, beforeLast.z, last.x, last.z)
  if tEnd > 1 and (tEnd - 1) * lenEnd > margin then
    return false
  end

  return true
end

return zones
