--[[
  Official layouts live in the project's public GitHub repo
  (layouts/<track>/<layout>.json), so every player on a server is judged
  against the same admin-published layout — no server config, no app
  update needed to add or change a track. Online sessions use only this,
  never the player's own locally edited layout.
]]

local U = require('src.util')
local Model = require('src.model')
local M = {}

local BASE_URL = 'https://raw.githubusercontent.com/insidedacoolest/drift-jury/master/layouts/'

-- Same folder/file naming as the local layout library (U.sanitizePart), so
-- a layout saved in the editor can be published by copying it as-is.
local function urlPart(value)
  return (U.sanitizePart(value):gsub('[^%w%-%._~]', function(char)
    return string.format('%%%02X', string.byte(char))
  end))
end

function M.url(track, layoutID)
  return BASE_URL .. urlPart(track) .. '/' .. urlPart(layoutID) .. '.json'
end

-- callback(layout) on success, callback(nil, message) on failure.
function M.fetch(track, layoutID, callback)
  web.get(M.url(track, layoutID), function(err, response)
    if (err and err ~= '') or not response then
      callback(nil, 'Sem ligação aos layouts oficiais: ' .. tostring(err))
      return
    end
    if response.status == 404 then
      callback(nil, 'Esta pista ainda não tem layout oficial publicado.')
      return
    end
    if response.status ~= 200 then
      callback(nil, 'Os layouts oficiais responderam com erro ' .. tostring(response.status) .. '.')
      return
    end
    local parsed = U.decodeJson(response.body)
    if not parsed then
      callback(nil, 'O layout oficial desta pista está corrompido.')
      return
    end
    if tostring(parsed.track or ''):lower() ~= tostring(track):lower()
      or tostring(parsed.layout or 'open'):lower() ~= tostring(layoutID):lower() then
      callback(nil, 'O layout oficial publicado não corresponde a esta pista.')
      return
    end
    callback(Model.normalizeLayout(parsed, track, layoutID))
  end)
end

return M
