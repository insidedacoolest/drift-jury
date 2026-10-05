local U = require('src.util')
local G = require('src.geometry')
local D = require('src.defaults')
local M = {}
M.__index = M

local function cloneCarPose()
  local car = ac.getCar(0)
  if not car then return nil end
  return U.fromVec3(car.position), G.forwardFromLook(U.fromVec3(car.look))
end

local function distanceSquared(a, b)
  local x, z = a.x - b.x, a.z - b.z
  return x * x + z * z
end

local function pointSegmentDistanceSquared(point, a, b)
  local x, z = b.x - a.x, b.z - a.z
  local length = x * x + z * z
  if length < 0.0001 then return distanceSquared(point, a) end
  local t = U.clamp(((point.x - a.x) * x + (point.z - a.z) * z) / length, 0, 1)
  local dx, dz = point.x - (a.x + x * t), point.z - (a.z + z * t)
  return dx * dx + dz * dz
end

function M.new(context)
  return setmetatable({
    context = context,
    mode = 'none',
    recording = false,
    outerDraft = {},
    undo = {},
    dragging = nil,
    hiddenOuterZones = {},
    hiddenInnerClips = {},
    previousLeft = false,
    previousRight = false,
    routeSmoothRadius = 15,
    startRadius = D.editor.startRadiusMeters,
    finishWidth = D.editor.finishWidthMeters,
    clipRadius = D.editor.clipRadiusMeters,
    debug = false
  }, M)
end

function M:isOuterZoneVisible(index)
  return self.hiddenOuterZones[index] ~= true
end

function M:setOuterZoneVisible(index, visible)
  if visible then
    self.hiddenOuterZones[index] = nil
  else
    self.hiddenOuterZones[index] = true
  end
  if not visible
    and self.dragging
    and self.dragging.kind == 'outer'
    and self.dragging.zone == index then
    self.dragging = nil
  end
end

function M:isInnerClipVisible(index)
  return self.hiddenInnerClips[index] ~= true
end

function M:setInnerClipVisible(index, visible)
  if visible then
    self.hiddenInnerClips[index] = nil
  else
    self.hiddenInnerClips[index] = true
  end
end

