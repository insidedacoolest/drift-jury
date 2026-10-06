local U = require('src.util')
local G = require('src.geometry')
local D = require('src.defaults')
local Scoring = require('src.scoring')
local Model = require('src.model')
local Leaderboard = require('src.leaderboard')
local M = {}
M.__index = M

local function worldFromLocal(position, look, localPoint)
  local forward = G.forwardFromLook(look)
  local right = { x = forward.z, y = 0, z = -forward.x }
  return {
    x = position.x + right.x * localPoint.x + forward.x * localPoint.z,
    y = position.y + localPoint.y,
    z = position.z + right.z * localPoint.x + forward.z * localPoint.z
  }
end

local function status(state, message)
  state.message = message
  state.messageAge = 0
end

function M.new(context)
  return setmetatable({
    context = context,
    state = 'idle',
    countdownRemaining = 0,
    runElapsed = 0,
    sampleAccumulator = 0,
    samples = {},
    penalties = 0,
    invalid = false,
    invalidReason = '',
    hornWasDown = false,
    previousPosition = nil,
    progressInitialized = false,
    progressSegment = 0,
    lastProgress = nil,
    spinSince = nil,
    lastProgressChanged = 0,
    lastProgressPosition = nil,
    resultAge = 99,
    message = '',
    messageAge = 99
  }, M)
end

function M:isBusy()
  return self.state == 'countdown' or self.state == 'running'
end

function M:resetProgress()
  self.progressInitialized = false
  self.progressSegment = 0
  self.lastProgress = nil
end

