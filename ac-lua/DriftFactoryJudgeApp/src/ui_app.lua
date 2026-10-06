local U = require('src.util')
local G = require('src.geometry')
local Model = require('src.model')
local Profiles = require('src.profiles')
local M = {}

-- Palette pulled from driftfactory.pt (background/text/lime accent/magenta
-- accent), used for the leaderboard and score displays specifically.
local BRAND = {
  accent = rgbm(212 / 255, 255 / 255, 63 / 255, 1), -- lime
  accent2 = rgbm(255 / 255, 62 / 255, 200 / 255, 1), -- magenta, used for invalid/attention
  text = rgbm(243 / 255, 244 / 255, 239 / 255, 1), -- cream
  muted = rgbm(154 / 255, 160 / 255, 172 / 255, 1),
}

local function heading(value)
  ui.textColored(value, rgbm(0.25, 0.8, 1, 1))
  ui.separator()
end

local function muted(value)
  ui.textColored(value, rgbm(0.68, 0.72, 0.76, 1))
end

local function wrapped(value)
  if ui.textWrapped then ui.textWrapped(value) else ui.text(value) end
end

local function checkbox(label, value)
  local ok, changed = pcall(ui.checkbox, label, value)
  if ok and changed then return not value, true end
  return value, false
end

local function slider(label, value, minimum, maximum, format)
  local ok, result, changed = pcall(ui.slider, label, value, minimum, maximum, format)
  if ok and type(result) == 'number' then return result, changed end
  return value, false
end

local function sameLine()
  if ui.sameLine then ui.sameLine() end
end

local function scoreLine(label, value)
  ui.text(string.format('%-18s %6.1f', label, value or 0))
end

local function saveWarning(context, message)
  if not context.dirty then return end
  ui.textColored(message or 'ALTERAÇÕES NÃO GUARDADAS - clica em Guardar Layout Agora para as manter depois de recarregar.',
    rgbm(1, 0.18, 0.12, 1))
  if ui.button('Guardar Layout Agora') then context:saveLayout() end
end

local function environment(context)
  local sim = ac.getSim()
  if sim.isReplayActive then
    ui.textColored('Desativado em replay', rgbm(1, 0.3, 0.2, 1))
    return false
  end
  -- Online (or anywhere CSP withholds physics write access), the app can
  -- still judge a run, it just can't auto-align the car to the start line
  -- itself — see CREDITS.md.
  if sim.isOnlineRace or not physics.allowed() then
    ui.textColored('Online: alinhamento manual', rgbm(0.85, 0.75, 0.2, 1))
    wrapped('A app não consegue alinhar o carro automaticamente aqui — alinha-te tu mesmo na partida e depois buzina.')
  end
  return true
end

