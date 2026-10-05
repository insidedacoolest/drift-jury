local source = debug.getinfo(1, 'S').source
local root = source and source:match('^@(.+[/\\])') or ''
if root ~= '' then
  package.path = root .. '?.lua;' .. root .. '?/init.lua;' .. root .. 'src/?.lua;' .. package.path
end

local U = require('src.util')
local Profiles = require('src.profiles')
local Storage = require('src.storage')
local Calibration = require('src.calibration')
local Session = require('src.session')
local Editor = require('src.editor')
local Draw = require('src.draw')
local UI = require('src.ui_app')

local function currentLayout()
  local value = U.call(ac.getTrackLayout, '')
  return value == '' and 'open' or value
end

local Context = {}
Context.__index = Context

function Context.new()
  local track = U.call(ac.getTrackID, U.call(ac.getTrackName, 'unknown'))
  local layoutID = currentLayout()
  local carID = U.call(function() return ac.getCarID(0) end, 'unknown-car')
  local storage = Storage.new(track, layoutID, carID, root)
  local layout, layoutWarning = storage:loadLayout()
  local results, resultWarning = storage:loadResults()
  local hudSettings = storage:loadHudSettings()
  local self = setmetatable({
    track = track,
    layoutID = layoutID,
    carID = carID,
    storage = storage,
    layout = layout,
    results = results,
    hudSettings = hudSettings,
    scoring = nil,
    matchedProfile = nil,
    dirty = false,
    status = layoutWarning or resultWarning or '',
    lastResult = results.runs[1],
    calibration = Calibration.new()
  }, Context)
  self:refreshScoring()
  self.session = Session.new(self)
  self.editor = Editor.new(self)
  return self
end

function Context:refreshScoring()
  self.scoring, self.matchedProfile = Profiles.resolve(self.layout, self.carID)
end

function Context:saveLayout()
  local errors = require('src.model').validateLayout(self.layout)
  local scoringValid, scoringError = Profiles.validate(self.scoring)
  if not scoringValid then errors[#errors + 1] = 'Carro atual: ' .. scoringError end
  if #errors > 0 then
    self.status = 'Não é possível guardar: ' .. table.concat(errors, ' ')
    return
  end
  local ok, err = self.storage:saveLayout(self.layout)
  if ok then
    self.dirty = false
    self.status = 'Layout guardado.'
  else
    self.status = 'Falha ao guardar: ' .. tostring(err)
  end
end

function Context:reloadLayout()
  if self.session:isBusy() then
    self.status = 'Termina ou cancela a run atual antes de reverter.'
    return
  end
  local layout, warning = self.storage:loadLayout()
  self.layout = layout
  self.dirty = false
  self.editor.outerDraft = {}
  self.editor.undo = {}
  self:refreshScoring()
  self.status = warning or 'Layout revertido.'
end

local context = Context.new()
-- Refreshes ac.getSim().isAdmin, tied to the server's own admin sign-up
-- (CSP's own admin chat app) — not an app-level allowlist, so it stays in
-- sync with whatever admin system the server already uses.
if ac.checkAdminPrivileges then ac.checkAdminPrivileges() end
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

function worldUpdate(dt)
  context.session:update(tonumber(dt) or 0)
  updateHudWindow(tonumber(dt) or 0)
end

function draw3D()
  context.editor:update3D()
  Draw.layout(context)
end

function windowMain()
  UI.window(context)
end

function windowHud()
  Draw.hud(context, true)
end
