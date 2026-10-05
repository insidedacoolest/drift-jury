--[[
  Pure run-lifecycle logic: gate-crossing geometry and the state transition
  table (§44 of the blueprint). No `ac.*` calls — the app feeds this module
  plain numbers each frame and reacts to what comes back.

  Phase 1 uses a reduced state set (IDLE / RUNNING / FINISHED / COOLDOWN).
  The full set from the blueprint (READY, ARMED, INVALID) gets folded in
  during Phase 2 once there are pre-run checks and zero-run conditions that
  need them — adding states later only means adding rows to TRANSITIONS,
  not rewriting this module.
]]

local state_machine = {}

local RunState = {
  IDLE = 'IDLE',
  RUNNING = 'RUNNING',
  FINISHED = 'FINISHED',
  COOLDOWN = 'COOLDOWN',
}
state_machine.RunState = RunState

local TRANSITIONS = {
  [RunState.IDLE] = { START_CROSSED = RunState.RUNNING },
  [RunState.RUNNING] = { FINISH_CROSSED = RunState.FINISHED, ABORTED = RunState.IDLE },
  [RunState.FINISHED] = { COOLDOWN_ELAPSED = RunState.COOLDOWN },
  [RunState.COOLDOWN] = { COOLDOWN_ELAPSED = RunState.IDLE },
}

-- Pure transition function. An event with no matching row is ignored (stays
-- in the current state) rather than raising an error — a stray/duplicate
-- event should never be able to crash the app mid-run.
function state_machine.nextState(current, event)
  local row = TRANSITIONS[current]
  local nxt = row and row[event]
  return nxt or current
end

-- Standard 2D segment-segment intersection (parametric form). Returns
-- true plus the intersection point if segments (p1,p2) and (p3,p4) cross.
function state_machine.segmentsIntersect(p1x, p1z, p2x, p2z, p3x, p3z, p4x, p4z)
  local d1x, d1z = p2x - p1x, p2z - p1z
  local d2x, d2z = p4x - p3x, p4z - p3z
  local denom = d1x * d2z - d1z * d2x
  if math.abs(denom) < 1e-9 then
    return false -- parallel (or degenerate) — never happens for a real gate crossing
  end
  local t = ((p3x - p1x) * d2z - (p3z - p1z) * d2x) / denom
  local u = ((p3x - p1x) * d1z - (p3z - p1z) * d1x) / denom
  if t >= 0 and t <= 1 and u >= 0 and u <= 1 then
    return true, p1x + d1x * t, p1z + d1z * t
  end
  return false
end

-- A gate is { ax, az, bx, bz, dirX, dirZ }: a line segment plus the
-- expected direction of travel through it (unit-ish vector, only its sign
-- matters). Returns true if the car's position moved from (prevX,prevZ) to
-- (curX,curZ) across the gate segment *and* that movement has a positive
-- dot product with the gate's configured direction — so clipping the line
-- while reversing out of a spin doesn't falsely start/end a run.
function state_machine.crossedGate(prevX, prevZ, curX, curZ, gate)
  local crossed = state_machine.segmentsIntersect(prevX, prevZ, curX, curZ, gate.ax, gate.az, gate.bx, gate.bz)
  if not crossed then
    return false
  end
  local moveX, moveZ = curX - prevX, curZ - prevZ
  local dot = moveX * gate.dirX + moveZ * gate.dirZ
  return dot > 0
end

return state_machine
