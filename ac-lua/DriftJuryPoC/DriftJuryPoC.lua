--[[
  Drift Jury - Fase 1 Proof of Concept

  Reads the local car's telemetry every frame, detects Start/Finish gate
  crossings, scores a single drift zone, and shows a debug HUD. All the
  actual math (angle, corridor projection, scoring curves, gate geometry,
  run state transitions) lives in core/ as plain, ac.*-free Lua modules —
  see tests/ at the repo root for their unit tests. This file's only job is
  wiring those pure functions to real telemetry, to mouse/camera input for
  the layout editor, and to the HUD.

  Install: copy (or junction) this folder to
    <AssettoCorsa>/apps/lua/DriftJuryPoC
  then enable "Drift Jury (PoC)" from the in-game apps list.
]]

local angle = require('core/angle')
local zones = require('core/zones')
local scoring = require('core/scoring')
local sm = require('core/state_machine')
local gates = require('core/gates')

local layout = require('layouts/poc_layout')

local car = ac.getCar(0) or error('DriftJuryPoC: no car at index 0')

local pb = ac.storage({ bestScore = 0 })

local COOLDOWN_LOCKOUT_SECONDS = 1.0 -- short extra lockout after the result is shown, so lingering near the finish line can't double-trigger
local ZONE_ACTIVATION_MARGIN = 2.0 -- meters the zone arms early/disarms late, at either end of the drawn corridor (see core/zones.lua isActiveAtPoint)

--[[ ---------------------------------------------------------------------
  Run tracking — unchanged from the driving-only version of this app.
----------------------------------------------------------------------- ]]

local runState = sm.RunState.IDLE
local prevX, prevZ = car.position.x, car.position.z
local cooldownRemaining = 0
local maxAngleSeen = 0
local lastResult = nil

local accum = { angleSum = 0, angleWeight = 0, speedSum = 0, depthSum = 0, dt = 0 }

local function resetAccumulators()
  accum.angleSum, accum.angleWeight = 0, 0
  accum.speedSum, accum.depthSum, accum.dt = 0, 0, 0
  maxAngleSeen = 0
end

-- Turns the run's accumulated samples into the 0-100 breakdown described in
-- §12/§15 of the architecture blueprint. Phase 1 only has three components
-- (line/angle/speed) — `style` is a Phase 2 addition once there's more than
-- one zone's worth of behaviour to measure consistency across.
local function finalizeScore()
  local avgAngle = accum.angleWeight > 0 and (accum.angleSum / accum.angleWeight) or 0
  local avgSpeedKmh = accum.dt > 0 and (accum.speedSum / accum.dt) or 0
  local avgDepth = accum.dt > 0 and (accum.depthSum / accum.dt) or 0

  local lineScore = avgDepth * 100
  local angleScore = scoring.rampScore(avgAngle, layout.zone.angleCurve)
  local speedScore = scoring.rampScore(avgSpeedKmh, layout.zone.speedCurve)
  local total = scoring.combine({ line = lineScore, angle = angleScore, speed = speedScore }, layout.weights)

  local isPB = total > pb.bestScore
  if isPB then
    pb.bestScore = total
  end

  return {
    total = total,
    line = lineScore,
    angle = angleScore,
    speed = speedScore,
    avgAngle = avgAngle,
    maxAngle = maxAngleSeen,
    avgSpeedKmh = avgSpeedKmh,
    zoneTimeSeconds = accum.dt,
    isPB = isPB,
    bestScore = pb.bestScore,
  }
end

--[[ ---------------------------------------------------------------------
  Layout editor.

  Start/Finish gates are captured by driving to the spot and pressing a
  button — the gate is built straight from the car's own pose
  (core/gates.lua buildFromCarPose), so there's no direction ambiguity and
  no flip toggle to get wrong. This mirrors how the reference app
  DriftJudgeSP captures its Start/Finish.

  The drift-zone corridor is still placed from free camera (F7), since
  there's no single "correct" line to drive to define it — clicking on the
  track adds a new point, and clicking near an already-placed point drags
  it instead, letting the corridor be refined without starting over.
  Confirmed feasible against the CSP Lua API actually installed on this
  machine (not guessed):

    render.createMouseRay()   screen-space mouse -> world-space ray
    physics.raycastTrack(...) ray -> point on the track surface
    render.debugLine/Text     draw the placed points back in 3D, from a
                               global draw3D() function wired up via
                               manifest.ini's [RENDER_CALLBACKS] — see the
                               comment above drawCircle for why that wiring
                               (not the function name/body) was the actual
                               bug the whole time.

  Zone *activation* (whether the car is currently within the corridor's
  span) is computed purely from the corridor's own geometry (see
  core/zones.lua isActiveAtPoint) — no AI spline required, so this works on
  any track.
----------------------------------------------------------------------- ]]

