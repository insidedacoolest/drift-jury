local U = require('src.util')
local M = {}

function M.normalize(value, track, layoutID, carID)
  value = type(value) == 'table' and value or {}
  value.version = 1
  value.track = track
  value.layout = layoutID
  value.car = carID
  value.personalBest = type(value.personalBest) == 'table' and value.personalBest or nil
  value.runs = U.ensureArray(value.runs)
  while #value.runs > 50 do table.remove(value.runs) end
  return value
end

function M.add(results, score, track, layoutID, carID, timestamp)
  local record = U.copy(score)
  record.dateUtc = timestamp or os.time()
  record.track = track
  record.layout = layoutID
  record.car = carID
  record.personalBest = false
  if record.valid and (not results.personalBest or record.score > results.personalBest.score) then
    record.personalBest = true
    results.personalBest = U.copy(record)
  end
  table.insert(results.runs, 1, record)
  while #results.runs > 50 do table.remove(results.runs) end
  return record
end

function M.clear(results)
  results.personalBest = nil
  results.runs = {}
end

return M