local function runTab(context)
  heading('Sessão Atual')
  ui.text('Pista: ' .. context.track .. ' / ' .. context.layoutID)
  ui.text('Carro: ' .. context.carID)
  local sourceLabels = {
    ['local'] = 'Layout local (edição)',
    official = 'Layout oficial',
    ['official-cached'] = 'Layout oficial (cópia guardada)',
    ['official-missing'] = 'Layout oficial indisponível',
  }
  muted(sourceLabels[context.layoutSource] or '')
  if context.layoutStatus then muted(context.layoutStatus) end
  local available = environment(context)
  local errors = Model.validateLayout(context.layout)
  if context.layoutSource == 'official-missing' then
    -- Not something the player can fix by editing — the track just hasn't
    -- been published yet (or the download hasn't finished).
    ui.newLine()
    ui.textColored('Ainda não há layout para esta pista.', rgbm(1, 0.65, 0.2, 1))
  elseif #errors > 0 then
    ui.newLine()
    ui.textColored('O layout não está pronto:', rgbm(1, 0.65, 0.2, 1))
    for _, errorMessage in ipairs(errors) do ui.bulletText(errorMessage) end
  elseif available then
    ui.newLine()
    ui.textColored('Pronto para uma run a solo', rgbm(0.2, 1, 0.35, 1))
    wrapped(physics.allowed()
      and 'Conduz até ao círculo verde de partida e buzina. A app alinha o carro e começa uma contagem decrescente de cinco segundos. Arrancar antes do zero invalida a run.'
      or 'Para dentro do círculo verde de partida, virado para o percurso, e buzina. Começa uma contagem decrescente de cinco segundos. Arrancar antes do zero invalida a run.')
    context.showCourse = select(1, checkbox('Mostrar zonas, clips e mapa de aceleração', context.showCourse))
    local car = ac.getCar(0)
    if car and context.layout.leadStart then
      local inside = G.insideCircle(
        U.fromVec3(car.position), context.layout.leadStart.position, context.layout.leadStart.radiusMeters)
      ui.textColored(inside and 'Na zona de partida' or 'Conduz até à zona de partida',
        inside and rgbm(0.2, 1, 0.35, 1) or rgbm(0.85, 0.85, 0.85, 1))
    end
  end
  if context.session:isBusy() and ui.button('Cancelar Run Atual') then
    context.session:cancel('Run cancelada pelo jogador.')
  end

  ui.newLine()
  heading('Objetivos de Pontuação')
  scoreLine('Velocidade alvo', context.scoring.targetSpeedKmh)
  scoreLine('Ângulo alvo', context.scoring.targetAngleDeg)
  scoreLine('Ângulo mínimo', context.scoring.minimumAngleDeg)
  scoreLine('Ângulo de estilo (início)', context.scoring.styleMinimumDriftAngleDeg)
  scoreLine('Ângulo de estilo (total)', context.scoring.styleFullDriftAngleDeg)

  ui.newLine()
  heading('Classificação')
  local showLeaderboard, leaderboardChanged = checkbox('Mostrar a classificação no ecrã', context.showLeaderboard)
  if leaderboardChanged then context:setShowLeaderboard(showLeaderboard) end
  muted('Melhor run de cada piloto nesta sessão, no canto do ecrã.')
  muted('Partilhada entre jogadores, não validada pelo servidor.')

  ui.newLine()
  heading('Pontuação (Drift Masters 2026)')
  ui.bulletText('Linha 60: zonas exteriores e clips, cada um vale o mesmo')
  ui.bulletText('Ângulo 20: ângulo alto e mantido nas zonas julgadas')
  ui.bulletText('Estilo 20: iniciação 5 · fluidez 10 · compromisso 5')
  if #context.layout.speedZones > 0 then
    ui.bulletText('Cumprir o mapa de aceleração vale 30% da fluidez')
  end

  ui.newLine()
  heading('Deduções')
  ui.bulletText('Toque num muro ou carro: -5 · -10 (perdes 5 km/h) · -20 (15 km/h)')
  ui.bulletText('Roda fora da pista (1 ou 2 rodas): -5')
  ui.bulletText('Endireitar por instantes (correção): -5')
  ui.bulletText('Travar a fundo ou travão de mão numa zona verde: -5')
  ui.bulletText('Dupla iniciação: 0 pontos de iniciação')
  muted('Zonas e clips falhados, fora da linha e falta de ângulo saem da própria pontuação.')

  ui.newLine()
  heading('Mapa de Aceleração')
  if #context.layout.speedZones == 0 then
    muted('Esta pista ainda não tem mapa de aceleração.')
  else
    ui.textColored('Verde: acelera ou mantém a velocidade, sem travar', rgbm(0.15, 1, 0.3, 1))
    ui.textColored('Laranja: acelerador parcial ou pequeno ajuste, sem travar a fundo', rgbm(1, 0.55, 0.05, 1))
    ui.textColored('Vermelha: podes abrandar com travão, travão de mão ou a soltar', rgbm(1, 0.25, 0.25, 1))
    muted('Liga "Mostrar zonas, clips e mapa de aceleração" para as veres na pista.')
  end

  ui.newLine()
  heading('A Run Fica Incompleta Se')
  ui.bulletText('Arrancares antes do fim da contagem')
  ui.bulletText('Fizeres um trompo')
  ui.bulletText('Deixares de derrapar (1 s direito)')
  ui.bulletText('Saíres com três rodas da pista')
  ui.bulletText('Andares no sentido contrário ou parares o carro')

  ui.newLine()
  heading('Recorde Pessoal')
  if context.results.personalBest then
    local best = context.results.personalBest
    ui.textColored(string.format('%.1f pontos', best.score), BRAND.accent)
    muted(U.formatDate(best.dateUtc))
    scoreLine('Linha', best.line)
    scoreLine('Ângulo', best.angle)
    scoreLine('Estilo', best.styleSpeed)
  else
    muted('Ainda sem recorde pessoal válido.')
  end
end

local function editorTab(context)
  local editor, layout = context.editor, context.layout
  editor.debug = select(1, checkbox('Modo de Depuração', editor.debug))

  ui.newLine()
  heading('Ficheiro de Layout')
  ui.text(context.dirty and '* Alterações não guardadas' or 'Guardado')
  if ui.button('Guardar Layout') then context:saveLayout() end
  sameLine()
  if ui.button('Reverter') then context:reloadLayout() end
  sameLine()
  if ui.button('Desfazer') then editor:undoLast() end
  if ui.button('Importar JSON') then
    context.storage:importLayout(function(ok, value)
      if ok then
        context.layout = value
        context.dirty = true
        context:refreshScoring()
        context.status = 'Layout importado. Guarda para o manter na biblioteca local.'
      else
        context.status = tostring(value)
      end
    end)
  end
  sameLine()
  if ui.button('Exportar JSON') then
    context.storage:exportLayout(layout, function(_, message) context.status = tostring(message) end)
  end

  if context.session:isBusy() or context.calibration.active then
    ui.newLine()
    ui.textColored('A edição está desativada durante uma run ou sessão de calibração.', rgbm(1, 0.65, 0.2, 1))
    return
  end

  ui.newLine()
  heading('Partida e Chegada')
  editor.startRadius = select(1, slider('Raio de partida', editor.startRadius, 1, 10, '%.1f m'))
  if ui.button('Capturar Partida') then editor:captureLeadStart() end
  if layout.leadStart then
    sameLine()
    if ui.button('Aplicar Raio de Partida') then
      editor:pushUndo()
      layout.leadStart.radiusMeters = editor.startRadius
      editor:changed('Raio de partida atualizado.')
    end
  end
  editor.finishWidth = select(1, slider('Largura da chegada', editor.finishWidth, 4, 30, '%.1f m'))
  if ui.button('Capturar Gate de Chegada') then editor:captureFinish() end

  ui.newLine()
  heading('Rota')
  if ui.button(editor.recording and 'Parar Gravação' or 'Gravar Rota') then editor:toggleRecording() end
  sameLine()
  if ui.button(editor.mode == 'route' and 'Parar Edição da Rota' or 'Editar Rota') then editor:setMode('route') end
  sameLine()
  if ui.button('Limpar Rota') then editor:clearRoute() end
  editor.routeSmoothRadius = select(1, slider('Raio de suavização', editor.routeSmoothRadius, 5, 30, '%.1f m'))
  local width, widthChanged = slider(
    'Meia-largura da rota', layout.pathCorridorHalfWidthMeters, 1, 10, '%.1f m')
  if widthChanged then
    editor:pushUndo()
    layout.pathCorridorHalfWidthMeters = width
    editor:changed('Largura da rota atualizada.')
  end
  muted(string.format('%d pontos de rota. Ctrl+click insere; arrastar move; Shift+arrastar suaviza; botão direito remove.',
    #layout.pathWaypoints))

  ui.newLine()
  heading('Zonas Exteriores')
  if ui.button(editor.mode == 'outer' and 'Parar Ferramenta Exterior' or 'Desenhar / Editar Exterior') then editor:setMode('outer') end
  sameLine()
  if ui.button('Terminar Rascunho') then editor:finishOuter() end
  sameLine()
  if ui.button('Cancelar Rascunho') then editor:cancelOuter() end
  muted(string.format('%d zonas, %d pontos em rascunho. Ctrl+click coloca ou insere pontos.',
    #layout.outerZones, #editor.outerDraft))

  ui.newLine()
  heading('Clips Interiores')
  editor.clipRadius = select(1, slider('Raio do clip', editor.clipRadius, 0.5, 8, '%.1f m'))
  if ui.button(editor.mode == 'clip' and 'Parar Ferramenta de Clips' or 'Colocar / Remover Clips') then editor:setMode('clip') end
  muted(string.format('%d clips. Ctrl+click coloca; botão direito remove.', #layout.innerClips))

  ui.newLine()
  heading('Mapa de Aceleração')
  local kinds = { 'green', 'orange', 'red' }
  for index, kind in ipairs(kinds) do
    local name = editor.speedKindNames[kind]
    if ui.button((editor.speedKind == kind and '* ' or '') .. name .. '##speedKind' .. kind) then
      editor.speedKind = kind
    end
    if index < #kinds then sameLine() end
  end
  if ui.button(editor.mode == 'speed' and 'Parar Ferramenta do Mapa' or 'Desenhar / Editar Mapa') then editor:setMode('speed') end
  sameLine()
  if ui.button(editor.speedDraft and 'Fim da Zona no Carro' or 'Início da Zona no Carro') then editor:markSpeedPointAtCar() end
  if editor.speedDraft then
    sameLine()
    if ui.button('Cancelar Zona') then editor:cancelSpeedDraft() end
  end
  sameLine()
  if ui.button('Limpar Mapa') then editor:clearSpeedZones() end
  local counts = { green = 0, orange = 0, red = 0 }
  for _, zone in ipairs(layout.speedZones) do counts[zone.kind] = counts[zone.kind] + 1 end
  muted(string.format('%d verdes, %d laranja, %d vermelhas. Ctrl+click marca o início e depois o fim; arrastar move uma ponta; botão direito na zona remove-a.',
    counts.green, counts.orange, counts.red))
  muted('Também podes conduzir e carregar em Início/Fim da Zona no Carro.')

  ui.newLine()
  heading('Visibilidade do Editor')
  wrapped('Zonas e clips desmarcados ficam escondidos e não podem ser selecionados. Isto afeta só a tua vista no editor.')
  if #layout.outerZones > 0 then
    ui.text('Zonas exteriores')
    for index = 1, #layout.outerZones do
      local visible, changed = checkbox(
        'Exterior ' .. tostring(index) .. '##outerVisibility' .. tostring(index),
        editor:isOuterZoneVisible(index))
      if changed then editor:setOuterZoneVisible(index, visible) end
      if index % 3 ~= 0 and index < #layout.outerZones then sameLine() end
    end
  end
  if #layout.innerClips > 0 then
    ui.text('Clips interiores')
    for index = 1, #layout.innerClips do
      local visible, changed = checkbox(
        'Clip ' .. tostring(index) .. '##clipVisibility' .. tostring(index),
        editor:isInnerClipVisible(index))
      if changed then editor:setInnerClipVisible(index, visible) end
      if index % 3 ~= 0 and index < #layout.innerClips then sameLine() end
    end
  end
end

local labels = {
  targetSpeedKmh = 'Velocidade alvo',
  targetAngleDeg = 'Ângulo alvo',
  minimumAngleDeg = 'Ângulo mínimo',
  styleMinimumDriftAngleDeg = 'Ângulo mínimo de estilo',
  styleFullDriftAngleDeg = 'Ângulo total de estilo'
}

local ranges = {
  targetSpeedKmh = { 20, 250, '%.0f km/h' },
  targetAngleDeg = { 20, 100, '%.0f deg' },
  minimumAngleDeg = { 0, 80, '%.0f deg' },
  styleMinimumDriftAngleDeg = { 0, 80, '%.0f deg' },
  styleFullDriftAngleDeg = { 5, 100, '%.0f deg' }
}

local function selectedProfileTarget(context)
  local packPattern, packName = Profiles.detectPackPattern(context.carID)
  if context.profileScope ~= 'exact' and context.profileScope ~= 'pack' then
    context.profileScope = packPattern and 'pack' or 'exact'
  elseif context.profileScope == 'pack' and not packPattern then
    context.profileScope = 'exact'
  end
  if context.profileScope == 'pack' and packPattern then
    return {
      scope = 'pack',
      pattern = packPattern,
      name = packName,
      heading = 'Perfil de Pack',
      description = 'Aplica-se a todos os carros que correspondam a ' .. packPattern .. '.'
    }
  end
  return {
    scope = 'exact',
    pattern = context.carID,
    name = context.carID,
    heading = 'Perfil Exato do Carro',
    description = 'Aplica-se só a este carro exato.'
  }
end

local function setProfileOverride(context, target, field, value)
  Profiles.setOverrideForPattern(context.layout, target.pattern, target.name, field, value)
  context.dirty = true
  context:refreshScoring()
end

local function applyRecommendation(context, pattern, name, recommendation)
  for _, field in ipairs(Profiles.overrideFields) do
    Profiles.setOverrideForPattern(context.layout, pattern, name, field, recommendation[field])
  end
  context.dirty = true
  context:refreshScoring()
end

local function carSetupTab(context)
  heading('Âmbito do Perfil')
  ui.text(context.carID)
  local packPattern, packName = Profiles.detectPackPattern(context.carID)
  if packPattern then
    if ui.button((context.profileScope == 'pack' and '* ' or '') .. 'Editar Pack ' .. packPattern) then
      context.profileScope = 'pack'
    end
    sameLine()
  else
    muted('Nenhum prefixo de pack detetado. IDs de carro como VDC_* ou SWARM_* podem usar perfis de pack.')
  end
  if ui.button((context.profileScope == 'exact' and '* ' or '') .. 'Editar Carro Exato') then
    context.profileScope = 'exact'
  end

  local target = selectedProfileTarget(context)
  ui.newLine()
  heading(target.heading)
  ui.text(target.pattern)
  muted(target.description)
  saveWarning(context, 'ALTERAÇÕES DE OVERRIDE NÃO GUARDADAS - clica em Guardar Layout Agora para manter/aplicar este perfil depois de recarregar.')
  local profile = Profiles.findPattern(context.layout, target.pattern)
  if not profile then
    muted('Ainda sem overrides guardados para este âmbito. Ativar um cria o perfil.')
  end
  local inherited = Profiles.resolveInherited(context.layout, context.carID, target.pattern)
  for _, field in ipairs(Profiles.overrideFields) do
    profile = Profiles.findPattern(context.layout, target.pattern)
    local active = profile and profile.overrides[field] ~= nil or false
    local newActive, changed = checkbox('Substituir ' .. labels[field], active)
    if changed then
      if newActive then
        setProfileOverride(context, target, field, inherited[field])
      else
        setProfileOverride(context, target, field, nil)
      end
      profile = Profiles.findPattern(context.layout, target.pattern)
      inherited = Profiles.resolveInherited(context.layout, context.carID, target.pattern)
    end
    local value = newActive and profile and profile.overrides[field] or inherited[field]
    if newActive then
      local range = ranges[field]
      local newValue, valueChanged = slider(labels[field] .. '##' .. field, value, range[1], range[2], range[3])
      if valueChanged then
        setProfileOverride(context, target, field, newValue)
      end
    else
      muted(string.format('%s herdado: %.1f', labels[field], inherited[field]))
    end
  end
  local ok, errorMessage = Profiles.validate(context.scoring)
  if not ok then ui.textColored(errorMessage, rgbm(1, 0.3, 0.2, 1)) end
end

local function calibrationTab(context)
  local calibration = context.calibration
  heading('Calibração de Cinco Runs')
  wrapped('A calibração usa cinco runs válidas e cria recomendações a partir das três melhores. As tentativas não são adicionadas ao histórico normal.')
  if not calibration.active then
    if ui.button('Iniciar Calibração') then
      calibration:start()
      context.status = 'Calibração iniciada. Completa cinco runs válidas.'
    end
  else
    ui.text(string.format('Runs válidas: %d / 5', #calibration.validRuns))
    ui.text(string.format('Tentativas: %d', #calibration.attempts))
    if ui.button('Reiniciar Calibração') then
      context.session:cancel('Run de calibração cancelada.')
      calibration:start()
    end
    sameLine()
    if ui.button('Cancelar Calibração') then
      context.session:cancel('Run de calibração cancelada.')
      calibration:cancel()
    end
  end
  if calibration.recommendation then
    ui.newLine()
    heading('Recomendação')
    local recommendation = calibration.recommendation
    scoreLine('Velocidade alvo', recommendation.targetSpeedKmh)
    scoreLine('Ângulo alvo', recommendation.targetAngleDeg)
    scoreLine('Ângulo mínimo', recommendation.minimumAngleDeg)
    scoreLine('Mínimo de estilo', recommendation.styleMinimumDriftAngleDeg)
    scoreLine('Total de estilo', recommendation.styleFullDriftAngleDeg)
    local packPattern, packName = Profiles.detectPackPattern(context.carID)
    if packPattern and ui.button('Aplicar ao Pack ' .. packPattern) then
      applyRecommendation(context, packPattern, packName, recommendation)
      calibration:cancel()
      context.status = 'Calibração aplicada a ' .. packPattern .. '. Guarda o layout para a manter.'
    end
    if packPattern then sameLine() end
    if ui.button('Aplicar ao Carro Atual') then
      applyRecommendation(context, context.carID, context.carID, recommendation)
      calibration:cancel()
      context.status = 'Calibração aplicada ao perfil do carro atual. Guarda o layout para a manter.'
    end
    sameLine()
    if ui.button('Rejeitar Recomendação') then calibration:cancel() end
  end
end

local function resultsTab(context)
  heading('Resultados Locais')
  if context.results.personalBest then
    ui.textColored(string.format('PB %.1f pontos', context.results.personalBest.score), BRAND.accent)
  else
    muted('Sem recorde pessoal.')
  end
  sameLine()
  if ui.button('Limpar Resultados') then
    local ok, err = context.storage:clearResults(context.results)
    context.status = ok and 'Resultados limpos.' or tostring(err)
  end
  ui.separator()
  if #context.results.runs == 0 then muted('Ainda sem runs completas.') return end
  for index, run in ipairs(context.results.runs) do
    local title = string.format('#%d  %s  %.1f pts  %s',
      index, run.valid and 'VÁLIDA' or 'INVÁLIDA', run.score or 0, U.formatDate(run.dateUtc))
    ui.treeNode(title, function()
      ui.text('Motivo: ' .. tostring(run.reason))
      scoreLine('Linha', run.line)
      scoreLine('Ângulo', run.angle)
      scoreLine('Estilo', run.styleSpeed)
      scoreLine('Ângulo médio', run.averageAngle)
      scoreLine('Velocidade média', run.averageSpeed)
      scoreLine('Qualidade da rota', run.pathQuality)
      scoreLine('Qualidade da zona', run.zoneQuality)
      scoreLine('Qualidade do clip', run.clipQuality)
      if run.mapQuality then scoreLine('Mapa de aceleração', run.mapQuality) end
    end)
  end
end

function M.window(context)
  local sim = ac.getSim()
  local isAdmin = sim and sim.isAdmin == true
  -- Everything that changes what a run is judged against (layout, scoring
  -- targets, calibration) is admin-only once online — otherwise any player
  -- could lower their own targets and inflate what they broadcast to the
  -- shared leaderboard. Offline there's no one else to restrict.
  -- The server-delivered version can't save files, so editing stays in the
  -- installed app regardless of admin status.
  local canEdit = not context.editingDisabled and (isAdmin or not (sim and sim.isOnlineRace))

  ui.textColored('Drift Factory Judge App', rgbm(0.25, 0.8, 1, 1))
  sameLine()
  muted('v0.4.0')
  if isAdmin then
    sameLine()
    ui.textColored('ADMIN', BRAND.accent)
  end
  muted('Modificado, não oficial — baseado em DriftJudging SP')
  muted('por DeadEndReece (AGPL-3.0). Código, créditos e licença:')
  muted('github.com/insidedacoolest/drift-jury')
  if context.status and context.status ~= '' then
    ui.textWrapped(context.status)
    ui.separator()
  end
  if canEdit then
    saveWarning(context)
    if context.dirty then ui.separator() end
  end
  ui.tabBar('DriftFactoryJudgeAppTabs', function()
    ui.tabItem('Corrida', function() runTab(context) end)
    if canEdit then
      ui.tabItem('Editor de Layout', function() editorTab(context) end)
      ui.tabItem('Configuração do Carro', function() carSetupTab(context) end)
      ui.tabItem('Calibração', function() calibrationTab(context) end)
    end
    ui.tabItem('Resultados', function() resultsTab(context) end)
  end)
end

return M
