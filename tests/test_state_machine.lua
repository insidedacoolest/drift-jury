local sm = require('state_machine')

return {
  { name = 'segmentsIntersect detects a straightforward crossing', fn = function()
    local hit, ix, iz = sm.segmentsIntersect(-1, 5, 1, 5, 0, 0, 0, 10)
    assert(hit)
    assert(math.abs(ix - 0) < 1e-6)
    assert(math.abs(iz - 5) < 1e-6)
  end },
  { name = 'segmentsIntersect returns false when segments do not meet', fn = function()
    local hit = sm.segmentsIntersect(-1, 20, 1, 20, 0, 0, 0, 10)
    assert(not hit)
  end },
  { name = 'segmentsIntersect returns false for parallel segments', fn = function()
    local hit = sm.segmentsIntersect(0, 0, 0, 10, 5, 0, 5, 10)
    assert(not hit)
  end },
  { name = 'crossedGate ignores a crossing in the wrong direction', fn = function()
    local gate = { ax = -2, az = 5, bx = 2, bz = 5, dirX = 0, dirZ = 1 }
    -- moving from z=6 to z=4 is backwards through a gate that expects +z travel
    local crossed = sm.crossedGate(0, 6, 0, 4, gate)
    assert(not crossed)
  end },
  { name = 'crossedGate accepts a crossing in the configured direction', fn = function()
    local gate = { ax = -2, az = 5, bx = 2, bz = 5, dirX = 0, dirZ = 1 }
    local crossed = sm.crossedGate(0, 4, 0, 6, gate)
    assert(crossed)
  end },
  { name = 'crossedGate ignores movement that never reaches the gate line', fn = function()
    local gate = { ax = -2, az = 5, bx = 2, bz = 5, dirX = 0, dirZ = 1 }
    local crossed = sm.crossedGate(0, 1, 0, 2, gate)
    assert(not crossed)
  end },
  { name = 'nextState follows the configured transition table', fn = function()
    assert(sm.nextState(sm.RunState.IDLE, 'START_CROSSED') == sm.RunState.RUNNING)
    assert(sm.nextState(sm.RunState.RUNNING, 'FINISH_CROSSED') == sm.RunState.FINISHED)
    assert(sm.nextState(sm.RunState.RUNNING, 'ABORTED') == sm.RunState.IDLE)
    assert(sm.nextState(sm.RunState.FINISHED, 'COOLDOWN_ELAPSED') == sm.RunState.COOLDOWN)
    assert(sm.nextState(sm.RunState.COOLDOWN, 'COOLDOWN_ELAPSED') == sm.RunState.IDLE)
  end },
  { name = 'nextState ignores unknown events instead of erroring', fn = function()
    assert(sm.nextState(sm.RunState.IDLE, 'NONSENSE') == sm.RunState.IDLE)
  end },
  { name = 'nextState ignores an event not valid for the current state', fn = function()
    -- FINISH_CROSSED only makes sense while RUNNING
    assert(sm.nextState(sm.RunState.IDLE, 'FINISH_CROSSED') == sm.RunState.IDLE)
  end },
}
