-- Patches a reloaded module into the table the game already holds (ADR 0007).
--
-- Games capture modules (`local ship = require("src.ship")`) and keep
-- instances whose metatables point at them, so a reload has to change the old
-- table in place rather than swap in the new one.
--
-- `shared` (optional, a set) lists tables that belong to someone else, such as
-- other loaded modules. They are treated as opaque values: never patched,
-- never walked, never copied by snapshot(), and compared by identity.
local M = {}

local NONE = {}

-- Modules that must never be reloaded: loupe itself, and the entry files,
-- whose top level runs the game rather than defining a module.
M.ALWAYS_IGNORED = { "^loupe$", "^loupe%.", "^main$", "^conf$" }

local function matchesAny(name, patterns)
  for _, pattern in ipairs(patterns) do
    if name:find(pattern) then
      return true
    end
  end
  return false
end

-- Names in `loaded` (shaped like package.loaded) that could be reloaded: the
-- module is a table and no pattern in ALWAYS_IGNORED or `ignore` matches.
-- Sorted, so reloads happen and are reported in a stable order.
function M.reloadable(loaded, ignore)
  local names = {}
  for name, value in pairs(loaded) do
    if
      type(name) == "string"
      and type(value) == "table"
      and not matchesAny(name, M.ALWAYS_IGNORED)
      and not matchesAny(name, ignore or NONE)
    then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

local function copy(value, seen, shared)
  if type(value) ~= "table" or shared[value] then
    return value
  end
  if seen[value] then
    return seen[value]
  end
  local out = {}
  seen[value] = out
  for k, v in pairs(value) do
    out[k] = copy(v, seen, shared)
  end
  return out
end

-- A deep copy of a module's own tables (functions, other values and shared
-- tables are kept by reference), taken right after it loads. Passed to patch()
-- later as `previous`, it tells values the file set apart from values the game
-- changed since. The root is always copied, even if it is in `shared`.
function M.snapshot(value, shared)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  local seen = { [value] = out }
  for k, v in pairs(value) do
    out[k] = copy(v, seen, shared or NONE)
  end
  return out
end

-- Pass 1: pair every new table with the old table at the same key, so pass 2
-- can point references to a new table (including self-references such as
-- `Class.__index = Class`) at the old table the game already holds. A new
-- table with no old counterpart pairs with itself: it's adopted as is, but
-- references inside it still get remapped.
local function pair(old, new, previous, ctx)
  ctx.map[new] = old
  ctx.entries[#ctx.entries + 1] = { old = old, new = new, previous = previous }
  local shared = ctx.shared
  for k, v in pairs(new) do
    local current = old[k]
    if type(v) == "table" and not ctx.map[v] and not shared[v] then
      if old == new or type(current) ~= "table" or shared[current] then
        pair(v, v, nil, ctx)
      elseif current ~= v then
        local prev = previous and previous[k]
        local usable = type(prev) == "table" and not shared[prev]
        pair(current, v, usable and prev or nil, ctx)
      end
      -- Otherwise both versions hold the same table: leave it.
    end
  end
end

-- Without a previous version every value is taken from the file. With one,
-- a plain value is taken only if the file changed it, so the game's runtime
-- changes (scores, loupe edits) survive reloads that don't touch them.
local function fileChanged(previous, k, v)
  return previous == nil or previous[k] ~= v
end

-- Pass 2: copy values across and drop keys the file no longer defines.
local function apply(entry, map)
  local old, new, previous = entry.old, entry.new, entry.previous
  for k, v in pairs(new) do
    if type(v) == "table" and map[v] then
      old[k] = map[v]
    elseif type(v) == "function" or fileChanged(previous, k, v) then
      old[k] = v
    end
  end
  for k in pairs(old) do
    -- Keys the game added at runtime aren't in the previous version: keep them.
    if new[k] == nil and (previous == nil or previous[k] ~= nil) then
      old[k] = nil
    end
  end
end

-- Copies `new` into `old` in place and returns true; returns false and
-- changes nothing unless both are tables.
--   functions        always replaced
--   tables in both   patched recursively, keeping the old table's identity
--   other values     replaced; with `previous` (a snapshot of the last version
--                    loaded), only when the file changed them
--   removed keys     removed; with `previous`, only keys the file used to define
-- Metatables are left alone.
function M.patch(old, new, previous, shared)
  if type(old) ~= "table" or type(new) ~= "table" then
    return false
  end
  local ctx = { map = {}, entries = {}, shared = shared or NONE }
  pair(old, new, type(previous) == "table" and previous or nil, ctx)
  for _, entry in ipairs(ctx.entries) do
    apply(entry, ctx.map)
  end
  return true
end

return M
