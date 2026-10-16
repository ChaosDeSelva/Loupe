-- Opt-in local mailbox transport. Requests contain data, never executable Lua.
local M = {}
local DIR = "loupe-mcp"
local function hexDecode(value)
  assert(#value % 2 == 0 and not value:find("[^%x]"), "invalid hex data")
  return (value:gsub("%x%x", function(pair)
    return string.char(tonumber(pair, 16))
  end))
end
local function quote(value)
  return '"'
    .. value:gsub('[%z\1-\31\\"]', function(c)
      if c == '"' then
        return '\\"'
      end
      if c == "\\" then
        return "\\\\"
      end
      return ("\\u%04x"):format(c:byte())
    end)
    .. '"'
end
local function json(value)
  local kind = type(value)
  if kind == "boolean" then
    return value and "true" or "false"
  end
  if kind == "number" then
    return tostring(value)
  end
  if kind == "string" then
    return quote(value)
  end
  if kind ~= "table" then
    return "null"
  end
  local entries = {}
  for key, item in pairs(value) do
    entries[#entries + 1] = quote(tostring(key)) .. ":" .. json(item)
  end
  return "{" .. table.concat(entries, ",") .. "}"
end
local function decode(text, session)
  assert(#text <= 16384, "request too large")
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  assert(lines[1] == session, "stale session")
  local expiry = tonumber(lines[2])
  assert(expiry and expiry >= os.time() and expiry <= os.time() + 30, "request expired")
  local action, root, keys = lines[3], hexDecode(lines[4] or ""), {}
  for part in (lines[5] or ""):gmatch("[^/]+") do
    local key = hexDecode(part:sub(2))
    if part:sub(1, 1) == "n" then
      key = assert(tonumber(key), "invalid numeric key")
    else
      assert(part:sub(1, 1) == "s", "invalid key type")
    end
    keys[#keys + 1] = key
  end
  local kind, value = lines[6], hexDecode(lines[7] or "")
  if kind == "number" then
    value = assert(tonumber(value), "invalid number")
  elseif kind == "boolean" then
    assert(value == "true" or value == "false", "invalid boolean")
    value = value == "true"
  elseif kind ~= "string" then
    value = nil
  end
  return action, root, keys, value
end
function M.new(api)
  assert(love.filesystem.createDirectory(DIR), "cannot create MCP bridge directory")
  local session = tostring(os.time()) .. "-" .. tostring(love.timer.getTime()):gsub("%.", "")
  assert(love.filesystem.write(DIR .. "/session", session))
  local bridge = { directory = love.filesystem.getSaveDirectory() .. "/" .. DIR }
  local function reply(id, value)
    local path = DIR .. "/" .. id .. ".response"
    local temp = path .. ".tmp"
    assert(love.filesystem.write(temp, json(value)))
    local base = love.filesystem.getSaveDirectory() .. "/"
    assert(os.rename(base .. temp, base .. path))
  end
  function bridge.poll()
    local count = 0
    for _, name in ipairs(love.filesystem.getDirectoryItems(DIR)) do
      local id = name:match("^(%x+)%.request$")
      if id and #id == 32 then
        count = count + 1
        if count > 8 then
          break
        end
        local path = DIR .. "/" .. name
        local info = love.filesystem.getInfo(path)
        local text = info and info.size <= 16384 and love.filesystem.read(path) or ""
        -- Consume before mutation: an interrupted response cannot apply an edit twice.
        love.filesystem.remove(path)
        local ok, result = pcall(function()
          local action, root, keys, value = decode(text, session)
          if action == "screenshot" then
            love.graphics.captureScreenshot(function(data)
              local filename = id .. ".png"
              local success, err = pcall(function()
                assert(love.filesystem.write(DIR .. "/" .. filename, data:encode("png")))
                reply(id, { ok = true, result = { file = filename } })
              end)
              if not success then
                reply(id, { ok = false, error = tostring(err) })
              end
            end)
            return "<pending-screenshot>"
          end
          return api:call(action, root, keys, value)
        end)
        if result ~= "<pending-screenshot>" then
          reply(
            id,
            ok and { ok = true, result = result } or { ok = false, error = tostring(result) }
          )
        end
      end
    end
  end
  function bridge.close()
    if love.filesystem.read(DIR .. "/session") == session then
      love.filesystem.remove(DIR .. "/session")
    end
  end
  return bridge
end
return M
