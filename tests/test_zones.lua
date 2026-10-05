local zones = require('zones')

local straightCorridor = {
  { x = 0, z = 0, width = 4 },
  { x = 0, z = 100, width = 4 },
}

return {
  { name = 'centerline point has depth 1', fn = function()
    local r = zones.project(0, 50, straightCorridor)
    assert(math.abs(r.depth - 1) < 1e-6, r.depth)
  end },
  { name = 'point exactly at the edge has depth 0', fn = function()
    local r = zones.project(2, 50, straightCorridor) -- half-width is 2
    assert(math.abs(r.depth) < 1e-6, r.depth)
  end },
  { name = 'point outside the corridor clamps depth to 0, not negative', fn = function()
    local r = zones.project(10, 50, straightCorridor)
    assert(r.depth == 0)
  end },
  { name = 'lateral offset sign flips between the two sides', fn = function()
    local sideA = zones.project(1, 50, straightCorridor)
    local sideB = zones.project(-1, 50, straightCorridor)
    assert(sideA.lateralOffset * sideB.lateralOffset < 0)
  end },
  { name = 'width interpolates along a tapering corridor', fn = function()
    local taper = {
      { x = 0, z = 0, width = 2 },
      { x = 0, z = 10, width = 10 },
    }
    local r = zones.project(0, 5, taper) -- halfway
    assert(math.abs(r.width - 6) < 1e-6, r.width)
  end },
  { name = 'isActiveAtPoint is true for a point within the corridor span', fn = function()
    assert(zones.isActiveAtPoint(0, 50, straightCorridor, 0) == true)
  end },
  { name = 'isActiveAtPoint is true even far off to the side, as long as within the span', fn = function()
    assert(zones.isActiveAtPoint(50, 50, straightCorridor, 0) == true)
  end },
  { name = 'isActiveAtPoint is false well before the corridor start', fn = function()
    assert(zones.isActiveAtPoint(0, -50, straightCorridor, 0) == false)
  end },
  { name = 'isActiveAtPoint is false well after the corridor end', fn = function()
    assert(zones.isActiveAtPoint(0, 150, straightCorridor, 0) == false)
  end },
  { name = 'isActiveAtPoint margin arms the zone a bit before the start', fn = function()
    assert(zones.isActiveAtPoint(0, -1, straightCorridor, 2) == true)
    assert(zones.isActiveAtPoint(0, -3, straightCorridor, 2) == false)
  end },
  { name = 'isActiveAtPoint margin disarms the zone a bit after the end', fn = function()
    assert(zones.isActiveAtPoint(0, 101, straightCorridor, 2) == true)
    assert(zones.isActiveAtPoint(0, 103, straightCorridor, 2) == false)
  end },
  { name = 'isActiveAtPoint works with the minimum 2-point corridor', fn = function()
    assert(zones.isActiveAtPoint(0, 50, straightCorridor, 0) == true)
    assert(zones.isActiveAtPoint(0, -10, straightCorridor, 0) == false)
  end },
}
