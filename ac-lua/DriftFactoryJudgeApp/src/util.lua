local M = {}

function M.clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function M.lerp(a, b, t)
  return a + (b - a) * t
end

function M.round(value)
  return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end

function M.copy(value, seen)
  if type(value) ~= 'table' then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do
    result[M.copy(key, seen)] = M.copy(item, seen)
  end
  return result
end

function M.ensureArray(value)
  return type(value) == 'table' and value or {}
end

function M.ensureTable(value)
  return type(value) == 'table' and value or {}
end

function M.sanitizePart(value)
  local text = tostring(value or 'open')
  text = text:gsub('[<>:"/\\|?*%c]', '-')
  text = text:gsub('^%s+', ''):gsub('%s+$', '')
  return text == '' and 'open' or text
end

function M.joinPath(...)
  local parts = { ... }
  local result = ''
  for _, part in ipairs(parts) do
    part = tostring(part or '')
    if part ~= '' then
      if result == '' then
        result = part:gsub('[\\/]+$', '')
      else
        result = result .. '\\' .. part:gsub('^[\\/]+', ''):gsub('[\\/]+$', '')
      end
    end
  end
  return result
end

function M.readFile(path)
  local file = io.open(path, 'rb')
  if not file then return nil end
  local content = file:read('*a')
  file:close()
  return content
end

function M.writeFile(path, content)
  local file, err = io.open(path, 'wb')
  if not file then return false, tostring(err or 'Não foi possível abrir o ficheiro') end
  local ok, writeErr = file:write(content)
  file:close()
  if not ok then return false, tostring(writeErr or 'Não foi possível escrever no ficheiro') end
  return true
end

function M.ensureDir(path)
  if io.exists(path) then return true end
  local ok, result = pcall(io.createDir, path)
  return ok and result ~= false
end

function M.atomicWrite(path, content)
  local directory = path:match('^(.*)[/\\][^/\\]+$')
  if directory and not M.ensureDir(directory) then
    return false, 'Não foi possível criar a pasta: ' .. directory
  end

  local temp = path .. '.tmp'
  local backup = path .. '.bak'
  local ok, err = M.writeFile(temp, content)
  if not ok then return false, err end

  if io.exists(path) then
    pcall(io.copyFile, path, backup, false, false)
  end
  local moved, moveResult = pcall(io.move, temp, path, true)
  if not moved or moveResult == false then
    pcall(io.deleteFile, temp)
    return false, 'Não foi possível substituir o ficheiro: ' .. tostring(moveResult)
  end
  return true
end

function M.decodeJson(content)
  if not content or content == '' then return nil, 'O ficheiro está vazio' end
  local ok, result = pcall(JSON.parse, content)
  if not ok or type(result) ~= 'table' then
    return nil, 'JSON inválido'
  end
  return result
end

function M.encodeJson(value)
  local ok, result = pcall(JSON.stringify, value)
  if not ok then return nil, tostring(result) end
  return result
end

local function nextNonSpace(text, index)
  for cursor = index + 1, #text do
    local char = text:sub(cursor, cursor)
    if not char:match('%s') then return char end
  end
  return ''
end

local function previousNonSpace(text, index)
  for cursor = index - 1, 1, -1 do
    local char = text:sub(cursor, cursor)
    if not char:match('%s') then return char end
  end
  return ''
end

function M.prettyJson(content)
  local result, indent, inString, escaped = {}, 0, false, false
  local function append(value) result[#result + 1] = value end
  local function newline() append('\n' .. string.rep('  ', indent)) end

  for index = 1, #content do
    local char = content:sub(index, index)
    if inString then
      append(char)
      if escaped then
        escaped = false
      elseif char == '\\' then
        escaped = true
      elseif char == '"' then
        inString = false
      end
    elseif char == '"' then
      inString = true
      append(char)
    elseif char == '{' or char == '[' then
      append(char)
      local close = char == '{' and '}' or ']'
      if nextNonSpace(content, index) ~= close then
        indent = indent + 1
        newline()
      end
    elseif char == '}' or char == ']' then
      local open = char == '}' and '{' or '['
      if previousNonSpace(content, index) ~= open then
        indent = math.max(0, indent - 1)
        newline()
      end
      append(char)
    elseif char == ',' then
      append(char)
      newline()
    elseif char == ':' then
      append(': ')
    elseif not char:match('%s') then
      append(char)
    end
  end
  return table.concat(result)
end

function M.encodeJsonPretty(value)
  local encoded, err = M.encodeJson(value)
  if not encoded then return nil, err end
  return M.prettyJson(encoded)
end

function M.vec(value, fallback)
  fallback = fallback or { x = 0, y = 0, z = 0 }
  if type(value) ~= 'table' then return M.copy(fallback) end
  return {
    x = tonumber(value.x or value.X) or fallback.x or 0,
    y = tonumber(value.y or value.Y) or fallback.y or 0,
    z = tonumber(value.z or value.Z) or fallback.z or 0
  }
end

function M.toVec3(value)
  return vec3(value.x or 0, value.y or 0, value.z or 0)
end

function M.fromVec3(value)
  return { x = value.x, y = value.y, z = value.z }
end

function M.formatDate(timestamp)
  local ok, result = pcall(os.date, '%Y-%m-%d %H:%M:%S', timestamp)
  return ok and result or tostring(timestamp)
end

function M.call(fn, fallback, ...)
  local ok, result = pcall(fn, ...)
  return ok and result ~= nil and result or fallback
end

return M
