-- The judging session's shared state (track, layout, scoring, results,
-- session and editor), used by both the installed app and the
-- server-delivered online script. Each entry point supplies its own
-- storage, since online scripts can't write files.
local U = require('src.util')
local D = require('src.defaults')
local Model = require('src.model')
local Profiles = require('src.profiles')
local OfficialLayout = require('src.official_layout')
local Calibration = require('src.calibration')
local Session = require('src.session')
local Editor = require('src.editor')

local function currentLayout()
  local value = U.call(ac.getTrackLayout, '')
  return value == '' and 'open' or value
end

local function isOnline()
  local sim = ac.getSim()
  return sim ~= nil and sim.isOnlineRace == true
end

local Context = {}
Context.__index = Context
Context.isOnline = isOnline

---@param options {createStorage: fun(track: string, layoutID: string, carID: string): table, editingDisabled: boolean?}
function Context.new(options)
  local track = U.call(ac.getTrackID, U.call(ac.getTrackName, 'unknown'))
  local layoutID = currentLayout()
  local carID = U.call(function() return ac.getCarID(0) end, 'unknown-car')
  local storage = options.createStorage(track, layoutID, carID)
  -- Online, only the official (published) layout counts, so everyone on
  -- the server is judged the same way: start from the last downloaded copy
  -- and replace it once the fresh download lands. Offline, the player's own
  -- editable layout is used, for preparing tracks.
  local layout, layoutWarning, layoutSource
  if isOnline() then
    layout = storage:loadOfficialCache()
    layoutSource = layout and 'official-cached' or 'official-missing'
    layout = layout or Model.normalizeLayout(D.newLayout(track, layoutID), track, layoutID)
  else
    layout, layoutWarning = storage:loadLayout()
    layoutSource = 'local'
  end
  local results, resultWarning = storage:loadResults()
  local hudSettings = storage:loadHudSettings()
  local self = setmetatable({
    track = track,
    trackName = U.call(ac.getTrackName, track),
    layoutID = layoutID,
    carID = carID,
    storage = storage,
    -- Set by the server-delivered version: it has no file access, so layout
    -- editing, calibration and car setup stay in the installed app.
    editingDisabled = options.editingDisabled == true,
    -- Player-side toggle to draw outer zones and clips on track (start and
    -- finish are always drawn).
    showCourse = false,
    -- On-screen leaderboard (top-right corner); on unless the player turned it off.
    showLeaderboard = hudSettings.showLeaderboard ~= false,
    layout = layout,
    layoutSource = layoutSource, -- 'local' | 'official' | 'official-cached' | 'official-missing'
    layoutStatus = nil, -- message about the official download, shown in the run tab
    pendingOfficialLayout = nil,
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
  if isOnline() then self:fetchOfficialLayout() end
  return self
end

function Context:setShowLeaderboard(show)
  if self.showLeaderboard == show then return end
  self.showLeaderboard = show
  self.hudSettings.showLeaderboard = show
  self.storage:saveHudSettings(self.hudSettings)
end

function Context:refreshScoring()
  self.scoring, self.matchedProfile = Profiles.resolve(self.layout, self.carID)
end

function Context:fetchOfficialLayout()
  self.layoutStatus = 'A descarregar o layout oficial…'
  OfficialLayout.fetch(self.track, self.layoutID, function(layout, message)
    if not layout then
      self.layoutStatus = message
      return
    end
    self.storage:saveOfficialCache(layout)
    self.pendingOfficialLayout = layout
    self.layoutStatus = nil
  end)
end

-- Swapping the layout mid-run would break progress tracking and scoring, so
-- a download that lands during a run waits until the run is over.
function Context:applyPendingOfficialLayout()
  if not self.pendingOfficialLayout or self.session:isBusy() then return end
  self.layout = self.pendingOfficialLayout
  self.pendingOfficialLayout = nil
  self.layoutSource = 'official'
  self.dirty = false
  self.editor.outerDraft = {}
  self.editor.undo = {}
  self:refreshScoring()
end

function Context:saveLayout()
  local errors = Model.validateLayout(self.layout)
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
  if isOnline() then
    self:fetchOfficialLayout()
    self.status = 'A voltar ao layout oficial…'
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

return Context
