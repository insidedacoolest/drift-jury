local U = require('src.util')
local D = require('src.defaults')
local Model = require('src.model')
local Results = require('src.results')
local M = {}
M.__index = M

local function loadJsonWithBackup(path)
  local content = U.readFile(path)
  if content then
    local value = U.decodeJson(content)
    if value then return value, nil, false end
  end
  local backup = U.readFile(path .. '.bak')
  if backup then
    local value = U.decodeJson(backup)
    if value then return value, 'Backup válido mais recente recuperado.', true end
  end
  return nil, nil, false
end

function M.new(track, layoutID, carID, appRoot)
  local root = ac.getFolder(ac.FolderID.ScriptConfig)
  local trackPart, layoutPart, carPart =
    U.sanitizePart(track), U.sanitizePart(layoutID), U.sanitizePart(carID)
  local bundledLayoutPath = appRoot and appRoot ~= ''
    and U.joinPath(appRoot, 'bundled-layouts', trackPart, layoutPart .. '.json') or nil
  return setmetatable({
    root = root,
    appRoot = appRoot,
    track = track,
    layoutID = layoutID,
    carID = carID,
    layoutPath = U.joinPath(root, 'layouts', trackPart, layoutPart .. '.json'),
    officialCachePath = U.joinPath(root, 'official-layouts', trackPart, layoutPart .. '.json'),
    bundledLayoutPath = bundledLayoutPath,
    resultsPath = U.joinPath(root, 'results', trackPart, layoutPart, carPart .. '.json'),
    hudSettingsPath = U.joinPath(root, 'hud-settings.json')
  }, M)
end

function M:loadLayout()
  local loaded, warning = loadJsonWithBackup(self.layoutPath)
  if loaded then return Model.normalizeLayout(loaded, self.track, self.layoutID), warning end

  if self.bundledLayoutPath then
    local bundled = loadJsonWithBackup(self.bundledLayoutPath)
    if bundled then
      return Model.normalizeLayout(bundled, self.track, self.layoutID),
        'Layout incluído carregado. Guarda o layout para teres a tua própria cópia editável.'
    end
  end

  return Model.normalizeLayout(D.newLayout(self.track, self.layoutID), self.track, self.layoutID), nil
end

function M:saveLayout(layout)
  local encoded, encodeError = U.encodeJsonPretty(Model.toStorageLayout(layout))
  if not encoded then return false, encodeError end
  return U.atomicWrite(self.layoutPath, encoded)
end

-- Last official layout successfully downloaded for this track — kept apart
-- from the player's own editable layout so an offline session never mixes
-- the two, and used online when the download itself fails.
function M:loadOfficialCache()
  local loaded = loadJsonWithBackup(self.officialCachePath)
  return loaded and Model.normalizeLayout(loaded, self.track, self.layoutID) or nil
end

function M:saveOfficialCache(layout)
  local encoded = U.encodeJsonPretty(Model.toStorageLayout(layout))
  if encoded then U.atomicWrite(self.officialCachePath, encoded) end
end

function M:loadResults()
  local loaded, warning = loadJsonWithBackup(self.resultsPath)
  return Results.normalize(loaded, self.track, self.layoutID, self.carID), warning
end

function M:saveResults(results)
  local encoded, encodeError = U.encodeJsonPretty(results)
  if not encoded then return false, encodeError end
  return U.atomicWrite(self.resultsPath, encoded)
end

function M:loadHudSettings()
  local loaded = loadJsonWithBackup(self.hudSettingsPath)
  return type(loaded) == 'table' and loaded or { version = 1 }
end

function M:saveHudSettings(settings)
  settings.version = 1
  local encoded, encodeError = U.encodeJsonPretty(settings)
  if not encoded then return false, encodeError end
  return U.atomicWrite(self.hudSettingsPath, encoded)
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
  os.openFileDialog({
    title = 'Importar layout da Drift Factory',
    defaultFolder = self.root,
    fileTypes = { { name = 'JSON layout', mask = '*.json' } },
    addAllFilesFileType = false,
    flags = bit.bor(os.DialogFlags.PathMustExist, os.DialogFlags.FileMustExist)
  }, function(err, filename)
    if err or not filename or filename == '' then
      if callback then callback(false, err and tostring(err) or 'Importação cancelada.') end
      return
    end
    local parsed, parseError = U.decodeJson(U.readFile(filename))
    if not parsed then
      callback(false, parseError or 'Não foi possível ler o layout.')
      return
    end
    local importedTrack = tostring(parsed.track or '')
    local importedLayout = tostring(parsed.layout or 'open')
    if importedTrack:lower() ~= self.track:lower()
      or importedLayout:lower() ~= self.layoutID:lower() then
      callback(false, string.format(
        'O layout é para %s/%s, a sessão atual é %s/%s.',
        importedTrack, importedLayout, self.track, self.layoutID))
      return
    end
    callback(true, Model.normalizeLayout(parsed, self.track, self.layoutID))
  end)
end

function M:exportLayout(layout, callback)
  os.saveFileDialog({
    title = 'Exportar layout da Drift Factory',
    defaultFolder = self.root,
    defaultExtension = '.json',
    fileName = U.sanitizePart(self.layoutID) .. '.json',
    fileTypes = { { name = 'JSON layout', mask = '*.json' } },
    addAllFilesFileType = false,
    flags = bit.bor(os.DialogFlags.PathMustExist, os.DialogFlags.OverwritePrompt)
  }, function(err, filename)
    if err or not filename or filename == '' then
      if callback then callback(false, err and tostring(err) or 'Exportação cancelada.') end
      return
    end
    local encoded, encodeError = U.encodeJsonPretty(Model.toStorageLayout(layout))
    if not encoded then callback(false, encodeError) return end
    local ok, writeError = U.atomicWrite(filename, encoded)
    callback(ok, ok and ('Exportado para ' .. filename) or writeError)
  end)
end

return M
