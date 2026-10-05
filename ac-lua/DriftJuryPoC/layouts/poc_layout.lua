--[[
  Placeholder layout for the Phase 1 Proof of Concept.

  Every coordinate below is a PLACEHOLDER near the world origin — it will
  not line up with any real track. Use the app's CAPTURE mode (see the
  README next to this file) to drive your actual track once and record
  real values, then replace this file's numbers with the exported ones.

  Coordinates are world-space, ground-plane meters: x = car.position.x,
  z = car.position.z (the CSP `y` axis, altitude, is intentionally unused
  here — see §11 of the architecture blueprint on corridors being modeled
  in 2D).

  Known Phase 1 limitation: a zone/gate that spans the start/finish line
  (the corridor's own first/last points wrapping around) is not supported
  yet — pick a layout section that doesn't cross the line.
]]

return {
  schema_version = '1.0',
  id = 'poc_layout',
  name = 'Phase 1 Proof of Concept (placeholder — capture your own)',

  -- A gate is a line segment (ax,az)-(bx,bz) plus the direction the car is
  -- expected to be travelling when it crosses. dirX/dirZ only need to point
  -- roughly the right way — only their sign (via dot product) is checked.
  -- The editor's "Capturar aqui" buttons build this straight from the
  -- car's pose (core/gates.lua buildFromCarPose), so dirX/dirZ always match
  -- exactly the direction the car was facing at capture time.
  startGate = { ax = -5, az = 0, bx = 5, bz = 0, dirX = 0, dirZ = 1 },
  finishGate = { ax = -5, az = 100, bx = 5, bz = 100, dirX = 0, dirZ = 1 },

  zone = {
    id = 'zone_1',
    -- Zone activation is decided purely from this corridor's own geometry
    -- (see core/zones.lua isActiveAtPoint) — no AI spline needed.
    corridor = {
      { x = -3, z = 20, width = 5 },
      { x = 0, z = 50, width = 5 },
      { x = 3, z = 80, width = 5 },
    },
    -- Curves are {min, target, max, overshootPenalty?} — see core/scoring.lua
    -- for exactly how these turn into a 0-100 score.
    angleCurve = { min = 20, target = 55, max = 70, overshootPenalty = 50 },
    speedCurve = { min = 40, target = 80, max = 140, overshootPenalty = 20 },
  },

  -- Relative importance of each component in the final 0-100 total. Phase 1
  -- only has three components; `style` joins in Phase 2.
  weights = { line = 40, angle = 35, speed = 25 },

  minDriftSpeedMs = 3, -- below this, angle samples are treated as invalid (see core/angle.lua)
  cooldownSeconds = 3, -- lockout after FINISHED before a new START_CROSSED is accepted
}
