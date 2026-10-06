-- Storage for the server-delivered online script. Online scripts can't write
-- files, so everything goes through ac.storage (CSP's own key-value store,
-- kept per player under Documents\Assetto Corsa\cfg\extension\state\lua).
-- Same interface as src/storage.lua; layout editing, import and export are
-- not available here and stay in the installed app.
local U = require('src.util')
local D = require('src.defaults')
local Model = require('src.model')
local Results = require('src.results')
local M = {}
M.__index = M

local unavailable = 'Não disponível na versão do servidor. Usa a app instalada, offline.'

local function key(...)
  local parts = {}
  for index, part in ipairs({ ... }) do parts[index] = U.sanitizePart(part) end
  return table.concat(parts, '/')
end

local function load(storageKey)
  local ok, content = pcall(function() return ac.storage[storageKey] end)
  if not ok or type(content) ~= 'string' or content == '' then return nil end
  return U.decodeJson(content)
end

local function save(storageKey, value)
  local encoded, encodeError = U.encodeJson(value)
  if not encoded then return false, encodeError end
  local ok, err = pcall(function() ac.storage[storageKey] = encoded end)
  if not ok then return false, tostring(err) end
  return true
end

function M.new(track, layoutID, carID)
  return setmetatable({
    track = track,
    layoutID = layoutID,
    carID = carID,
    officialKey = 'official:' .. key(track, layoutID),
    resultsKey = 'results:' .. key(track, layoutID, carID),
    hudKey = 'hud',
  }, M)
end

function M:loadLayout()
  return Model.normalizeLayout(D.newLayout(self.track, self.layoutID), self.track, self.layoutID), nil
end

function M:saveLayout()
  return false, unavailable
end

function M:loadOfficialCache()
  local loaded = load(self.officialKey)
  return loaded and Model.normalizeLayout(loaded, self.track, self.layoutID) or nil
end

function M:saveOfficialCache(layout)
  save(self.officialKey, Model.toStorageLayout(layout))
end

function M:loadResults()
  return Results.normalize(load(self.resultsKey), self.track, self.layoutID, self.carID), nil
end

function M:saveResults(results)
  return save(self.resultsKey, results)
end

function M:loadHudSettings()
  local loaded = load(self.hudKey)
  return type(loaded) == 'table' and loaded or { version = 1 }
end

function M:saveHudSettings(settings)
  settings.version = 1
  return save(self.hudKey, settings)
end

function M:addResult(results, score)
  local record = Results.add(results, score, self.track, self.layoutID, self.carID)
  local ok, saveError = self:saveResults(results)
  return ok, ok and record or saveError
end

function M:clearResults(results)
  Results.clear(results)
  return self:saveResults(results)
end

function M:importLayout(callback)
  if callback then callback(false, unavailable) end
end

function M:exportLayout(_, callback)
  if callback then callback(false, unavailable) end
end

return M
