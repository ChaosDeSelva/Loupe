-- Tweaked values to persist, and the loupe_overrides.lua file format.
--
-- An entry is { root = "game", keys = { "ship", "thrust" }, value = 286 }:
-- the watched root's name, the keys from it down to the field, and the value.
-- Keys are kept as a list (not a path string) so nothing needs parsing.
local reflect = require("loupe.core.reflect")
local serialize = require("loupe.core.serialize")

local M = {}
M.__index = M

local function copy(list)
  local out = {}
  for i, v in ipairs(list) do
    out[i] = v
  end
  return out
end

local SCALAR = { number = true, string = true, boolean = true }

-- Whether a field reached by `keys` can be saved: every key must be a string
-- or a finite number. Others can't be written to the file (functions,
-- tables, userdata) or aren't read back from it (booleans, infinities).
function M.persistable(keys)
  if type(keys) ~= "table" or #keys == 0 then
    return false
  end
  for _, k in ipairs(keys) do
    local t = type(k)
    if not (t == "string" or (t == "number" and k > -math.huge and k < math.huge)) then
      return false
    end
  end
  return true
end

local function entryId(root, keys)
  -- serialize keeps 1 and "1" apart.
  return root .. "\0" .. serialize.value(keys)
end

function M.new()
  return setmetatable({ byId = {} }, M)
end

-- A field changed from old to new. Remembers the first `old` it sees as the
-- field's original, and forgets the entry when the field returns to it.
-- Returns false, recording nothing, when the keys aren't persistable.
function M:record(root, keys, old, new)
  if not M.persistable(keys) then
    return false
  end
  local id = entryId(root, keys)
  local entry = self.byId[id]
  if not entry then
    entry = { root = root, keys = copy(keys), original = old, knowsOriginal = true }
    self.byId[id] = entry
  end
  entry.value = new
  if entry.knowsOriginal and new == entry.original then
    self.byId[id] = nil
  end
  return true
end

-- Seeds the store with entries loaded from a file (originals unknown).
function M:load(entries)
  for _, e in ipairs(entries) do
    self.byId[entryId(e.root, e.keys)] = {
      root = e.root,
      keys = copy(e.keys),
      value = e.value,
      knowsOriginal = false,
    }
  end
end

local function keyBefore(a, b)
  if type(a) ~= type(b) then
    return type(a) == "number"
  end
  return a < b
end

local function entryBefore(a, b)
  if a.root ~= b.root then
    return a.root < b.root
  end
  for i = 1, math.min(#a.keys, #b.keys) do
    if a.keys[i] ~= b.keys[i] then
      return keyBefore(a.keys[i], b.keys[i])
    end
  end
  return #a.keys < #b.keys
end

-- The current overrides as { root, keys, value }, in a stable order.
function M:entries()
  local list = {}
  for _, e in pairs(self.byId) do
    list[#list + 1] = { root = e.root, keys = copy(e.keys), value = e.value }
  end
  table.sort(list, entryBefore)
  return list
end

-- The Lua-style path to a field, e.g. game.rocks[3].x, on one line.
function M.path(root, keys)
  -- Comments end at a newline, so keep odd keys on one line.
  return (reflect.path(root, keys):gsub("[\r\n]", " "))
end

local HEADER = [[
-- loupe overrides: values tweaked in the inspector, re-applied when the game runs.
-- Remove a line (or this whole file) to drop a tweak. Copy values into your code to keep them.
]]

function M.render(entries)
  local lines = { HEADER, "return {" }
  for _, e in ipairs(entries) do
    lines[#lines + 1] = ("  { %s, %s, %s }, -- %s"):format(
      serialize.value(e.root),
      serialize.value(e.keys),
      serialize.value(e.value),
      M.path(e.root, e.keys)
    )
  end
  lines[#lines + 1] = "}\n"
  return table.concat(lines, "\n")
end

-- Turns the table a loaded overrides file returned into entries, dropping
-- anything malformed.
function M.parse(data)
  local out = {}
  if type(data) ~= "table" then
    return out
  end
  for _, item in ipairs(data) do
    if
      type(item) == "table"
      and type(item[1]) == "string"
      and M.persistable(item[2])
      and SCALAR[type(item[3])]
    then
      out[#out + 1] = { root = item[1], keys = copy(item[2]), value = item[3] }
    end
  end
  return out
end

-- Writes the entries for `rootName` into `root`. Fields must already exist:
-- an override for something the game no longer has is skipped, not created.
-- Returns applied, skipped.
function M.apply(entries, rootName, root)
  local applied, skipped = 0, 0
  for _, e in ipairs(entries) do
    if e.root == rootName then
      local parent = reflect.resolveParent(root, e.keys)
      local key = e.keys[#e.keys]
      if type(parent) == "table" and parent[key] ~= nil then
        parent[key] = e.value
        applied = applied + 1
      else
        skipped = skipped + 1
      end
    end
  end
  return applied, skipped
end

return M
