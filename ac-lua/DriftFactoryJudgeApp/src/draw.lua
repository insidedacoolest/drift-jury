local U = require('src.util')
local G = require('src.geometry')
local M = {}

local colors = {
  route = rgbm(0.85, 0.9, 1, 1),
  corridor = rgbm(0.25, 0.75, 1, 0.9),
  start = rgbm(0.2, 1, 0.25, 1),
  finish = rgbm(1, 0.9, 0.2, 1),
  outer = rgbm(1, 0.42, 0.05, 1),
  draft = rgbm(1, 0.1, 1, 1),
  clip = rgbm(0.2, 1, 1, 1)
}

-- Palette pulled from driftfactory.pt, used for the score HUD specifically
-- (not the 3D editor markers above, which keep their own scheme).
local BRAND = {
  panelBg = rgbm(11 / 255, 12 / 255, 15 / 255, 0.92),
  accent = rgbm(212 / 255, 255 / 255, 63 / 255, 1), -- lime
  accent2 = rgbm(255 / 255, 62 / 255, 200 / 255, 1), -- magenta, invalid/attention
  text = rgbm(243 / 255, 244 / 255, 239 / 255, 1), -- cream
  muted = rgbm(154 / 255, 160 / 255, 172 / 255, 1),
}

local hudWindowWidth = 380
local hudWindowTopPadding = 26
local hudWindowBottomPadding = 6

local function elevate(point, amount)
  return vec3(point.x, point.y + (amount or 0.08), point.z)
end

local function line(a, b, color, height)
  render.debugLine(elevate(a, height), elevate(b, height), color)
end

local function circle(point, radius, color)
  local segments = math.max(20, math.min(48, math.ceil(radius * 12)))
  local previous = { x = point.x + radius, y = point.y, z = point.z }
  for index = 1, segments do
    local angle = index / segments * math.pi * 2
    local current = {
      x = point.x + math.cos(angle) * radius,
      y = point.y,
      z = point.z + math.sin(angle) * radius
    }
    line(previous, current, color)
    previous = current
  end
end

local function label(point, text, color)
  if render.debugText then
    render.debugText(elevate(point, 0.35), text, color, 0.8, render.FontAlign.Left)
  end
end

local function drawRoute(layout)
  local route = layout.pathWaypoints
  for index = 2, #route do line(route[index - 1], route[index], colors.route) end
  for index, point in ipairs(route) do
    circle(point, 0.3, colors.route)
    if index == 1 or (index - 1) % 10 == 0 then label(point, 'P' .. index, colors.route) end
  end
  if #route >= 2 then
    local left = G.createOffsetPath(route, layout.pathCorridorHalfWidthMeters)
    local right = G.createOffsetPath(route, -layout.pathCorridorHalfWidthMeters)
    for index = 2, #left do
      line(left[index - 1], left[index], colors.corridor)
      line(right[index - 1], right[index], colors.corridor)
    end
  end
end

local function drawFinish(gate)
  local direction = G.forwardFromLook(gate.direction)
  local lateral = { x = -direction.z, y = 0, z = direction.x }
  local half = gate.widthMeters * 0.5
  local a = { x = gate.center.x - lateral.x * half, y = gate.center.y, z = gate.center.z - lateral.z * half }
  local b = { x = gate.center.x + lateral.x * half, y = gate.center.y, z = gate.center.z + lateral.z * half }
  line(a, b, colors.finish, 0.15)
  line(gate.center, {
    x = gate.center.x + direction.x * 4,
    y = gate.center.y,
    z = gate.center.z + direction.z * 4
  }, colors.finish, 0.15)
  label(gate.center, 'CHEGADA', colors.finish)
end