local editor = {
  active = false,
  zoneWidth = 5.0,
  zonePoints = {}, -- { {x=, y=, z=, width=}, ... } — y is kept only for drawing, never used by core/zones.lua
  dragIndex = nil, -- index into zonePoints currently being dragged, or nil
  startGate = nil, -- {ax,az,bx,bz,dirX,dirZ,y}, built by core/gates.lua buildFromCarPose
  finishGate = nil,
  startGateWidth = 8.0,
  finishGateWidth = 8.0,
  hover = nil, -- last raycast hit point under the cursor, for the preview marker
  clickCount = 0, -- diagnostic counter: how many times a zone point has actually been committed
  lastMessage = nil, -- last action's result, shown directly in the panel (see editorSetMessage)
  lastMessageOk = false,
}

local COLOR_START = rgbm(1, 0.7, 0.1, 1)
local COLOR_FINISH = rgbm(0.1, 0.75, 1, 1)
local COLOR_ZONE = rgbm(0.25, 0.9, 0.4, 1)
local COLOR_ZONE_DRAG = rgbm(1, 0.85, 0.15, 1)
local COLOR_HOVER = rgbm(1, 1, 1, 0.7)
local DRAW_LIFT = 0.08 -- meters above the raycast hit, purely so markers don't z-fight with the track surface
local PICK_RADIUS_METERS = 1.5 -- clicking within this distance of an existing zone point drags it instead of adding a new one

-- Sets both the in-game log (ac.log/ac.warn — needs the CSP Lua console to
-- see) and editor.lastMessage (shown directly in windowMain), since the
-- console isn't something every player has open or knows how to find.
local function editorSetMessage(ok, text)
  editor.lastMessageOk = ok
  editor.lastMessage = text
  if ok then ac.log('[DriftJury] ' .. text) else ac.warn('[DriftJury] ' .. text) end
end

-- Builds Start or Finish straight from the car's current pose — no free
-- camera, no raycast, just "drive here and press the button".
local function editorCaptureGate(which)
  local halfWidth = (which == 'START' and editor.startGateWidth or editor.finishGateWidth) / 2
  local gate = gates.buildFromCarPose(
    car.position.x, car.position.y, car.position.z,
    car.side.x, car.side.z, car.look.x, car.look.z,
    halfWidth)
  if which == 'START' then
    editor.startGate = gate
  else
    editor.finishGate = gate
  end
  editorSetMessage(true, (which == 'START' and 'Start' or 'Finish') .. ' capturado na posicao atual do carro.')
end

local function editorCommitPoint(hit)
  editor.clickCount = editor.clickCount + 1
  table.insert(editor.zonePoints, { x = hit.x, y = hit.y, z = hit.z, width = editor.zoneWidth })
end

-- Raycasts the current mouse position against the track surface. Returns a
-- {x,y,z} point, or nil if the cursor isn't over any track geometry.
local function raycastMouseOnTrack()
  local ray = render.createMouseRay()
  local hitPoint, hitNormal = vec3(), vec3()
  local dist = physics.raycastTrack(ray.pos, ray.dir, 2000, hitPoint, hitNormal)
  if dist and dist > 0 then
    return { x = hitPoint.x, y = hitPoint.y, z = hitPoint.z }
  end
  return nil
end

-- Index of the nearest existing zone point within PICK_RADIUS_METERS of
-- `hover`, or nil if none is close enough to count as "clicking on it".
local function findNearbyZonePointIndex(hover)
  local bestIndex, bestDistSq = nil, PICK_RADIUS_METERS * PICK_RADIUS_METERS
  for i, p in ipairs(editor.zonePoints) do
    local dx, dz = p.x - hover.x, p.z - hover.z
    local distSq = dx * dx + dz * dz
    if distSq <= bestDistSq then
      bestIndex, bestDistSq = i, distSq
    end
  end
  return bestIndex
end

