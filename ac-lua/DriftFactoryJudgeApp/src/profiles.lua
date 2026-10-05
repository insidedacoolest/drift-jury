local U = require('src.util')
local D = require('src.defaults')
local M = {}

local overrideFields = {
  'targetSpeedKmh',
  'targetAngleDeg',
  'minimumAngleDeg',
  'styleMinimumDriftAngleDeg',
  'styleFullDriftAngleDeg'
}

local function wildcardPattern(pattern)
  local escaped = pattern:gsub('([%^%$%(%)%%%.%[%]%+%-])', '%%%1')
  return '^' .. escaped:gsub('%*', '.*'):gsub('%?', '.') .. '$'
end

local function patternKey(pattern)
  return tostring(pattern or ''):lower()
end

local function specificity(profile, carID, index)
  local pattern = tostring(profile.carModelPattern or '')
  if patternKey(pattern) == patternKey(carID) then return 1000000 + index end
  local plain = pattern:gsub('[%*%?]', '')
  return #plain * 1000 + index
end

local function matchingProfiles(layout, carID)
  local matches = {}
  for index, profile in ipairs(layout.carScoringProfiles or {}) do
    if M.matches(carID, profile.carModelPattern) then
      matches[#matches + 1] = {
        profile = profile,
        index = index,
        key = patternKey(profile.carModelPattern),
        score = specificity(profile, carID, index)
      }
    end
  end
  table.sort(matches, function(a, b) return a.score < b.score end)
  return matches
end

function M.matches(value, pattern)
  value, pattern = tostring(value or ''):lower(), tostring(pattern or ''):lower()
  if pattern == '' then return false end
  if value == pattern then return true end
  if not pattern:find('*', 1, true) and not pattern:find('?', 1, true) then
    return value:find(pattern, 1, true) ~= nil
  end
  return value:match(wildcardPattern(pattern)) ~= nil
end

function M.find(layout, carID)
  local matches = matchingProfiles(layout, carID)
  local match = matches[#matches]
  return match and match.profile or nil, match and match.index or nil
end

function M.findExact(layout, carID)
  return M.findPattern(layout, carID)
end

function M.findPattern(layout, pattern)
  for index, profile in ipairs(layout.carScoringProfiles or {}) do
    if patternKey(profile.carModelPattern) == patternKey(pattern) then
      return profile, index
    end
  end
  return nil, nil
end

local function apply(target, overrides)
  if type(overrides) ~= 'table' then return end
  for _, field in ipairs(overrideFields) do
    if overrides[field] ~= nil then target[field] = tonumber(overrides[field]) or target[field] end
  end
end

function M.resolve(layout, carID)
  local result = U.copy(D.scoring)
  apply(result, layout.scoringOverrides)
  local profile = nil
  for _, match in ipairs(matchingProfiles(layout, carID)) do
    profile = match.profile
    apply(result, profile.overrides)
  end
  return result, profile
end

function M.resolveInherited(layout, carID, targetPattern)
  local result = U.copy(D.scoring)
  apply(result, layout.scoringOverrides)
  local targetScore = specificity({ carModelPattern = targetPattern }, carID, 0)
  local targetKey = patternKey(targetPattern)
  for _, match in ipairs(matchingProfiles(layout, carID)) do
    if match.key ~= targetKey and match.score < targetScore then
      apply(result, match.profile.overrides)
    end
  end
  return result
end

function M.detectPackPattern(carID)
  local text = tostring(carID or '')
  local prefix = text:match('^([^_]+_)')
  if not prefix then return nil, nil end
  local name = prefix:gsub('_$', ''):upper()
  return prefix .. '*', name .. ' Pack'
end

function M.ensurePattern(layout, pattern, name)
  layout.carScoringProfiles = U.ensureArray(layout.carScoringProfiles)
  local profile, index = M.findPattern(layout, pattern)
  if profile then return profile, index end
  profile = {
    name = name or pattern,
    carModelPattern = pattern,
    overrides = {}
  }
  table.insert(layout.carScoringProfiles, 1, profile)
  return profile, 1
end

function M.ensureExact(layout, carID)
  return M.ensurePattern(layout, carID, carID)
end

function M.setOverrideForPattern(layout, pattern, name, field, value)
  local profile, index = M.ensurePattern(layout, pattern, name)
  profile.overrides = U.ensureTable(profile.overrides)
  profile.overrides[field] = value ~= nil and tonumber(value) or nil
  if value == nil then
    local hasOverrides = false
    for _, overrideField in ipairs(overrideFields) do
      if profile.overrides[overrideField] ~= nil then
        hasOverrides = true
        break
      end
    end
    if not hasOverrides then
      table.remove(layout.carScoringProfiles, index)
      return nil
    end
  end
  return profile
end

function M.setOverride(layout, carID, field, value)
  return M.setOverrideForPattern(layout, carID, carID, field, value)
end

function M.validate(scoring)
  if scoring.minimumAngleDeg < 0 then return false, 'O ângulo mínimo tem de ser pelo menos zero.' end
  if scoring.targetAngleDeg <= scoring.minimumAngleDeg then
    return false, 'O ângulo alvo tem de ser maior que o ângulo mínimo.'
  end
  if scoring.targetSpeedKmh <= 0 then return false, 'A velocidade alvo tem de ser maior que zero.' end
  if scoring.styleMinimumDriftAngleDeg < 0 then
    return false, 'O ângulo mínimo de estilo tem de ser pelo menos zero.'
  end
  if scoring.styleFullDriftAngleDeg <= scoring.styleMinimumDriftAngleDeg then
    return false, 'O ângulo total de estilo tem de ser maior que o ângulo mínimo de estilo.'
  end
  return true
end

M.overrideFields = overrideFields
return M
