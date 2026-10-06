local source = debug.getinfo(1, 'S').source
local root = source and source:match('^@(.+[/\\])') or ''
if root ~= '' then
  package.path = root .. '?.lua;' .. root .. '?/init.lua;' .. root .. 'src/?.lua;' .. package.path
end

local U = require('src.util')
local Storage = require('src.storage')
local Context = require('src.context')
local Draw = require('src.draw')
local UI = require('src.ui_app')

-- A server that delivers the Drift Factory online script already gives
-- every player the judge; running this installed copy as well would draw a
-- second HUD and report every run twice. Detected from the server's CSP
-- extra options, which name the script's URL.
local function serverProvidesJudge()
  local sim = ac.getSim()
  if not (sim and sim.isOnlineRace) or not ac.INIConfig or not ac.INIConfig.onlineExtras then return false end
  local ok, config = pcall(ac.INIConfig.onlineExtras)
  if not ok or not config or not config.sections then return false end
  for name, section in pairs(config.sections) do
    if tostring(name):upper():find('^SCRIPT') then
      local script = section.SCRIPT and section.SCRIPT[1] or ''
      if tostring(script):lower():find('drift-jury', 1, true) then return true end
    end
  end
  return false
end

local context = Context.new({
  createStorage = function(track, layoutID, carID) return Storage.new(track, layoutID, carID, root) end
})
local serverJudge = serverProvidesJudge()
local adminCheckCountdown = 0
local hudWindow = nil
local hudAutoOpened = false
local hudActiveShowing = false
local hudPendingPlacement = false
local hudLastPosition = nil
local hudMoveIgnoreFrames = 0
local hudSettingsDirty = false
local hudSettingsSaveDelay = 0

local function cloneVec2(value)
  if not value then return nil end
  return vec2(value.x or 0, value.y or 0)
end

local function positionsDiffer(a, b)
  if not a or not b then return true end
  return math.abs((a.x or 0) - (b.x or 0)) > 2
    or math.abs((a.y or 0) - (b.y or 0)) > 2
end

local function readHudPosition()
  if not hudWindow or not hudWindow:valid() then return nil end
  local ok, position = pcall(function() return hudWindow:position() end)
  return ok and position and cloneVec2(position) or nil
end

local function savedHudPosition()
  local hud = type(context.hudSettings) == 'table' and context.hudSettings.hud or nil
  if type(hud) ~= 'table' then return nil end
  local x, y = tonumber(hud.x), tonumber(hud.y)
  if not x or not y then return nil end
  return vec2(x, y)
end

local function clampHudPosition(position, width, height)
  local sim = ac.getSim()
  local margin = 24
  return vec2(
    U.clamp(position.x, 0, math.max(0, sim.windowWidth - width)),
    U.clamp(position.y, margin, math.max(margin, sim.windowHeight - height)))
end

local function defaultHudPosition(width, height)
  local sim = ac.getSim()
  return clampHudPosition(vec2(
    sim.windowWidth * 0.5 - width * 0.5,
    sim.windowHeight - height - 36), width, height)
end

local function markHudPosition(position, width, height)
  if not width or not height then return end
  if type(context.hudSettings) ~= 'table' then context.hudSettings = { version = 1 } end
  position = clampHudPosition(position, width, height)
  context.hudSettings.hud = {
    x = U.round(position.x),
    y = U.round(position.y)
  }
  hudSettingsDirty = true
  hudSettingsSaveDelay = 0.45
end

local function flushHudSettings(dt, force)
  if not hudSettingsDirty then return end
  hudSettingsSaveDelay = force and 0 or hudSettingsSaveDelay - (tonumber(dt) or 0)
  if hudSettingsSaveDelay > 0 then return end
  local ok, err = context.storage:saveHudSettings(context.hudSettings)
  hudSettingsDirty = not ok
  if not ok then context.status = 'Falha ao guardar a posição do HUD: ' .. tostring(err) end
end

local function findHudWindow()
  local candidates = {
    'IMGUI_LUA_DriftFactoryJudgeApp_hud',
    'IMGUI_LUA_Drift Factory Judge App_hud'
  }
  for _, name in ipairs(candidates) do
    local window = ac.accessAppWindow(name)
    if window and window:valid() then return window end
  end
  for _, info in ipairs(ac.getAppWindows() or {}) do
    local name = tostring(info.name or '')
    local title = tostring(info.title or '')
    if title == 'Drift Factory Judge App HUD'
      or name:lower():find('driftfactoryjudgeapp_hud', 1, true)
      or name:lower():find('drift factory judge app_hud', 1, true) then
      local window = ac.accessAppWindow(name)
      if window and window:valid() then return window end
    end
  end
  return nil
end