-- render.debugSphere never rendered anything, in any of the places we tried
-- calling it from — turned out the real bug was one level up: our
-- manifest.ini never declared a [RENDER_CALLBACKS] section, so CSP had no
-- 3D-drawing callback registered for this app at all, regardless of what
-- Lua function we called or what we named it. Found by comparing against a
-- published app (DriftJudgeSP) that does the same kind of layout editing —
-- its manifest.ini has `[RENDER_CALLBACKS] TRANSPARENT=draw3D`, ours now
-- does too (see manifest.ini), wired to the global draw3D() function below.
-- Its own drawing code draws circles as a ring of render.debugLine segments
-- rather than render.debugSphere, so that's what this matches too.
local function drawCircle(center, radius, color)
  local segments = 20
  local prev = vec3(center.x + radius, center.y, center.z)
  for i = 1, segments do
    local a = i / segments * math.pi * 2
    local cur = vec3(center.x + math.cos(a) * radius, center.y, center.z + math.sin(a) * radius)
    render.debugLine(prev, cur, color)
    prev = cur
  end
end

local function drawGate(gate, color, label)
  if not gate then return end
  local ay = gate.y + DRAW_LIFT
  local a, b = vec3(gate.ax, ay, gate.az), vec3(gate.bx, ay, gate.bz)
  drawCircle(a, 0.4, color)
  drawCircle(b, 0.4, color)
  render.debugLine(a, b, color)
  local midX, midZ = (gate.ax + gate.bx) / 2, (gate.az + gate.bz) / 2
  local mid, tip = vec3(midX, ay, midZ), vec3(midX + gate.dirX * 4, ay, midZ + gate.dirZ * 4)
  render.debugLine(mid, tip, color)
  if render.debugText then
    render.debugText(vec3(midX, ay + 0.5, midZ), label, color, 1.2)
  end
end

-- Input/state (raycast, click, drag) — runs every tick regardless of
-- whether anything ends up drawn.
local function updateEditor()
  local uiState = ac.getUI()
  editor.hover = raycastMouseOnTrack()
  local mouseDown = uiState.isMouseLeftKeyDown
  local clickedEdge = uiState.isMouseLeftKeyClicked and not uiState.wantCaptureMouse

  if editor.dragIndex then
    if editor.hover and mouseDown then
      local p = editor.zonePoints[editor.dragIndex]
      p.x, p.y, p.z = editor.hover.x, editor.hover.y, editor.hover.z
    end
    if not mouseDown then
      editor.dragIndex = nil
    end
  elseif clickedEdge and editor.hover then
    local nearIndex = findNearbyZonePointIndex(editor.hover)
    if nearIndex then
      editor.dragIndex = nearIndex
    else
      editorCommitPoint(editor.hover)
    end
  end
end

local function drawEditor()
  if editor.hover then
    drawCircle(vec3(editor.hover.x, editor.hover.y + DRAW_LIFT, editor.hover.z), 0.3, COLOR_HOVER)
  end

  drawGate(editor.startGate, COLOR_START, 'START')
  drawGate(editor.finishGate, COLOR_FINISH, 'FINISH')

  for i, p in ipairs(editor.zonePoints) do
    local color = (i == editor.dragIndex) and COLOR_ZONE_DRAG or COLOR_ZONE
    drawCircle(vec3(p.x, p.y + DRAW_LIFT, p.z), 0.25, color)
    if i > 1 then
      local prev = editor.zonePoints[i - 1]
      render.debugLine(vec3(prev.x, prev.y + DRAW_LIFT, prev.z), vec3(p.x, p.y + DRAW_LIFT, p.z), COLOR_ZONE)
    end
  end
end

