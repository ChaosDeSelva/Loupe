-- Watches the game's Lua modules and hot-swaps them when their files change
-- (ADR 0007). Only modules that are already loaded and live in the game's
-- filesystem are watched; patching itself is in core/hotswap.lua.
local hotswap = require("loupe.core.hotswap")

local M = {}
M.__index = M

local INTERVAL = 0.5 -- seconds between file checks
local NOTHING = {}

-- Where require looks: the game's require path (set with
-- love.filesystem.setRequirePath, e.g. "src/?.lua"), then LÖVE's defaults.
local function candidates(base)
  local fs = love.filesystem
  local patterns = fs.getRequirePath and fs.getRequirePath() or ""
  local out = {}
  for pattern in (patterns .. ";?.lua;?/init.lua"):gmatch("[^;]+") do
    out[#out + 1] = pattern:gsub("%?", function()
      return base
    end)
  end
  return out
end

-- The file a module name was loaded from, or false if it isn't a game file.
local function findFile(name)
  local base = (name:gsub("%.", "/"))
  for _, path in ipairs(candidates(base)) do
    local info = love.filesystem.getInfo(path)
    if info and info.type == "file" then
      return path
    end
  end
  return false
end

-- Every loaded module table, so patching never reaches into another module.
local function loadedTables()
  local set = {}
  for _, value in pairs(package.loaded) do
    if type(value) == "table" then
      set[value] = true
    end
  end
  return set
end

-- Trims the newline LÖVE appends to syntax errors.
local function message(err)
  return (tostring(err):gsub("%s+$", ""))
end

-- Loads and runs a module's file. Returns the new module table, or nil and
-- an error. Errors never escape: a broken file must not take the game down.
local function loadModule(name, path)
  local ok, chunk, err = pcall(love.filesystem.load, path)
  if not ok then
    return nil, message(chunk)
  end
  if not chunk then
    return nil, message(err)
  end
  local ran, result = pcall(chunk, name)
  if not ran then
    return nil, message(result)
  end
  if type(result) ~= "table" then
    return nil, ("didn't return a table (got %s)"):format(type(result))
  end
  return result
end

-- Patches the new version into the live module; the new version becomes the
-- baseline for telling file changes from game changes next time.
local function reloadModule(name, path, entry, shared)
  local new, err = loadModule(name, path)
  if not new then
    return { name = name, ok = false, err = err }
  end
  local previous = hotswap.snapshot(new, shared)
  -- The game's own metamethods (a locked module table) can throw mid-patch.
  local ok, patchErr = pcall(hotswap.patch, package.loaded[name], new, entry.previous, shared)
  if not ok then
    return { name = name, ok = false, err = message(patchErr) }
  end
  entry.previous = previous
  return { name = name, ok = true }
end

-- opts.ignore: Lua patterns for module names never to reload.
-- Starts tracking the modules loaded so far right away.
function M.new(opts)
  opts = opts or {}
  local self = setmetatable({
    ignore = opts.ignore or {},
    elapsed = 0,
    files = {}, -- name -> path, or false when the module has no game file
    tracked = {}, -- name -> { modtime, previous = snapshot of the last version }
  }, M)
  self:check()
  return self
end

-- Call every frame with the real (unscaled) dt. Returns a list of
-- { name, ok, err? }, one per module that changed; usually empty.
function M:update(dt)
  self.elapsed = self.elapsed + dt
  if self.elapsed < INTERVAL then
    return NOTHING
  end
  -- Restart rather than subtract, so a long hitch doesn't queue up checks.
  self.elapsed = 0
  return self:check()
end

-- The modification time of the game file behind module `name`, or nil when
-- it has none. Each module's file is looked up once.
local function modtimeOf(self, name)
  if self.files[name] == nil then
    self.files[name] = findFile(name)
  end
  local path = self.files[name]
  local info = path and love.filesystem.getInfo(path)
  return info and info.modtime
end

-- Starts tracking modules seen for the first time and reloads tracked ones
-- whose file changed. Returns the reload results, as update() does.
function M:check()
  local results = {}
  local shared -- built only when something needs it: walking package.loaded isn't free
  for _, name in ipairs(hotswap.reloadable(package.loaded, self.ignore)) do
    local modtime = modtimeOf(self, name)
    local entry = self.tracked[name]
    if modtime and (not entry or modtime > entry.modtime) then
      shared = shared or loadedTables()
      if not entry then
        self.tracked[name] = {
          modtime = modtime,
          previous = hotswap.snapshot(package.loaded[name], shared),
        }
      else
        -- Recorded even on failure, so a broken file is retried only once it's saved again.
        entry.modtime = modtime
        results[#results + 1] = reloadModule(name, self.files[name], entry, shared)
      end
    end
  end
  return results
end

return M
