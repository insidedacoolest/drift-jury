local U = require('src.util')
local D = require('src.defaults')
local P = require('src.profiles')
local M = {}

local function normalizeStart(value)
  if type(value) ~= 'table' then return nil end
  value.position = U.vec(value.position)
  value.direction = U.vec(value.direction, { x = 0, y = 0, z = 1 })
  value.radiusMeters = tonumber(value.radiusMeters) or D.editor.startRadiusMeters
  return value
end

local function normalizeGate(value)
  if type(value) ~= 'table' then return nil end
  value.center = U.vec(value.center)
  value.direction = U.vec(value.direction, { x = 0, y = 0, z = 1 })
  value.widthMeters = tonumber(value.widthMeters) or D.editor.finishWidthMeters
  return value
end

local function canonicalPattern(pattern)
  local text = tostring(pattern or '')
  if text ~= '' and not text:find('*', 1, true) and not text:find('?', 1, true)
    and text:sub(-1) == '_' then
    return text .. '*'
  end
  return text
end

local function patternName(pattern, fallback)
  fallback = tostring(fallback or '')
  local prefix = tostring(pattern or ''):match('^([^*?]+_)%*$')
  if prefix then return prefix:gsub('_$', ''):upper() .. ' Pack' end
  return fallback ~= '' and fallback or tostring(pattern or '')
end

local function cleanOverrides(overrides)
  local result = {}
  if type(overrides) ~= 'table' then return result end
  for _, field in ipairs(P.overrideFields) do
    if overrides[field] ~= nil then result[field] = tonumber(overrides[field]) or overrides[field] end
  end
  return result
end

local function hasOverrides(overrides)
  if type(overrides) ~= 'table' then return false end
  for _, field in ipairs(P.overrideFields) do
    if overrides[field] ~= nil then return true end
  end
  return false
end