function M.layout(context)
  local editor, layout = context.editor, context.layout
  if not editor.debug then return end
  drawRoute(layout)
  if layout.leadStart then
    circle(layout.leadStart.position, layout.leadStart.radiusMeters, colors.start)
    label(layout.leadStart.position, 'PARTIDA', colors.start)
  end
  if layout.finishGate then drawFinish(layout.finishGate) end
  for zoneIndex, zone in ipairs(layout.outerZones) do
    if editor:isOuterZoneVisible(zoneIndex) then
      for index, point in ipairs(zone.points) do
        line(point, zone.points[index % #zone.points + 1], colors.outer, 0.12)
        circle(point, 0.3, colors.outer)
        if index == 1 then label(point, 'EXTERIOR ' .. zoneIndex, colors.outer) end
      end
    end
  end
  for index, point in ipairs(editor.outerDraft) do
    circle(point, 0.35, colors.draft)
    if index > 1 then line(editor.outerDraft[index - 1], point, colors.draft, 0.15) end
  end
  for index, clip in ipairs(layout.innerClips) do
    if editor:isInnerClipVisible(index) then
      circle(clip.position, clip.radiusMeters, colors.clip)
      label(clip.position, 'CLIP ' .. index, colors.clip)
      -- (kept as "CLIP" untranslated — common drift-scene loanword)
    end
  end
  if editor.mode ~= 'none' then
    local hit = editor:rayHit()
    if hit then circle(hit, editor.mode == 'clip' and editor.clipRadius or 0.55, colors.draft) end
  end
end

local function fill(p1, p2, color, rounding)
  ui.drawRectFilled(p1, p2, color, rounding or 5)
end

local function text(value, size, position, color)
  if ui.dwriteDrawText then
    ui.dwriteDrawText(value, size, position, color)
  else
    ui.setCursor(position)
    ui.textColored(value, color)
  end
end

-- A slanted "speed stripe" instead of a plain vertical accent bar — the
-- recurring livery-style signature element that shows up in every HUD state.
local function accentStripe(p1, p2, color)
  ui.drawQuadFilled(
    vec2(p1.x, p1.y), vec2(p1.x + 16, p1.y),
    vec2(p1.x + 6, p2.y), vec2(p1.x, p2.y), color)
end

-- Small cut-corner wedge at the panel's top-right, like a livery badge.
local function cornerWedge(topRight, size, color)
  ui.drawTriangleFilled(
    vec2(topRight.x - size, topRight.y), topRight, vec2(topRight.x, topRight.y + size), color)
end

local function withAlpha(color, alpha)
  return rgbm(color.r, color.g, color.b, color.mult * alpha)
end

-- Expanding, fading ring — used to give the countdown a "pulse" every second.
local function pulseRing(center, baseRadius, phase, color)
  ui.drawCircle(center, baseRadius + phase * 22, withAlpha(color, 1 - phase), 40, 2.5)
end

local function arc(center, radius, angleFrom, angleTo, color, thickness)
  local segments = 28
  local previous = nil
  for i = 0, segments do
    local t = i / segments
    local angle = angleFrom + (angleTo - angleFrom) * t
    local point = vec2(center.x + math.cos(angle) * radius, center.y + math.sin(angle) * radius)
    if previous then ui.drawLine(previous, point, color, thickness) end
    previous = point
  end
end

-- Speedometer-style gauge: 240 degree sweep opening at the bottom, apex at
-- the top. Color runs from the lime accent toward magenta as the value
-- approaches/exceeds the target, so the driver reads "getting hot" at a
-- glance instead of having to read the number.
local function angleGauge(center, radius, valueDeg, maxDeg, targetDeg, trackColor)
  local angleFrom, angleTo = math.rad(150), math.rad(390)
  arc(center, radius, angleFrom, angleTo, trackColor, 5)
  local normalized = U.clamp(valueDeg / maxDeg, 0, 1)
  local heat = U.clamp(valueDeg / math.max(1, targetDeg), 0, 1.4) / 1.4
  local needleColor = rgbm(
    BRAND.accent.r + (BRAND.accent2.r - BRAND.accent.r) * heat,
    BRAND.accent.g + (BRAND.accent2.g - BRAND.accent.g) * heat,
    BRAND.accent.b + (BRAND.accent2.b - BRAND.accent.b) * heat, 1)
  arc(center, radius, angleFrom, angleFrom + (angleTo - angleFrom) * normalized, needleColor, 5)
  local tip = vec2(center.x + math.cos(angleFrom + (angleTo - angleFrom) * normalized) * radius,
    center.y + math.sin(angleFrom + (angleTo - angleFrom) * normalized) * radius)
  ui.drawCircleFilled(tip, 5, needleColor)
end

-- Radiating "speed lines" bursting from a point, fading out — the flourish
-- that fires once on a new personal best.
local function speedBurst(center, phase, color)
  local count = 10
  local innerRadius, outerRadius = 20 + phase * 10, 70 + phase * 90
  local alpha = 1 - phase
  for i = 1, count do
    local angle = (i / count) * math.pi * 2 + phase * 0.6
    local dir = vec2(math.cos(angle), math.sin(angle))
    local a = center + dir * innerRadius
    local b = center + dir * outerRadius
    ui.drawLine(a, b, withAlpha(color, alpha * 0.8), 3)
  end
end

function M.hudWindowSize(context)
  local panelHeight = context and M.hudSize(context) or 178
  if context and not context.session:isBusy() and context.session.resultAge >= 4 then
    panelHeight = 70
  end
  return hudWindowWidth, panelHeight + hudWindowTopPadding + hudWindowBottomPadding
end

function M.hudSize(context)
  if context.session.state == 'result' then return hudWindowWidth, 178 end
  if context.session.state == 'running' then return hudWindowWidth, 108 end
  return hudWindowWidth, 96
end

function M.hud(context, windowMode)
  local session = context.session
  if not session:isBusy() and session.resultAge >= 4 then
    if not windowMode then return end
    local width, height = hudWindowWidth, 70
    local p1 = vec2(0, hudWindowTopPadding)
    local p2 = p1 + vec2(width, height)
    fill(p1, p2, BRAND.panelBg, 4)
    accentStripe(p1, vec2(p1.x, p2.y), BRAND.accent)
    cornerWedge(vec2(p2.x, p1.y), 18, BRAND.accent2)
    text('HUD', 18, p1 + vec2(24, 12), BRAND.accent)
    text('Aparece durante a contagem decrescente, runs e resultados.', 13,
      p1 + vec2(24, 40), BRAND.muted)
    return
  end
  local sim = ac.getSim()
  local width, height = M.hudSize(context)
  local p1 = windowMode
    and vec2(0, hudWindowTopPadding)
    or vec2(sim.windowWidth * 0.5 - width * 0.5, sim.windowHeight - height - 36)
  local p2 = p1 + vec2(width, height)
  local result = context.lastResult
  local accent = result and not result.valid and BRAND.accent2 or BRAND.accent
  fill(p1, p2, BRAND.panelBg, 4)
  accentStripe(p1, vec2(p1.x, p2.y), accent)
  cornerWedge(vec2(p2.x, p1.y), 18, accent)

  if session.state == 'countdown' then
    local center = vec2(p1.x + width * 0.5, p1.y + height * 0.58)
    -- countdownRemaining decreases, so its fractional part runs 1 -> 0 each
    -- second; inverted so the ring starts small and expands/fades instead.
    local phase = 1 - (session.countdownRemaining - math.floor(session.countdownRemaining))
    pulseRing(center, 34, phase, accent)
    pulseRing(center, 34, (phase + 0.5) % 1, accent)
    text('PREPARA-TE', 18, p1 + vec2(24, 12), accent)
    text(tostring(math.max(1, math.ceil(session.countdownRemaining))), 52,
      vec2(center.x - 16, center.y - 30), BRAND.text)
    if session.penalties > 0 then
      text('PENALIZAÇÃO DE PARTIDA ANTECIPADA', 13, p1 + vec2(24, height - 24), BRAND.accent2)
    end
  elseif session.state == 'running' then
    local sample = session.samples[#session.samples]
    text('RUN A SOLO', 18, p1 + vec2(24, 12), accent)
    text(string.format('%.1fs', session.runElapsed), 18, p2 - vec2(70, height - 14), BRAND.muted)
    if sample then
      text(string.format('%.0f°', sample.angleDeg), 34, p1 + vec2(24, 42), BRAND.text)
      text('ÂNGULO', 12, p1 + vec2(24, 82), BRAND.muted)
      text(string.format('%.0f', sample.speedKmh), 34, p1 + vec2(150, 42), BRAND.text)
      text('KM/H', 12, p1 + vec2(150, 82), BRAND.muted)
      angleGauge(vec2(p2.x - 66, p1.y + 66), 40, sample.angleDeg, 90,
        context.scoring.targetAngleDeg, rgbm(1, 1, 1, 0.12))
      local barY = p2.y - 8
      fill(vec2(p1.x + 24, barY), vec2(p2.x - 24, barY + 4), rgbm(1, 1, 1, 0.12), 2)
      fill(vec2(p1.x + 24, barY),
        vec2(p1.x + 24 + (width - 48) * U.clamp(sample.progress.normalized, 0, 1), barY + 4), accent, 2)
    end
  elseif result then
    local isPb = result.personalBest and session.resultAge < 0.8
    if isPb then
      local phase = U.clamp(session.resultAge / 0.8, 0, 1)
      fill(p1, p2, withAlpha(BRAND.accent, (1 - phase) * 0.18), 4)
      speedBurst(vec2(p1.x + 96, p1.y + 78), phase, BRAND.accent)
    end
    text(result.personalBest and 'NOVO RECORDE PESSOAL' or (result.valid and 'RESULTADO DA RUN' or 'RUN INVÁLIDA'),
      16, p1 + vec2(24, 12), accent)
    text(string.format('%.0f', result.score or 0), 64, p1 + vec2(20, 30), BRAND.text)
    text('PTS', 16, p1 + vec2(20, 100), BRAND.muted)
    fill(vec2(p1.x + 22, p1.y + 96), vec2(p1.x + 90, p1.y + 100), accent, 0)
    text(string.format('LINHA %.0f', result.line or 0), 14, p1 + vec2(200, 36), BRAND.muted)
    text(string.format('ÂNGULO %.0f', result.angle or 0), 14, p1 + vec2(200, 58), BRAND.muted)
    text(string.format('ESTILO %.0f', result.styleSpeed or 0), 14, p1 + vec2(200, 80), BRAND.muted)
    text(result.valid and string.format('Média %.1f° / %.0f km/h',
      result.averageAngle or 0, result.averageSpeed or 0) or tostring(result.reason),
      13, p1 + vec2(24, height - 28), BRAND.muted)
  end
end

return M