local function editorExport()
  if not (editor.startGate and editor.finishGate and #editor.zonePoints >= 2) then
    editorSetMessage(false, 'Layout incompleto: falta capturar Start, Finish, ou pelo menos 2 pontos de zona.')
    return
  end

  local exported = {
    schema_version = '1.0',
    id = 'edited_' .. os.date('%Y%m%d_%H%M%S'),
    name = 'Layout capturado pelo editor',
    startGate = editor.startGate,
    finishGate = editor.finishGate,
    zone = {
      id = 'zone_1',
      corridor = editor.zonePoints,
      angleCurve = layout.zone.angleCurve,
      speedCurve = layout.zone.speedCurve,
    },
    weights = layout.weights,
    minDriftSpeedMs = layout.minDriftSpeedMs,
    cooldownSeconds = layout.cooldownSeconds,
  }

  local folder = ac.getFolder(ac.FolderID.AppDataLocal) .. '/DriftJuryPoC'
  io.createDir(folder)
  local path = folder .. '/captured_layout.lua'
  local ok = io.save(path, 'return ' .. stringify(exported, false))
  if ok then
    editorSetMessage(true, 'Layout exportado para: ' .. path)
  else
    editorSetMessage(false, 'Falha ao gravar o layout em: ' .. path)
  end
end

--[[ ---------------------------------------------------------------------
  Main update loop.
----------------------------------------------------------------------- ]]

function script.update(dt)
  if editor.active then
    updateEditor()
  end

  local curX, curZ = car.position.x, car.position.z

  if runState == sm.RunState.FINISHED then
    cooldownRemaining = cooldownRemaining - dt
    if cooldownRemaining <= 0 then
      runState = sm.nextState(runState, 'COOLDOWN_ELAPSED')
      cooldownRemaining = COOLDOWN_LOCKOUT_SECONDS
    end
  elseif runState == sm.RunState.COOLDOWN then
    cooldownRemaining = cooldownRemaining - dt
    if cooldownRemaining <= 0 then
      runState = sm.nextState(runState, 'COOLDOWN_ELAPSED')
    end
  elseif runState == sm.RunState.IDLE then
    if sm.crossedGate(prevX, prevZ, curX, curZ, layout.startGate) then
      runState = sm.nextState(runState, 'START_CROSSED')
      resetAccumulators()
      lastResult = nil
      ac.log('[DriftJury] Run started')
    end
  elseif runState == sm.RunState.RUNNING then
    if car.isInPit then
      runState = sm.nextState(runState, 'ABORTED')
      ac.log('[DriftJury] Run aborted: car returned to pits')
    else
      local driftDeg, driftValid = angle.driftAngleDeg(car.localVelocity, layout.minDriftSpeedMs)
      local zoneActive = zones.isActiveAtPoint(curX, curZ, layout.zone.corridor, ZONE_ACTIVATION_MARGIN)

      if zoneActive then
        local proj = zones.project(curX, curZ, layout.zone.corridor)
        accum.dt = accum.dt + dt
        accum.depthSum = accum.depthSum + proj.depth * dt
        accum.speedSum = accum.speedSum + car.speedKmh * dt
        if driftValid then
          accum.angleSum = accum.angleSum + math.abs(driftDeg) * dt
          accum.angleWeight = accum.angleWeight + dt
          if math.abs(driftDeg) > maxAngleSeen then
            maxAngleSeen = math.abs(driftDeg)
          end
        end
      end

      if sm.crossedGate(prevX, prevZ, curX, curZ, layout.finishGate) then
        lastResult = finalizeScore()
        runState = sm.nextState(runState, 'FINISH_CROSSED')
        cooldownRemaining = layout.cooldownSeconds
        ac.log(string.format('[DriftJury] Run finished: total=%.2f (line=%.1f angle=%.1f speed=%.1f)',
          lastResult.total, lastResult.line, lastResult.angle, lastResult.speed))
      end
    end
  end

  prevX, prevZ = curX, curZ
end

-- Deliberately a bare global, not script.draw3D — matches manifest.ini's
-- `[RENDER_CALLBACKS] TRANSPARENT = draw3D` and DriftJudgeSP's own
-- convention for this specific callback (its other callbacks are also bare
-- globals: worldUpdate, windowMain — script.update/windowMain being valid
-- too seems to be a separate, parallel convention CSP also accepts, but
-- draw3D specifically wasn't wired up in the [RENDER_CALLBACKS] sense
-- before, so this sticks to what's proven to work).
editor.draw3DCallCount = 0
function draw3D()
  editor.draw3DCallCount = editor.draw3DCallCount + 1
  if editor.active then
    drawEditor()
  end
end

--[[ ---------------------------------------------------------------------
  HUD.
----------------------------------------------------------------------- ]]

local function gateStatus(gate)
  if not gate then return 'nao capturado' end
  local midX, midZ = (gate.ax + gate.bx) / 2, (gate.az + gate.bz) / 2
  return string.format('capturado (%.1f, %.1f)', midX, midZ)
end

function script.windowMain(dt)
  ui.text('Estado: ' .. runState)
  ui.separator()

  ui.text(string.format('Velocidade: %.0f km/h', car.speedKmh))
  local liveDeg, liveValid = angle.driftAngleDeg(car.localVelocity, layout.minDriftSpeedMs)
  ui.text('Angulo: ' .. (liveValid and string.format('%.1f deg', liveDeg) or '--'))

  if runState == sm.RunState.RUNNING then
    local zoneActive = zones.isActiveAtPoint(car.position.x, car.position.z, layout.zone.corridor, ZONE_ACTIVATION_MARGIN)
    ui.text('Zona: ' .. (zoneActive and 'ATIVA' or '-'))
    if zoneActive then
      local proj = zones.project(car.position.x, car.position.z, layout.zone.corridor)
      ui.text(string.format('Profundidade: %.0f%%', proj.depth * 100))
    end
  end

  if lastResult then
    ui.separator()
    ui.textColored(string.format('TOTAL  %.2f', lastResult.total), rgbm(0.88, 0.64, 0.31, 1))
    ui.text(string.format('  Linha    %.1f', lastResult.line))
    ui.text(string.format('  Angulo   %.1f', lastResult.angle))
    ui.text(string.format('  Velocidade %.1f', lastResult.speed))
    ui.text(string.format('Angulo medio %.1f deg | maximo %.1f deg', lastResult.avgAngle, lastResult.maxAngle))
    if lastResult.isPB then
      ui.textColored('NOVO RECORDE PESSOAL', rgbm(0.4, 0.8, 0.5, 1))
    else
      ui.text(string.format('Recorde pessoal: %.2f', lastResult.bestScore))
    end
  end

  ui.separator()
  if ui.button(editor.active and 'Sair do editor de layout' or 'Editor de layout') then
    editor.active = not editor.active
  end

  if editor.active then
    ui.separator()
    ui.textWrapped('Start/Finish: conduz ate ao sitio e clica "Capturar aqui". Zona: entra em camara livre (F7), aponta o rato para a pista e clica para adicionar um ponto — clica perto de um ponto ja colocado para o arrastar.', 320)

    if ui.button('Capturar Start aqui') then editorCaptureGate('START') end
    ui.sameLine(0, 8)
    editor.startGateWidth = ui.slider('##startGateWidth', editor.startGateWidth, 2, 20, 'Largura: %.1f m')
    ui.text('  Start: ' .. gateStatus(editor.startGate))

    if ui.button('Capturar Finish aqui') then editorCaptureGate('FINISH') end
    ui.sameLine(0, 8)
    editor.finishGateWidth = ui.slider('##finishGateWidth', editor.finishGateWidth, 2, 20, 'Largura: %.1f m')
    ui.text('  Finish: ' .. gateStatus(editor.finishGate))

    ui.separator()
    editor.zoneWidth = ui.slider('##zoneWidth', editor.zoneWidth, 1, 12, 'Largura da zona: %.1f m')
    ui.text(string.format('Pontos de zona: %d', #editor.zonePoints))

    ui.separator()
    ui.textColored('Diagnostico (apaga-se quando isto estiver a funcionar):', rgbm(0.7, 0.7, 0.7, 1))
    local diagUI = ac.getUI()
    ui.text('  Rato sobre a pista (raycast): ' .. (editor.hover and string.format('SIM (%.1f, %.1f, %.1f)', editor.hover.x, editor.hover.y, editor.hover.z) or 'NAO — rato nao esta a acertar em geometria da pista'))
    ui.text('  Botao esquerdo clicado agora: ' .. tostring(diagUI.isMouseLeftKeyClicked))
    ui.text('  UI a capturar o rato (wantCaptureMouse): ' .. tostring(diagUI.wantCaptureMouse))
    ui.text('  Total de cliques registados: ' .. editor.clickCount)
    ui.text('  A arrastar ponto de zona: ' .. (editor.dragIndex and ('#' .. editor.dragIndex) or 'nenhum'))
    ui.text('  Chamadas a draw3D: ' .. editor.draw3DCallCount .. (editor.draw3DCallCount == 0 and '  <-- se ficar a 0, o manifest.ini ainda nao pegou (reinicia o jogo)' or ''))

    if ui.button('Remover ultimo ponto de zona') then table.remove(editor.zonePoints) end
    ui.sameLine(0, 6)
    if ui.button('Limpar tudo') then
      editor.startGate, editor.finishGate = nil, nil
      editor.zonePoints = {}
      editor.dragIndex = nil
    end

    ui.separator()
    if ui.button('Exportar layout') then editorExport() end
    if editor.lastMessage then
      ui.textColored(editor.lastMessage, editor.lastMessageOk and rgbm(0.4, 0.8, 0.5, 1) or rgbm(0.9, 0.3, 0.3, 1))
    end
  end
end