function M:pushUndo()
  self.undo[#self.undo + 1] = U.copy(self.context.layout)
  while #self.undo > 25 do table.remove(self.undo, 1) end
end

function M:changed(message)
  self.context.dirty = true
  self.context.status = message
end

function M:undoLast()
  if #self.undo == 0 then return end
  self.context.layout = table.remove(self.undo)
  self.context:refreshScoring()
  self:changed('Desfeita a última edição do layout.')
end

function M:setMode(mode)
  self.mode = self.mode == mode and 'none' or mode
  self.dragging = nil
end

function M:captureLeadStart()
  local position, direction = cloneCarPose()
  if not position then return end
  self:pushUndo()
  self.context.layout.leadStart = {
    position = position, direction = direction, radiusMeters = self.startRadius
  }
  self:changed('Partida capturada.')
end

function M:captureFinish()
  local position, direction = cloneCarPose()
  if not position then return end
  self:pushUndo()
  self.context.layout.finishGate = {
    center = position, direction = direction, widthMeters = self.finishWidth
  }
  self:changed('Gate de chegada capturado.')
end

function M:addRoutePoint(position)
  self.context.layout.pathWaypoints[#self.context.layout.pathWaypoints + 1] = U.copy(position)
end

function M:toggleRecording()
  self.recording = not self.recording
  if self.recording then
    self:pushUndo()
    self.mode = 'none'
    local position = cloneCarPose()
    if position then self:addRoutePoint(position) end
    self:changed('Gravação da rota iniciada.')
  else
    self:changed('Gravação da rota parada.')
  end
end

function M:clearRoute()
  if #self.context.layout.pathWaypoints == 0 then return end
  self:pushUndo()
  self.context.layout.pathWaypoints = {}
  self:changed('Rota limpa.')
end

function M:finishOuter()
  if #self.outerDraft < 3 then
    self.context.status = 'Uma zona exterior precisa de pelo menos três pontos.'
    return
  end
  self:pushUndo()
  self.context.layout.outerZones[#self.context.layout.outerZones + 1] = {
    name = 'Exterior ' .. (#self.context.layout.outerZones + 1),
    points = U.copy(self.outerDraft)
  }
  self.outerDraft = {}
  self:changed('Zona exterior adicionada.')
end

function M:cancelOuter()
  self.outerDraft = {}
  self.context.status = 'Rascunho da zona exterior cancelado.'
end

function M:updateRecording()
  if not self.recording then return end
  local car = ac.getCar(0)
  if not car then return end
  local position = U.fromVec3(car.position)
  local route = self.context.layout.pathWaypoints
  if #route == 0 or G.distance2(route[#route], position) >= D.editor.pathRecordingSpacingMeters then
    self:addRoutePoint(position)
    self.context.dirty = true
  end
end

function M:rayHit()
  if not render.createMouseRay then return nil end
  local ray = render.createMouseRay()
  if not ray then return nil end
  local distance = ray:track()
  if not distance or distance < 0 then return nil end
  return U.fromVec3(ray.pos + ray.dir * distance)
end

function M:nearestRoute(point, radius)
  local best, bestDistance = nil, radius * radius
  for index, routePoint in ipairs(self.context.layout.pathWaypoints) do
    local distance = distanceSquared(point, routePoint)
    if distance <= bestDistance then best, bestDistance = index, distance end
  end
  return best
end

function M:nearestRouteSegment(point, radius)
  local route = self.context.layout.pathWaypoints
  local best, bestDistance = nil, radius * radius
  for index = 1, #route - 1 do
    local distance = pointSegmentDistanceSquared(point, route[index], route[index + 1])
    if distance <= bestDistance then best, bestDistance = index, distance end
  end
  return best
end

function M:nearestOuter(point, radius)
  local best, bestDistance = nil, radius * radius
  for index, draftPoint in ipairs(self.outerDraft) do
    local distance = distanceSquared(point, draftPoint)
    if distance <= bestDistance then
      best, bestDistance = { draft = true, index = index }, distance
    end
  end
  for zoneIndex, zone in ipairs(self.context.layout.outerZones) do
    if self:isOuterZoneVisible(zoneIndex) then
      for index, zonePoint in ipairs(zone.points) do
        local distance = distanceSquared(point, zonePoint)
        if distance <= bestDistance then
          best, bestDistance = { zone = zoneIndex, index = index }, distance
        end
      end
    end
  end
  return best
end

function M:nearestOuterEdge(point, radius)
  local best, bestDistance = nil, radius * radius
  for zoneIndex, zone in ipairs(self.context.layout.outerZones) do
    if self:isOuterZoneVisible(zoneIndex) then
      for index = 1, #zone.points do
        local distance = pointSegmentDistanceSquared(point, zone.points[index], zone.points[index % #zone.points + 1])
        if distance <= bestDistance then
          best, bestDistance = { zone = zoneIndex, index = index }, distance
        end
      end
    end
  end
  return best
end

function M:nearestClip(point, radius)
  local best, bestDistance = nil, radius * radius
  for index, clip in ipairs(self.context.layout.innerClips) do
    if self:isInnerClipVisible(index) then
      local distance = distanceSquared(point, clip.position)
      if distance <= bestDistance then best, bestDistance = index, distance end
    end
  end
  return best
end

function M:applyRouteDrag(hit)
  local route = self.context.layout.pathWaypoints
  local drag = self.dragging
  if not drag or drag.kind ~= 'route' then return end
  if drag.smooth ~= true then
    route[drag.index] = U.copy(hit)
    return
  end

  local original = drag.originalRoute
  if not original or not original[drag.index] then return end
  local cumulative = { 0 }
  for index = 2, #original do
    cumulative[index] = cumulative[index - 1] + G.distance2(original[index - 1], original[index])
  end

  local source = original[drag.index]
  local delta = {
    x = hit.x - source.x,
    y = (hit.y or 0) - (source.y or 0),
    z = hit.z - source.z
  }
  local radius = U.clamp(tonumber(drag.smoothRadius) or self.routeSmoothRadius, 5, 30)
  local selectedDistance = cumulative[drag.index] or 0
  for index, point in ipairs(original) do
    local routeDistance = math.abs((cumulative[index] or 0) - selectedDistance)
    if routeDistance <= radius then
      local weight = 0.5 * (1 + math.cos(math.pi * routeDistance / radius))
      route[index] = {
        x = point.x + delta.x * weight,
        y = (point.y or 0) + delta.y * weight,
        z = point.z + delta.z * weight
      }
    else
      route[index] = U.copy(point)
    end
  end
  route[drag.index] = U.copy(hit)
end

function M:uiCapturesMouse()
  local state = ac.getUI and ac.getUI() or nil
  return state and state.wantCaptureMouse == true
end

function M:update3D()
  if self.context.session:isBusy() or self.context.calibration.active then
    self.recording = false
    self.dragging = nil
    return
  end
  self:updateRecording()
  if self.mode == 'none' then
    self.dragging = nil
    return
  end
  local hit = self:rayHit()
  if not hit then return end
  local leftButton = ui.MouseButton and ui.MouseButton.Left or 0
  local rightButton = ui.MouseButton and ui.MouseButton.Right or 1
  local left = ui.mouseDown and ui.mouseDown(leftButton) or false
  local right = ui.mouseDown and ui.mouseDown(rightButton) or false
  local leftPressed, leftReleased = left and not self.previousLeft, not left and self.previousLeft
  local rightPressed = right and not self.previousRight
  local ctrl = ui.keyboardButtonDown and ui.KeyIndex
    and ui.keyboardButtonDown(ui.KeyIndex.Control)
  local shift = ui.keyboardButtonDown and ui.KeyIndex and ui.KeyIndex.Shift
    and ui.keyboardButtonDown(ui.KeyIndex.Shift)
  local captured = self:uiCapturesMouse()

  if self.dragging and left then
    if self.dragging.kind == 'route' then
      self:applyRouteDrag(hit)
    elseif self.dragging.kind == 'outerDraft' then
      self.outerDraft[self.dragging.index] = U.copy(hit)
    elseif self.dragging.kind == 'outer' then
      self.context.layout.outerZones[self.dragging.zone].points[self.dragging.index] = U.copy(hit)
    end
    self.context.dirty = true
  end
  if self.dragging and leftReleased then
    self.dragging = nil
    self:changed('Ponto movido.')
  end

  if not captured and leftPressed and not self.dragging then
    if self.mode == 'route' then
      if ctrl then
        local segment = self:nearestRouteSegment(hit, 2)
        if segment then
          self:pushUndo()
          table.insert(self.context.layout.pathWaypoints, segment + 1, U.copy(hit))
          self:changed('Ponto de rota inserido.')
        end
      else
        local index = self:nearestRoute(hit, 0.8)
        if index then
          self:pushUndo()
          self.dragging = {
            kind = 'route',
            index = index,
            smooth = shift == true,
            smoothRadius = self.routeSmoothRadius,
            originalRoute = U.copy(self.context.layout.pathWaypoints)
          }
        end
      end
    elseif self.mode == 'outer' then
      if ctrl then
        local edge = self:nearestOuterEdge(hit, 2)
        self:pushUndo()
        if edge then
          table.insert(self.context.layout.outerZones[edge.zone].points, edge.index + 1, U.copy(hit))
          self:changed('Ponto da zona exterior inserido.')
        else
          self.outerDraft[#self.outerDraft + 1] = U.copy(hit)
          self.context.status = 'Ponto de rascunho exterior adicionado.'
        end
      else
        local target = self:nearestOuter(hit, 0.8)
        if target then
          self:pushUndo()
          self.dragging = target.draft
            and { kind = 'outerDraft', index = target.index }
            or { kind = 'outer', zone = target.zone, index = target.index }
        end
      end
    elseif self.mode == 'clip' and ctrl then
      self:pushUndo()
      self.context.layout.innerClips[#self.context.layout.innerClips + 1] = {
        name = 'Clip ' .. (#self.context.layout.innerClips + 1),
        position = U.copy(hit),
        radiusMeters = self.clipRadius
      }
      self:changed('Clip interior adicionado.')
    end
  end

  if not captured and rightPressed then
    if self.mode == 'route' then
      local index = self:nearestRoute(hit, 0.8)
      if index and #self.context.layout.pathWaypoints > 2 then
        self:pushUndo()
        table.remove(self.context.layout.pathWaypoints, index)
        self:changed('Ponto de rota removido.')
      end
    elseif self.mode == 'outer' then
      local target = self:nearestOuter(hit, 0.8)
      if target then
        if target.draft then
          table.remove(self.outerDraft, target.index)
          self.context.status = 'Ponto de rascunho removido.'
        else
          local points = self.context.layout.outerZones[target.zone].points
          if #points > 3 then
            self:pushUndo()
            table.remove(points, target.index)
            self:changed('Ponto da zona exterior removido.')
          end
        end
      end
    elseif self.mode == 'clip' then
      local index = self:nearestClip(hit, 1)
      if index then
        self:pushUndo()
        table.remove(self.context.layout.innerClips, index)
        self:changed('Clip interior removido.')
      end
    end
  end

  self.previousLeft, self.previousRight = left, right
end

return M