local function sizeHudWindow()
  if not hudWindow or not hudWindow:valid() then
    hudWindow = findHudWindow()
  end
  if hudWindow and hudWindow:valid() then
    local width, height = Draw.hudWindowSize(context)
    hudWindow:resize(vec2(width, height))
    return width, height
  end
  return nil, nil
end

local function moveHudWindow(position, width, height)
  if not hudWindow or not hudWindow:valid() then
    hudWindow = findHudWindow()
  end
  if hudWindow and hudWindow:valid() then
    local target = clampHudPosition(position, width, height)
    hudWindow:move(target)
    hudLastPosition = cloneVec2(target)
    hudMoveIgnoreFrames = 3
  end
end

local function placeHudWindow(width, height)
  local saved = savedHudPosition()
  if saved then
    moveHudWindow(saved, width, height)
    return
  end

  local current = readHudPosition()
  if current and (math.abs(current.x) > 4 or math.abs(current.y) > 4) then
    local clamped = clampHudPosition(current, width, height)
    if positionsDiffer(current, clamped) then
      moveHudWindow(clamped, width, height)
    else
      hudLastPosition = cloneVec2(current)
    end
    markHudPosition(clamped, width, height)
    return
  end

  moveHudWindow(defaultHudPosition(width, height), width, height)
end

local function observeHudWindow(dt, width, height)
  if not hudWindow or not hudWindow:valid() then return end
  local position = readHudPosition()
  if position and positionsDiffer(position, hudLastPosition) then
    if hudMoveIgnoreFrames <= 0 then
      markHudPosition(position, width, height)
      hudLastPosition = cloneVec2(position)
    else
      hudLastPosition = cloneVec2(position)
    end
  elseif position then
    hudLastPosition = cloneVec2(position)
  end
  if hudMoveIgnoreFrames > 0 then hudMoveIgnoreFrames = hudMoveIgnoreFrames - 1 end
  flushHudSettings(dt, false)
end

local function hudVisible()
  if not hudWindow or not hudWindow:valid() then
    hudWindow = findHudWindow()
  end
  if not hudWindow or not hudWindow:valid() then return false end
  return hudWindow:visible()
end

local function updateHudWindow(dt)
  local show = context.session:isBusy() or context.session.resultAge < 4
  if not show then
    if hudAutoOpened then
      ac.setWindowOpen('hud', false)
      hudAutoOpened = false
      hudActiveShowing = false
      hudPendingPlacement = false
      flushHudSettings(dt, true)
      return
    end
    if not hudWindow or not hudWindow:valid() then
      hudWindow = findHudWindow()
    end
    if hudWindow and hudWindow:valid() and hudWindow:visible() then
      local width, height = sizeHudWindow()
      observeHudWindow(dt, width, height)
    else
      flushHudSettings(dt, false)
    end
    hudActiveShowing = false
    return
  end

  local wasVisible = hudVisible()
  if not hudActiveShowing then
    hudAutoOpened = not wasVisible
    hudPendingPlacement = not wasVisible
  end
  hudActiveShowing = true
  ac.setWindowOpen('hud', true)
  local width, height = sizeHudWindow()
  if width and height then
    if hudPendingPlacement then
      placeHudWindow(width, height)
      hudPendingPlacement = false
    end
    observeHudWindow(dt, width, height)
  end
end

-- Refreshes ac.getSim().isAdmin, which follows the server's own admin
-- sign-up rather than an app-level allowlist. Re-checked periodically while
-- online and not yet admin, so signing in as admin after the app has
-- loaded still unlocks the editing tabs.
local function refreshAdmin(dt)
  adminCheckCountdown = adminCheckCountdown - dt
  if adminCheckCountdown > 0 then return end
  adminCheckCountdown = 10
  local sim = ac.getSim()
  if ac.checkAdminPrivileges and sim and sim.isOnlineRace and not sim.isAdmin then
    ac.checkAdminPrivileges()
  end
end

function worldUpdate(dt)
  if serverJudge then return end
  dt = tonumber(dt) or 0
  refreshAdmin(dt)
  context:applyPendingOfficialLayout()
  context.session:update(dt)
  updateHudWindow(dt)
end

function draw3D()
  if serverJudge then return end
  context.editor:update3D()
  Draw.layout(context)
end

function windowMain()
  if serverJudge then
    ui.textWrapped('Este servidor já entrega a Drift Factory Judge App a todos os jogadores. '
      .. 'Usa a versão do servidor: abre-a no menu de extras online do chat (ícone da lâmpada). '
      .. 'Esta cópia instalada fica desligada aqui para não contar as runs duas vezes.')
    return
  end
  UI.window(context)
end

function windowHud()
  if serverJudge then return end
  Draw.hud(context, true)
end