local function normalizeProfiles(layout)
  local profiles, byKey = {}, {}
  for _, profile in ipairs(U.ensureArray(layout.carScoringProfiles)) do
    if type(profile) == 'table' then
      local pattern = canonicalPattern(profile.carModelPattern or profile.name)
      if pattern ~= '' then
        local key = pattern:lower()
        local existing = byKey[key]
        if not existing then
          existing = {
            name = patternName(pattern, profile.name),
            carModelPattern = pattern,
            overrides = cleanOverrides(profile.overrides)
          }
          profiles[#profiles + 1] = existing
          byKey[key] = existing
        elseif not hasOverrides(existing.overrides) then
          existing.overrides = cleanOverrides(profile.overrides)
        end
      end
    end
  end

  for tag, overrides in pairs(U.ensureTable(layout.taggedScoringOverrides)) do
    local pattern = canonicalPattern(tag)
    local key = pattern:lower()
    if pattern ~= '' and not byKey[key] and hasOverrides(overrides) then
      local profile = {
        name = patternName(pattern, tag),
        carModelPattern = pattern,
        overrides = cleanOverrides(overrides)
      }
      profiles[#profiles + 1] = profile
      byKey[key] = profile
    end
  end

  layout.carScoringProfiles = profiles
end

local function copyStart(value)
  if not value then return nil end
  return {
    position = U.copy(value.position),
    radiusMeters = value.radiusMeters,
    direction = U.copy(value.direction)
  }
end

local function copyGate(value)
  if not value then return nil end
  return {
    center = U.copy(value.center),
    direction = U.copy(value.direction),
    widthMeters = value.widthMeters
  }
end

local function cleanProfiles(profiles)
  local result = {}
  for _, profile in ipairs(profiles or {}) do
    if hasOverrides(profile.overrides) then
      result[#result + 1] = {
        name = tostring(profile.name or profile.carModelPattern or ''),
        carModelPattern = tostring(profile.carModelPattern or ''),
        overrides = cleanOverrides(profile.overrides)
      }
    end
  end
  return result
end

function M.normalizeLayout(layout, track, layoutID)
  layout = type(layout) == 'table' and layout or D.newLayout(track, layoutID)
  layout.version = 5
  layout.track = tostring(layout.track or track or '')
  layout.layout = tostring(layout.layout or layoutID or 'open')
  layout.pathCorridorHalfWidthMeters = tonumber(layout.pathCorridorHalfWidthMeters)
    or D.editor.defaultPathCorridorHalfWidthMeters
  layout.scoringOverrides = U.ensureTable(layout.scoringOverrides)
  layout.taggedScoringOverrides = U.ensureTable(layout.taggedScoringOverrides)
  layout.leadStart = normalizeStart(layout.leadStart)
  layout.chaseStart = normalizeStart(layout.chaseStart)
  layout.soloStart = normalizeStart(layout.soloStart)
  layout.finishGate = normalizeGate(layout.finishGate)
  layout.pathWaypoints = U.ensureArray(layout.pathWaypoints)
  for index, point in ipairs(layout.pathWaypoints) do layout.pathWaypoints[index] = U.vec(point) end
  layout.outerZones = U.ensureArray(layout.outerZones)
  for _, zone in ipairs(layout.outerZones) do
    zone.name = tostring(zone.name or '')
    zone.points = U.ensureArray(zone.points)
    for index, point in ipairs(zone.points) do zone.points[index] = U.vec(point) end
  end
  layout.innerClips = U.ensureArray(layout.innerClips)
  for _, clip in ipairs(layout.innerClips) do
    clip.name = tostring(clip.name or '')
    clip.position = U.vec(clip.position)
    clip.radiusMeters = tonumber(clip.radiusMeters) or D.editor.clipRadiusMeters
  end
  layout.lineupPairs = U.ensureArray(layout.lineupPairs)
  normalizeProfiles(layout)
  return layout
end

function M.validateLayout(layout)
  local errors = {}
  if not layout.leadStart then errors[#errors + 1] = 'Falta a partida.' end
  if not layout.finishGate then errors[#errors + 1] = 'Falta o gate de chegada.' end
  if #layout.pathWaypoints < 2 then errors[#errors + 1] = 'São necessários pelo menos dois pontos de rota.' end
  if layout.pathCorridorHalfWidthMeters <= 0 then errors[#errors + 1] = 'A meia-largura da rota tem de ser maior que zero.' end
  for index, zone in ipairs(layout.outerZones) do
    if #zone.points < 3 then errors[#errors + 1] = 'A zona exterior ' .. index .. ' precisa de pelo menos três pontos.' end
  end
  for index, clip in ipairs(layout.innerClips) do
    if clip.radiusMeters <= 0 then errors[#errors + 1] = 'O raio do clip interior ' .. index .. ' tem de ser maior que zero.' end
  end
  local scoring = P.resolve(layout, '')
  local ok, errorMessage = P.validate(scoring)
  if not ok then errors[#errors + 1] = errorMessage end
  return errors
end

function M.isReady(layout)
  return layout.leadStart ~= nil and layout.finishGate ~= nil and #layout.pathWaypoints >= 2
end

function M.toStorageLayout(layout)
  layout = M.normalizeLayout(U.copy(layout), layout.track, layout.layout)
  local result = {
    version = 5,
    track = layout.track,
    layout = layout.layout,
    pathCorridorHalfWidthMeters = layout.pathCorridorHalfWidthMeters,
    scoringOverrides = cleanOverrides(layout.scoringOverrides),
    carScoringProfiles = cleanProfiles(layout.carScoringProfiles),
    leadStart = copyStart(layout.leadStart),
    finishGate = copyGate(layout.finishGate),
    pathWaypoints = U.copy(layout.pathWaypoints),
    outerZones = U.copy(layout.outerZones),
    innerClips = U.copy(layout.innerClips)
  }
  return result
end

return M
