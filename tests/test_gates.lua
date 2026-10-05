local gates = require('gates')
local sm = require('state_machine')

-- Car at (5, z=10), facing north (look = 0,1), side = 1,0 (its right), 3m half-width.
local NORTH_GATE = gates.buildFromCarPose(5, 0, 10, 1, 0, 0, 1, 3)

return {
  { name = 'buildFromCarPose places A/B halfWidth to each side of the car, along `side`', fn = function()
    assert(math.abs(NORTH_GATE.ax - 2) < 1e-6 and math.abs(NORTH_GATE.az - 10) < 1e-6,
      string.format('%.2f,%.2f', NORTH_GATE.ax, NORTH_GATE.az))
    assert(math.abs(NORTH_GATE.bx - 8) < 1e-6 and math.abs(NORTH_GATE.bz - 10) < 1e-6,
      string.format('%.2f,%.2f', NORTH_GATE.bx, NORTH_GATE.bz))
  end },
  { name = 'buildFromCarPose direction is exactly the car\'s look vector', fn = function()
    local gate = gates.buildFromCarPose(10, 0, 20, 1, 0, 0.6, 0.8, 3)
    assert(math.abs(gate.dirX - 0.6) < 1e-6)
    assert(math.abs(gate.dirZ - 0.8) < 1e-6)
  end },
  { name = 'buildFromCarPose keeps y only for drawing, unread by state_machine', fn = function()
    local gate = gates.buildFromCarPose(0, 12.5, 5, 1, 0, 0, 1, 2)
    assert(gate.y == 12.5)
  end },
  { name = 'a gate built from car pose accepts a crossing in the car\'s own forward direction', fn = function()
    local crossed = sm.crossedGate(5, 9, 5, 11, NORTH_GATE)
    assert(crossed)
  end },
  { name = 'a gate built from car pose rejects a crossing backwards through it', fn = function()
    local crossed = sm.crossedGate(5, 11, 5, 9, NORTH_GATE)
    assert(not crossed)
  end },
}