function M:getProgress(position)
  local path, config = self.context.layout.pathWaypoints, self.context.scoring
  if not self.progressInitialized then
    self.lastProgress = G.getProgress(path, position)
    self.progressSegment = self.lastProgress.segmentIndex
    self.progressInitialized = true
    return self.lastProgress
  end
  local candidate = G.getProgress(
    path,
    position,
    math.max(0, self.progressSegment - config.progressSearchBackSegments),
    math.min(math.max(0, #path - 2), self.progressSegment + config.progressSearchForwardSegments))
  if candidate.meters < self.lastProgress.meters then
    local backwards = self.lastProgress.meters - candidate.meters
    if backwards <= config.progressBacktrackToleranceMeters then
      local held = U.copy(self.lastProgress)
      held.distanceToPathMeters = candidate.distanceToPathMeters
      return held
    end
    return self.lastProgress
  end
  self.lastProgress, self.progressSegment = candidate, candidate.segmentIndex
  return candidate
end

function M:sample(nowMilliseconds)
  local car = ac.getCar(0)
  if not car then return nil end
  local position, look, velocity =
    U.fromVec3(car.position), U.fromVec3(car.look), U.fromVec3(car.velocity)
  local progress = self:getProgress(position)
  local signedAngle = G.signedSlipAngle(look, velocity)
  local forward = G.forwardFromLook(look)
  local center = car.aabbCenter and U.fromVec3(car.aabbCenter) or { x = 0, y = 0, z = 0 }
  local size = car.aabbSize and U.fromVec3(car.aabbSize) or { x = 2, y = 1, z = 4.4 }
  local front = worldFromLocal(position, forward, {
    x = center.x, y = center.y, z = center.z + size.z * 0.5
  })
  local rear = worldFromLocal(position, forward, {
    x = center.x, y = center.y, z = center.z - size.z * 0.5
  })
  local leftWheel, rightWheel = car.wheels[2], car.wheels[3]
  local left = leftWheel and U.fromVec3(leftWheel.contactPoint) or rear
  local right = rightWheel and U.fromVec3(rightWheel.contactPoint) or rear
  local steerLock = math.max(1, tonumber(car.steerLock) or 360)
  return {
    timeMilliseconds = nowMilliseconds,
    position = position,
    look = look,
    velocity = velocity,
    steerAngle = U.round(U.clamp(((tonumber(car.steer) or 0) / steerLock + 1) * 127.5, 0, 255)),
    gas = U.round(U.clamp((tonumber(car.gas) or 0) * 255, 0, 255)),
    signedAngleDeg = signedAngle,
    angleDeg = math.abs(signedAngle),
    speedKmh = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z) * 3.6,
    progress = progress,
    frontBumper = front,
    rearBumper = rear,
    rearWheelLeft = left,
    rearWheelRight = right,
    rearWheelLeftExact = leftWheel ~= nil,
    rearWheelRightExact = rightWheel ~= nil,
    exactWheelCoverage = (leftWheel and 0.5 or 0) + (rightWheel and 0.5 or 0),
    wheelsOutside = tonumber(car.wheelsOutside) or 0
  }
end

-- Unit direction of the route segment the car is on, flattened to the ground.
local function courseDirection(path, segmentIndex)
  local a, b = path[segmentIndex + 1], path[segmentIndex + 2]
  if not a or not b then return nil end
  local dx, dz = b.x - a.x, b.z - a.z
  local length = math.sqrt(dx * dx + dz * dz)
  if length < 0.01 then return nil end
  return dx / length, dz / length
end

local function routeLength(path)
  local total = 0
  for index = 2, #path do total = total + G.distance3(path[index - 1], path[index]) end
  return total
end

-- True once `condition` has held continuously for `graceSeconds`;
-- timers are kept per rule in self.ruleSince.
function M:sustained(rule, condition, now, graceSeconds)
  if not condition then
    self.ruleSince[rule] = nil
    return false
  end
  self.ruleSince[rule] = self.ruleSince[rule] or now
  return now - self.ruleSince[rule] >= graceSeconds * 1000
end

function M:beginCountdown()
  local context, pose = self.context, self.context.layout.leadStart
  if not pose then return end
  -- Auto-align (teleport to the start line) needs physics write access,
  -- which CSP itself withholds once connected to a multiplayer server —
  -- online, the driver lines up manually during the countdown instead.
  if physics.allowed() then
    physics.disableCarCollisions(0, true, false)
    local direction = pose.direction
    physics.setCarPosition(0, U.toVec3(pose.position), vec3(
      -(direction.x or 0), -(direction.y or 0), -(direction.z or 1)))
    physics.setCarVelocity(0, vec3())
  end
  self.state = 'countdown'
  self.countdownRemaining = D.flow.countdownSeconds
  self.samples, self.penalties, self.invalid, self.invalidReason = {}, 0, false, ''
  self.previousPosition, self.spinSince = nil, nil
  self.ruleSince, self.driftEngaged = {}, false
  self:resetProgress()
  status(self, context.calibration.active and 'Contagem decrescente de calibração iniciada.' or 'Contagem decrescente iniciada.')
end

function M:beginRun()
  self.state = 'running'
  self.runElapsed, self.sampleAccumulator = 0, 0
  self.ruleSince, self.driftEngaged, self.launched = {}, false, false
  self.courseLength = routeLength(self.context.layout.pathWaypoints)
  self:resetProgress()
  local first = self:sample(0)
  self.previousPosition = first and first.position or nil
  self.lastProgress = first and first.progress or nil
  self.lastProgressChanged = 0
  self.lastProgressPosition = first and first.position or nil
  status(self, 'Vai!')
end

function M:markInvalid(reason)
  if self.invalid then return end
  self.invalid, self.invalidReason = true, reason
end

function M:checkInvalid(sample)
  if sample.angleDeg < D.flow.spinAngleDeg then
    self.spinSince = nil
  else
    self.spinSince = self.spinSince or sample.timeMilliseconds
    if sample.timeMilliseconds - self.spinSince >= D.flow.spinGraceSeconds * 1000 then
      self:markInvalid('Trompo')
    end
  end
  if not self.lastProgressPosition then
    self.lastProgressChanged = sample.timeMilliseconds
    self.lastProgressPosition = sample.position
    self.lastProgress = sample.progress
  else
    local courseDelta = sample.progress.meters - self.lastProgress.meters
    local worldDelta = G.distance3(sample.position, self.lastProgressPosition)
    if courseDelta >= D.flow.noProgressMeters or worldDelta >= D.flow.noProgressMeters then
      self.lastProgressChanged = sample.timeMilliseconds
      self.lastProgressPosition = sample.position
      self.lastProgress = sample.progress
    end
    if sample.timeMilliseconds - self.lastProgressChanged >= D.flow.noProgressSeconds * 1000 then
      self:markInvalid('Sem progresso no percurso')
    end
  end

  local now, flow, scoring = sample.timeMilliseconds, D.flow, self.context.scoring

  -- Driving the wrong way: moving back along the route.
  local dirX, dirZ = courseDirection(self.context.layout.pathWaypoints, sample.progress.segmentIndex or 0)
  local horizontalSpeed = math.sqrt(sample.velocity.x * sample.velocity.x + sample.velocity.z * sample.velocity.z)
  local backwards = dirX ~= nil and sample.speedKmh >= flow.wrongWayMinSpeedKmh and horizontalSpeed > 0
    and (sample.velocity.x * dirX + sample.velocity.z * dirZ) / horizontalSpeed < -0.2
  if self:sustained('wrongWay', backwards, now, flow.wrongWayGraceSeconds) then
    self:markInvalid('Sentido contrário')
  end

  -- Straightening up: only once the drift has started, and not in the last
  -- meters before the finish where drivers may straighten to cross it.
  if sample.angleDeg >= scoring.minimumAngleDeg then self.driftEngaged = true end
  local remaining = (self.courseLength or 0) - sample.progress.meters
  -- A stopped car has no slip angle either; that case is reported as a stop.
  local straight = self.driftEngaged and sample.angleDeg < flow.straightenAngleDeg
    and sample.speedKmh >= flow.stopSpeedKmh and remaining > scoring.finishExclusionMeters
  if self:sustained('straighten', straight, now, flow.straightenGraceSeconds) then
    self:markInvalid('Endireitou o carro')
  end

  if self:sustained('offTrack', (sample.wheelsOutside or 0) >= flow.offTrackWheels, now, flow.offTrackGraceSeconds) then
    self:markInvalid('Saiu da pista')
  end

  -- Stopping: only after the launch, so a slow reaction at "Vai!" isn't a stop
  -- (never launching at all is caught by the no-progress rule above).
  if sample.speedKmh >= flow.launchedSpeedKmh then self.launched = true end
  if self:sustained('stop', self.launched and sample.speedKmh < flow.stopSpeedKmh, now, flow.stopGraceSeconds) then
    self:markInvalid('Parou o carro')
  end
end

function M:finish(reason)
  local context = self.context
  local score = Scoring.scoreLead(
    self.samples, context.layout, context.scoring, self.penalties, self.invalid, self.invalidReason)
  score.reason = score.valid and 'Válida' or (self.invalidReason ~= '' and self.invalidReason or reason)
  score.calibration = context.calibration.active
  context.lastResult = score
  self.resultAge = 0
  if physics.allowed() then physics.disableCarCollisions(0, false, false) end
  self.state = 'result'
  if context.calibration.active then
    local analysis = Scoring.analyzeRun(self.samples, context.layout, context.scoring)
    local run = context.calibration:add(score.valid, score.reason, score, analysis)
    status(self, run.valid
      and string.format('Run de calibração %d/5 válida: %.1f pontos.', #context.calibration.validRuns, score.score)
      or string.format('Tentativa de calibração inválida: %s.', run.reason))
  else
    Leaderboard.report(score)
    local ok, recordOrError = context.storage:addResult(context.results, score)
    if not ok then
      status(self, 'Resultado guardado em memória, mas falhou ao gravar: ' .. tostring(recordOrError))
    else
      context.lastResult = recordOrError
      status(self, recordOrError.personalBest
        and string.format('Novo PB: %.1f pontos!', score.score)
        or (score.valid and string.format('Pontuação: %.1f pontos.', score.score)
          or 'Run inválida: ' .. score.reason))
    end
  end
end

function M:cancel(message)
  if not self:isBusy() then return end
  if physics.allowed() then physics.disableCarCollisions(0, false, false) end
  self.state = 'idle'
  self.samples = {}
  status(self, message or 'Run cancelada.')
end

function M:update(dt)
  self.messageAge = self.messageAge + dt
  self.resultAge = self.resultAge + dt
  local context = self.context
  local sim, car = ac.getSim(), ac.getCar(0)
  if not sim or not car then return end
  local hornDown = car.hornActive == true
  local hornEdge = hornDown and not self.hornWasDown
  self.hornWasDown = hornDown

  -- Replay genuinely can't run a live judged session (no live telemetry to
  -- judge). Online multiplayer used to be blocked here too, in the
  -- original DriftJudging SP — see CREDITS.md for why this fork keeps it
  -- working online instead.
  if sim.isReplayActive then
    if self:isBusy() then self:cancel('Run cancelada: isto é um replay.') end
    return
  end

  if self.state == 'result' and self.resultAge > 4 then self.state = 'idle' end
  if self.state == 'idle' or self.state == 'result' then
    if hornEdge and Model.isReady(context.layout)
      and context.calibration.recommendation == nil
      and G.insideCircle(U.fromVec3(car.position), context.layout.leadStart.position,
        context.layout.leadStart.radiusMeters) then
      self:beginCountdown()
    end
    return
  end

  if self.state == 'countdown' then
    self.countdownRemaining = self.countdownRemaining - dt
    -- Moving off before the countdown ends voids the run outright.
    local speed = tonumber(car.speedKmh) or 0
    if speed > D.flow.jumpStartSpeedKmh then
      self:markInvalid('Partida antecipada')
      self:finish('Partida antecipada')
      return
    end
    if self.countdownRemaining <= 0 then self:beginRun() end
    return
  end

  if self.state == 'running' then
    self.runElapsed = self.runElapsed + dt
    self.sampleAccumulator = self.sampleAccumulator + dt
    while self.sampleAccumulator >= 0.05 do
      self.sampleAccumulator = self.sampleAccumulator - 0.05
      local sample = self:sample(U.round(self.runElapsed * 1000))
      if sample then
        self.samples[#self.samples + 1] = sample
        self:checkInvalid(sample)
        if self.invalid then self:finish(self.invalidReason) return end
        if self.previousPosition and G.crossedGate(
          self.previousPosition, sample.position, context.layout.finishGate) then
          self:finish('Terminada')
          return
        end
        self.previousPosition = sample.position
      end
    end
    if self.runElapsed >= D.flow.maxRunSeconds then
      self:markInvalid('Tempo limite excedido')
      self:finish('Tempo limite excedido')
    end
  end
end

return M
