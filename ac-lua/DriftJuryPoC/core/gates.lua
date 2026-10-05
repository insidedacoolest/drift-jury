--[[
  Pure helper for turning the car's own pose into a "gate" table
  ({ax,az,bx,bz,dirX,dirZ}) as expected by core/state_machine.crossedGate().

  Start/Finish gates are captured by driving to the spot and pressing a
  button — not by clicking two arbitrary points in free camera. That means
  the direction never needs to be derived or flipped: the car's own `look`
  vector already points the right way, and `side` gives a line across the
  track for free. This mirrors how DriftJudgeSP captures its Start/Finish
  (drive there, capture) instead of two independently clicked points.

  No `ac.*` calls here — same reasoning as the other core/ modules.
]]

local gates = {}

-- Builds a gate perpendicular to the car, `halfWidth` meters to each side,
-- with the crossing direction simply the car's own forward vector.
-- `y` is carried along purely for drawing the gate marker in 3D (same
-- convention as the `y` kept on drift-zone corridor points) — never read by
-- core/state_machine.crossedGate().
function gates.buildFromCarPose(x, y, z, sideX, sideZ, lookX, lookZ, halfWidth)
  return {
    ax = x - sideX * halfWidth, az = z - sideZ * halfWidth,
    bx = x + sideX * halfWidth, bz = z + sideZ * halfWidth,
    dirX = lookX, dirZ = lookZ,
    y = y,
  }
end

return gates
