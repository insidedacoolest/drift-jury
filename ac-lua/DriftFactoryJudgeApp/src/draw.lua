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

local hudWindowWidth = 300
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
  -- Start and finish are always drawn: every player needs them to find
  -- where a run begins and ends, including online players who never see
  -- the editor's debug toggle.
  if layout.leadStart then
    circle(layout.leadStart.position, layout.leadStart.radiusMeters, colors.start)
    label(layout.leadStart.position, 'PARTIDA', colors.start)
  end
  if layout.finishGate then drawFinish(layout.finishGate) end
  -- Zones and clips: in the editor's debug mode, or when the player turns
  -- on "Mostrar zonas e clips". The route and its nodes are editor-only.
  if not (editor.debug or context.showCourse) then return end
  if editor.debug then drawRoute(layout) end
  for zoneIndex, zone in ipairs(layout.outerZones) do
    if not editor.debug or editor:isOuterZoneVisible(zoneIndex) then
      for index, point in ipairs(zone.points) do
        line(point, zone.points[index % #zone.points + 1], colors.outer, 0.12)
        circle(point, 0.3, colors.outer)
        if index == 1 then label(point, 'EXTERIOR ' .. zoneIndex, colors.outer) end
      end
    end
  end
  for index, clip in ipairs(layout.innerClips) do
    if not editor.debug or editor:isInnerClipVisible(index) then
      circle(clip.position, clip.radiusMeters, colors.clip)
      label(clip.position, 'CLIP ' .. index, colors.clip)
      -- (kept as "CLIP" untranslated — common drift-scene loanword)
    end
  end
  if not editor.debug then return end
  for index, point in ipairs(editor.outerDraft) do
    circle(point, 0.35, colors.draft)
    if index > 1 then line(editor.outerDraft[index - 1], point, colors.draft, 0.15) end
  end
  if editor.mode ~= 'none' then
    local hit = editor:rayHit()
    if hit then circle(hit, editor.mode == 'clip' and editor.clipRadius or 0.55, colors.draft) end
  end
end

local function fill(p1, p2, color, rounding)
  ui.drawRectFilled(p1, p2, color, rounding or 5)
end

-- Brand typefaces (driftfactory.pt), shipped as TTFs in the app's fonts/
-- folder under the SIL Open Font License: Saira for titles and big numbers,
-- JetBrains Mono for small readouts so digits keep a fixed width. Built
-- lazily; if CSP can't build them, everything falls back to its default font.
local FONTS_DIR = './fonts'
local brandFonts = nil

-- The online script has no app folder: it downloads the fonts and points
-- here at the folder CSP unpacked them into.
function M.setFontsDir(dir)
  FONTS_DIR = dir
  brandFonts = nil
end

local function fontFor(role)
  if brandFonts == nil then
    brandFonts = false
    if ui.DWriteFont and ui.pushDWriteFont then
      local ok, result = pcall(function()
        local weight = ui.DWriteFont.Weight
        return {
          title = ui.DWriteFont('Saira', FONTS_DIR):weight(weight.SemiBold),
          number = ui.DWriteFont('Saira', FONTS_DIR):weight(weight.Bold),
          mono = ui.DWriteFont('JetBrains Mono', FONTS_DIR):weight(weight.Medium),
          monoBold = ui.DWriteFont('JetBrains Mono', FONTS_DIR):weight(weight.Bold),
        }
      end)
      if ok then brandFonts = result end
    end
  end
  return brandFonts and role and brandFonts[role] or nil
end

local function withFont(role, drawFn)
  local font = fontFor(role)
  if font then ui.pushDWriteFont(font) end
  drawFn()
  if font then ui.popDWriteFont() end
end

local function text(value, size, position, color, role)
  if ui.dwriteDrawText then
    withFont(role, function() ui.dwriteDrawText(value, size, position, color) end)
  else
    ui.setCursor(position)
    ui.textColored(value, color)
  end
end

-- Text placed inside a box with real alignment, so numbers and labels land
-- where the layout says instead of depending on font metrics. Falls back to
-- top-left placement on CSP builds without the clipped DWrite call.
local function textIn(value, size, boxMin, boxMax, hAlign, vAlign, color, role)
  if ui.dwriteDrawTextClipped and ui.Alignment then
    withFont(role, function()
      ui.dwriteDrawTextClipped(value, size, boxMin, boxMax,
        ui.Alignment[hAlign or 'Start'], ui.Alignment[vAlign or 'Center'], false, color)
    end)
  else
    text(value, size, boxMin, color, role)
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
-- `grow` bounds the expansion so the ring never leaves the panel.
local function pulseRing(center, baseRadius, grow, phase, color)
  ui.drawCircle(center, baseRadius + phase * grow, withAlpha(color, 1 - phase), 40, 2.5)
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

-- A fan of "speed lines" shooting out to the right of the score, fading out —
-- the flourish that fires once on a new personal best. The inner radius
-- keeps the lines clear of the number itself.
local function speedBurst(center, phase, color)
  local count = 5
  local innerRadius, outerRadius = 40 + phase * 6, 50 + phase * 14
  local alpha = 1 - phase
  for i = 1, count do
    local angle = -0.5 + (i - 1) / (count - 1) * 1.0
    local dir = vec2(math.cos(angle), math.sin(angle))
    local a = center + dir * innerRadius
    local b = center + dir * outerRadius
    ui.drawLine(a, b, withAlpha(color, alpha * 0.8), 3)
  end
end

-- Panel heights per state. The HUD only carries what a driver reads at a
-- glance: the count, angle and speed while driving, and the score (or why
-- the run was voided) at the end.
local hudHeights = { countdown = 76, running = 72, result = 100, idle = 92 }

function M.hudSize(context)
  local state = context.session.state
  return hudWindowWidth, hudHeights[state] or hudHeights.countdown
end

function M.hudWindowSize(context)
  local panelHeight = context and select(2, M.hudSize(context)) or hudHeights.result
  if context and not context.session:isBusy() and context.session.resultAge >= 4 then
    panelHeight = hudHeights.idle
  end
  return hudWindowWidth, panelHeight + hudWindowTopPadding + hudWindowBottomPadding
end

local function panel(p1, p2, accent)
  fill(p1, p2, BRAND.panelBg, 4)
  accentStripe(p1, vec2(p1.x, p2.y), accent)
  cornerWedge(vec2(p2.x, p1.y), 14, accent)
end

-- Between runs: what to do next (drive to the start, or honk once inside
-- it) and the rules that void a run, so a first-time player needs no menu.
local function guide(context, p1)
  local p2 = p1 + vec2(hudWindowWidth, hudHeights.idle)
  local layout = context.layout
  local start = layout.leadStart
  local ready = start ~= nil and layout.finishGate ~= nil and #(layout.pathWaypoints or {}) >= 2
  local car = ac.getCar(0)
  local distance = nil
  if ready and car then
    local dx, dz = car.position.x - start.position.x, car.position.z - start.position.z
    distance = math.sqrt(dx * dx + dz * dz) - (start.radiusMeters or 0)
  end
  local inside = distance ~= nil and distance <= 0

  panel(p1, p2, ready and BRAND.accent or BRAND.accent2)
  if not ready then
    -- No run is possible here, so the rules would only be noise.
    textIn('SEM LAYOUT NESTA PISTA', 15, p1 + vec2(20, 18), vec2(p2.x - 20, p1.y + 44), 'Start', 'Center', BRAND.accent2, 'title')
    textIn('O admin ainda não publicou o layout.', 11, p1 + vec2(20, 46), vec2(p2.x - 16, p1.y + 66),
      'Start', 'Center', BRAND.muted, 'mono')
    return
  elseif inside then
    local center = vec2(p2.x - 34, p1.y + 22)
    local phase = (os.clock and os.clock() or 0) % 1
    pulseRing(center, 7, 8, phase, BRAND.accent)
    ui.drawCircleFilled(center, 5, BRAND.accent)
    textIn('BUZINA PARA COMEÇAR', 15, p1 + vec2(20, 8), vec2(p2.x - 52, p1.y + 34), 'Start', 'Center', BRAND.accent, 'title')
  else
    textIn('VAI ATÉ À PARTIDA', 15, p1 + vec2(20, 8), vec2(p2.x - 90, p1.y + 34), 'Start', 'Center', BRAND.text, 'title')
    textIn(distance and string.format('%.0f m', math.max(0, distance)) or '', 15,
      vec2(p2.x - 90, p1.y + 8), vec2(p2.x - 18, p1.y + 34), 'End', 'Center', BRAND.accent, 'monoBold')
  end

  -- Rules that void a run.
  fill(vec2(p1.x + 20, p1.y + 40), vec2(p2.x - 16, p1.y + 41), rgbm(1, 1, 1, 0.08), 0)
  textIn('A RUN É INVÁLIDA SE', 9, p1 + vec2(20, 44), vec2(p2.x - 16, p1.y + 56), 'Start', 'Center', BRAND.muted, 'mono')
  textIn('Arrancar antes · Contramão · Endireitar', 10,
    p1 + vec2(20, 57), vec2(p2.x - 12, p1.y + 71), 'Start', 'Center', BRAND.text, 'mono')
  textIn('Sair da pista · Parar · Trompo', 10,
    p1 + vec2(20, 71), vec2(p2.x - 12, p1.y + 85), 'Start', 'Center', BRAND.text, 'mono')
end

function M.hud(context, windowMode)
  local session = context.session
  local sim = ac.getSim()
  if not session:isBusy() and session.resultAge >= 4 then
    guide(context, windowMode and vec2(0, hudWindowTopPadding)
      or vec2(sim.windowWidth * 0.5 - hudWindowWidth * 0.5, sim.windowHeight - hudHeights.idle - 40))
    return
  end

  local width, height = M.hudSize(context)
  local p1 = windowMode
    and vec2(0, hudWindowTopPadding)
    or vec2(sim.windowWidth * 0.5 - width * 0.5, sim.windowHeight - height - 40)
  local p2 = p1 + vec2(width, height)
  local result = context.lastResult
  local accent = session.state == 'result' and result and not result.valid and BRAND.accent2 or BRAND.accent
  panel(p1, p2, accent)

  if session.state == 'countdown' then
    -- Text left, count right inside its pulsing ring.
    local center = vec2(p2.x - 46, p1.y + height * 0.5)
    -- countdownRemaining decreases, so its fractional part runs 1 -> 0 each
    -- second; inverted so the ring starts small and expands/fades instead.
    local phase = 1 - (session.countdownRemaining - math.floor(session.countdownRemaining))
    pulseRing(center, 20, 12, phase, accent)
    pulseRing(center, 20, 12, (phase + 0.5) % 1, accent)
    ui.drawCircle(center, 20, withAlpha(BRAND.text, 0.25), 40, 1.5)
    textIn('PREPARA-TE', 20, p1 + vec2(20, 12), p1 + vec2(200, 40), 'Start', 'Center', accent, 'title')
    textIn('ARRANCAR ANTES INVALIDA', 11, p1 + vec2(20, 42), p1 + vec2(200, 60), 'Start', 'Center', BRAND.muted, 'mono')
    -- Box nudged up a little: DWrite centers the line box, and digits sit
    -- low inside it.
    textIn(tostring(math.max(1, math.ceil(session.countdownRemaining))), 30,
      center - vec2(26, 29), center + vec2(26, 23), 'Center', 'Center', BRAND.text, 'number')

  elseif session.state == 'running' then
    local sample = session.samples[#session.samples]
    if sample then
      -- Angle is the headline number; speed sits beside it; the gauge on the
      -- right turns from lime to magenta as the angle passes the target.
      textIn(string.format('%.0f°', sample.angleDeg), 38, p1 + vec2(20, 4), p1 + vec2(118, 52), 'Start', 'Center', BRAND.text, 'number')
      textIn('ÂNGULO', 10, p1 + vec2(21, 48), p1 + vec2(118, 62), 'Start', 'Center', BRAND.muted, 'mono')
      textIn(string.format('%.0f', sample.speedKmh), 26, p1 + vec2(128, 12), p1 + vec2(210, 48), 'Start', 'Center', BRAND.text, 'number')
      textIn('KM/H', 10, p1 + vec2(129, 48), p1 + vec2(210, 62), 'Start', 'Center', BRAND.muted, 'mono')
      angleGauge(vec2(p2.x - 44, p1.y + 34), 24, sample.angleDeg, 90,
        context.scoring.targetAngleDeg, rgbm(1, 1, 1, 0.12))
      -- Course progress along the bottom edge.
      local barY = p2.y - 5
      fill(vec2(p1.x + 16, barY), vec2(p2.x - 10, barY + 3), rgbm(1, 1, 1, 0.10), 2)
      fill(vec2(p1.x + 16, barY),
        vec2(p1.x + 16 + (width - 26) * U.clamp(sample.progress.normalized, 0, 1), barY + 3), accent, 2)
    end

  elseif result then
    if result.personalBest and session.resultAge < 0.8 then
      local phase = U.clamp(session.resultAge / 0.8, 0, 1)
      fill(p1, p2, withAlpha(BRAND.accent, (1 - phase) * 0.18), 4)
      speedBurst(vec2(p1.x + 52, p1.y + 60), phase, BRAND.accent)
    end
    textIn(result.personalBest and 'NOVO RECORDE' or (result.valid and 'RESULTADO' or 'RUN INVÁLIDA'),
      13, p1 + vec2(20, 6), p1 + vec2(220, 26), 'Start', 'Center', accent, 'title')
    textIn(string.format('%.0f', result.score or 0), 52, p1 + vec2(18, 26), p1 + vec2(130, 86), 'Start', 'Center', BRAND.text, 'number')
    textIn('PTS', 10, p1 + vec2(20, 82), p1 + vec2(80, 96), 'Start', 'Center', BRAND.muted, 'mono')
    if result.valid then
      -- Breakdown: name left, points / max right.
      local scoring = context.scoring or {}
      local rows = {
        { 'LINHA', result.line, scoring.leadLinePoints or 35 },
        { 'ÂNGULO', result.angle, scoring.leadAnglePoints or 35 },
        { 'ESTILO', result.styleSpeed, scoring.leadStyleSpeedPoints or 30 },
      }
      for index, row in ipairs(rows) do
        local top = p1.y + 30 + (index - 1) * 20
        textIn(row[1], 11, vec2(p1.x + 150, top), vec2(p1.x + 214, top + 18), 'Start', 'Center', BRAND.muted, 'title')
        textIn(string.format('%.0f/%d', row[2] or 0, row[3]), 12,
          vec2(p1.x + 210, top), vec2(p2.x - 16, top + 18), 'End', 'Center', BRAND.text, 'monoBold')
      end
    else
      -- Voided: the reason is what the driver needs.
      textIn(tostring(result.reason or ''), 15, p1 + vec2(140, 30), vec2(p2.x - 16, p1.y + 84),
        'Start', 'Center', BRAND.text, 'title')
    end
  end
end

-- Compact on-screen leaderboard: best run per driver this session on this
-- track. Shows the top rows; if the local driver is further down, the last
-- row is theirs, so they always see where they stand.
local leaderboardWidth, leaderboardMaxRows = 264, 8
local leaderboardHeader, leaderboardRow = 32, 20

M.windowTopPadding = hudWindowTopPadding

local function visibleLeaderboardRows(entries, ownName)
  local rows, ownIndex = {}, nil
  for index, entry in ipairs(entries) do
    if entry.name == ownName then ownIndex = index end
  end
  for index = 1, math.min(#entries, leaderboardMaxRows) do
    rows[#rows + 1] = { position = index, entry = entries[index] }
  end
  if ownIndex and ownIndex > leaderboardMaxRows then
    rows[#rows] = { position = ownIndex, entry = entries[ownIndex] }
  end
  return rows
end

function M.leaderboardSize(entries)
  local count = math.max(1, math.min(#entries, leaderboardMaxRows))
  return leaderboardWidth, leaderboardHeader + count * leaderboardRow + 10
end

---@param entries {name: string, score: number, valid: boolean}[] @Best first, from Leaderboard.entries().
---@param origin vec2 @Top-left corner of the panel.
function M.leaderboard(context, entries, origin)
  local width, height = M.leaderboardSize(entries)
  local p1, p2 = origin, origin + vec2(width, height)
  fill(p1, p2, BRAND.panelBg, 4)
  accentStripe(p1, vec2(p1.x, p2.y), BRAND.accent)
  textIn('CLASSIFICAÇÃO', 13, p1 + vec2(20, 6), p1 + vec2(140, 28), 'Start', 'Center', BRAND.accent, 'title')
  textIn(context.trackName or context.track or '', 11, p1 + vec2(140, 6), vec2(p2.x - 12, p1.y + 28),
    'End', 'Center', BRAND.muted, 'mono')

  if #entries == 0 then
    textIn('Ainda sem runs nesta sessão.', 12, p1 + vec2(20, leaderboardHeader),
      vec2(p2.x - 12, p1.y + leaderboardHeader + leaderboardRow), 'Start', 'Center', BRAND.muted, 'mono')
    return
  end

  local ownName = U.call(ac.getDriverName, nil, 0)
  for index, row in ipairs(visibleLeaderboardRows(entries, ownName)) do
    local top = p1.y + leaderboardHeader + (index - 1) * leaderboardRow
    local entry = row.entry
    if entry.name == ownName then
      fill(vec2(p1.x + 12, top), vec2(p2.x - 6, top + leaderboardRow), withAlpha(BRAND.accent, 0.12), 2)
    end
    textIn(tostring(row.position), 12, vec2(p1.x + 14, top), vec2(p1.x + 36, top + leaderboardRow),
      'End', 'Center', row.position == 1 and BRAND.accent or BRAND.muted, 'monoBold')
    textIn(entry.name, 13, vec2(p1.x + 46, top), vec2(p2.x - 74, top + leaderboardRow),
      'Start', 'Center', entry.valid and BRAND.text or BRAND.muted, 'title')
    textIn(entry.valid and string.format('%.1f', entry.score or 0) or '—', 13,
      vec2(p2.x - 72, top), vec2(p2.x - 14, top + leaderboardRow),
      'End', 'Center', entry.valid and BRAND.text or BRAND.accent2, 'monoBold')
  end
end

return M
