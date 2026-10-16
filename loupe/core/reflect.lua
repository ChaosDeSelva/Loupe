-- Looks at plain Lua values and describes them for the inspector.
local M = {}

local KEYWORDS = {}
for word in
  ([[and break do else elseif end false for function goto if in local nil not or
  repeat return then true until while]]):gmatch("%a+")
do
  KEYWORDS[word] = true
end

local function isIdentifier(key)
  return type(key) == "string" and key:match("^[%a_][%w_]*$") ~= nil and not KEYWORDS[key]
end

-- {r, g, b} or {r, g, b, a}: only numbers in 0..1, nothing else in the table.
local function isColor(t)
  local n = 0
  for k, v in pairs(t) do
    if type(k) ~= "number" or type(v) ~= "number" or v < 0 or v > 1 then
      return false
    end
    n = n + 1
  end
  if n ~= 3 and n ~= 4 then
    return false
  end
  for i = 1, n do
    if t[i] == nil then
      return false
    end
  end
  return true
end

-- "number", "boolean", "string", "color", "table", "function", "userdata", "nil", ...
function M.kind(value)
  local t = type(value)
  if t == "table" and isColor(value) then
    return "color"
  end
  return t
end

-- tostring that can't throw: a game's __tostring may error or return a
-- non-string, and loupe must still be able to show the table.
local function safeString(value)
  local ok, s = pcall(tostring, value)
  if ok and type(s) == "string" then
    return s
  end
  return type(value)
end

function M.keyLabel(key)
  if isIdentifier(key) then
    return key
  elseif type(key) == "string" then
    return ("[%q]"):format(key)
  end
  return "[" .. safeString(key) .. "]"
end

function M.childPath(parentPath, key)
  if isIdentifier(key) then
    return parentPath .. "." .. key
  end
  return parentPath .. M.keyLabel(key)
end

-- The Lua-style path from a root down `keys`, e.g. game.rocks[3].x.
function M.path(rootName, keys)
  local path = rootName
  for _, k in ipairs(keys) do
    path = M.childPath(path, k)
  end
  return path
end

-- The key list for a child: a new list, so callers can keep both.
function M.childKeys(keys, key)
  local out = {}
  for i, k in ipairs(keys) do
    out[i] = k
  end
  out[#out + 1] = key
  return out
end

-- Follows keys down from root. Returns the value there, or nil if the path
-- no longer leads anywhere.
function M.resolve(root, keys)
  local value = root
  for _, k in ipairs(keys) do
    if type(value) ~= "table" then
      return nil
    end
    value = value[k]
  end
  return value
end

-- The table holding the field `keys` leads to (keys minus the last one), or
-- nil if the path no longer leads anywhere.
function M.resolveParent(root, keys)
  local value = root
  for i = 1, #keys - 1 do
    if type(value) ~= "table" then
      return nil
    end
    value = value[keys[i]]
  end
  return value
end

local TYPE_ORDER = { number = 1, string = 2 }

-- names: other keys' safeString, worked out once rather than per comparison.
local function keyBefore(a, b, names)
  local ta, tb = TYPE_ORDER[type(a)] or 3, TYPE_ORDER[type(b)] or 3
  if ta ~= tb then
    return ta < tb
  elseif ta == 3 then
    return names[a] < names[b]
  end
  return a < b
end

local function field(key, value)
  return { key = key, value = value, kind = M.kind(value), label = M.keyLabel(key) }
end

-- The table's fields as { key, value, kind, label }: the array part first in
-- order, then numbers, then strings, then anything else.
function M.fields(t)
  local out = {}
  local arrayLength = 0
  for i, v in ipairs(t) do
    out[i] = field(i, v)
    arrayLength = i
  end

  local rest, names = {}, {}
  for k in pairs(t) do
    if not (type(k) == "number" and k >= 1 and k <= arrayLength and k % 1 == 0) then
      rest[#rest + 1] = k
      if not TYPE_ORDER[type(k)] then
        names[k] = safeString(k)
      end
    end
  end
  table.sort(rest, function(a, b)
    return keyBefore(a, b, names)
  end)
  for _, k in ipairs(rest) do
    out[#out + 1] = field(k, t[k])
  end
  return out
end

local function userdataType(value)
  local ok, name = pcall(function()
    return value:type()
  end)
  if ok and type(name) == "string" then
    return name
  end
  return "userdata"
end

-- A short description for showing a value that isn't edited directly.
function M.summary(value)
  local t = type(value)
  if t == "table" then
    local n = 0
    for _ in pairs(value) do
      n = n + 1
    end
    return "{" .. (n > 0 and n or "") .. "}"
  elseif t == "userdata" then
    return userdataType(value)
  elseif t == "string" then
    return ("%q"):format(value)
  elseif t == "function" or t == "thread" then
    return t
  end
  return tostring(value)
end

return M
