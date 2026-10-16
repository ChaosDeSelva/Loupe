-- Where watched objects are in the world, and which one is under a point.
local reflect = require("loupe.core.reflect")

local M = {}

M.POINT_SIZE = 8 -- box for objects with a position but no size
M.MAX_DEPTH = 6 -- how far below a root to look for objects
M.MAX_OBJECTS = 5000
M.MAX_VISITS = 20000 -- tables looked at per collect, positioned or not

local function num(v)
  return type(v) == "number" and v or nil
end

-- The world-space box x, y, w, h of obj, or nothing if it has no position.
-- opts.bounds(obj): user hook tried first. It sees every table under the
-- watched roots, so it must return nil for tables it doesn't recognize.
-- opts.center: x, y is the center of w/h boxes instead of the top-left.
function M.bounds(obj, opts)
  if opts.bounds then
    local x, y, w, h = opts.bounds(obj)
    if x then
      return x, y, w, h
    end
  end

  local x, y = num(obj.x), num(obj.y)
  if not (x and y) then
    return
  end
  local def = type(obj.def) == "table" and obj.def or {}

  local w = num(obj.w) or num(obj.width) or num(def.w) or num(def.width)
  local h = num(obj.h) or num(obj.height) or num(def.h) or num(def.height)
  if w and h then
    if opts.center then
      return x - w / 2, y - h / 2, w, h
    end
    return x, y, w, h
  end

  local r = num(obj.r) or num(obj.radius) or num(def.r) or num(def.radius)
  if r then
    return x - r, y - r, 2 * r, 2 * r
  end

  local s = M.POINT_SIZE
  return x - s / 2, y - s / 2, s, s
end

-- An entry's path (e.g. "game.enemies[3]") is built on first use: collect
-- runs every frame over every table, and most entries' paths are never read.
local ENTRY = {
  __index = function(entry, field)
    if field == "path" then
      local path = reflect.path(entry.root, entry.keys)
      rawset(entry, "path", path)
      return path
    end
  end,
}

-- keys is the walk's shared key stack, so the entry gets its own copy of the
-- first `depth` keys.
local function newEntry(value, rootName, keys, depth, x, y, w, h)
  local own = {}
  for i = 1, depth do
    own[i] = keys[i]
  end
  return setmetatable({
    value = value,
    root = rootName,
    keys = own,
    x = x,
    y = y,
    w = w,
    h = h,
  }, ENTRY)
end

-- Every positioned table under the roots:
-- { value, path, root, keys, x, y, w, h }, where keys lead from the root.
-- Visits at most MAX_VISITS tables in all, so a huge world costs a bounded
-- amount per frame; MAX_OBJECTS only caps the result.
-- opts.pickable(obj): return false to leave an object out (e.g. the camera).
function M.collect(roots, opts)
  local list, seen = {}, {}
  local visits = 0
  local keys = {} -- the keys from the current root down to the table being visited

  local function walk(value, depth, rootName)
    if seen[value] or #list >= M.MAX_OBJECTS or visits >= M.MAX_VISITS then
      return
    end
    seen[value] = true
    visits = visits + 1

    if not opts.pickable or opts.pickable(value) then
      local x, y, w, h = M.bounds(value, opts)
      if x then
        list[#list + 1] = newEntry(value, rootName, keys, depth, x, y, w, h)
      end
    end

    if depth < M.MAX_DEPTH then
      for key, child in pairs(value) do
        if type(child) == "table" then
          keys[depth + 1] = key
          walk(child, depth + 1, rootName)
        end
      end
      keys[depth + 1] = nil
    end
  end

  for _, root in ipairs(roots) do
    if type(root.value) == "table" then
      walk(root.value, 0, root.name)
    end
  end
  return list
end

local function contains(e, x, y)
  return x >= e.x and y >= e.y and x < e.x + e.w and y < e.y + e.h
end

-- Smaller first; equal sizes by path so the order doesn't depend on pairs().
local function before(a, b)
  local areaA, areaB = a.w * a.h, b.w * b.h
  if areaA ~= areaB then
    return areaA < areaB
  end
  return tostring(a.path) < tostring(b.path)
end

-- Every box containing (x, y), smallest first: big containers such as level
-- bounds shouldn't win over the thing you actually clicked.
function M.hits(list, x, y)
  local out = {}
  for _, e in ipairs(list) do
    if contains(e, x, y) then
      out[#out + 1] = e
    end
  end
  table.sort(out, before)
  return out
end

-- The smallest box containing (x, y), or nil.
function M.pick(list, x, y)
  return M.hits(list, x, y)[1]
end

return M
