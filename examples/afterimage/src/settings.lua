-- Player preferences that survive a restart, saved as `settings.txt` in the
-- game's save directory (the `t.identity` folder). Pure Lua: the file system
-- is passed in, so tests run without LÖVE.
--
-- The format is one `key=value` per line and is parsed, never executed, so a
-- hand-edited or damaged file can only fall back to defaults. Analytics has
-- no setting here: it is always on in official builds (README.md, "Analytics").
local M = {}

M.FILE = "settings.txt"

-- Every key, its kind, and its default. Unknown keys in the file are ignored.
local FIELDS = {
  { "art", "enum", "illustrated", { illustrated = true, vector = true } },
  { "reduced_motion", "boolean", false },
  { "muted", "boolean", false },
  { "music", "volume", 0.85 },
  { "effects", "volume", 0.85 },
}

function M.defaults()
  local out = {}
  for _, field in ipairs(FIELDS) do
    out[field[1]] = field[3]
  end
  return out
end

local function parseValue(field, text)
  local kind = field[2]
  if kind == "boolean" then
    if text == "true" then
      return true
    elseif text == "false" then
      return false
    end
  elseif kind == "volume" then
    local n = tonumber(text)
    if n and n == n and n >= 0 and n <= 1 then
      return math.floor(n * 100 + 0.5) / 100
    end
  elseif kind == "enum" and field[4][text] then
    return text
  end
  return nil
end

-- Reads `text` into a full settings table; bad or missing values keep their defaults.
function M.parse(text)
  local out = M.defaults()
  if type(text) ~= "string" then
    return out
  end
  local byKey = {}
  for _, field in ipairs(FIELDS) do
    byKey[field[1]] = field
  end
  for line in text:gmatch("[^\r\n]+") do
    local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    local field = key and byKey[key]
    if field then
      local parsed = parseValue(field, value)
      if parsed ~= nil then
        out[key] = parsed
      end
    end
  end
  return out
end

-- The file text for `values`, in a fixed order so an unchanged setting never rewrites it.
function M.serialize(values)
  local lines = {}
  for _, field in ipairs(FIELDS) do
    local value = values[field[1]]
    if parseValue(field, tostring(value)) == nil then
      value = field[3]
    end
    if field[2] == "volume" then
      value = string.format("%.2f", value)
    end
    lines[#lines + 1] = field[1] .. "=" .. tostring(value)
  end
  return table.concat(lines, "\n") .. "\n"
end

-- fs: { read(name) -> text or nil, write(name, text) }. Normally love.filesystem.
function M.new(fs)
  local store = { fs = fs, saved = nil }
  function store.load()
    local ok, text = pcall(fs.read, M.FILE)
    store.saved = ok and type(text) == "string" and text or nil
    return M.parse(store.saved)
  end
  -- Writes only when the text changed. Returns true when it wrote.
  function store.save(values)
    local text = M.serialize(values)
    if text == store.saved then
      return false
    end
    local ok = pcall(fs.write, M.FILE, text)
    if ok then
      store.saved = text
    end
    return ok
  end
  return store
end

return M
