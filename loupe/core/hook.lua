-- Wraps named callbacks on a host table (in practice, the engine's callback
-- table) so loupe runs around the game's own callbacks.
--
-- The callbacks are moved off the table and served through a metatable. Reads
-- return the wrapper; writes replace what the wrapper calls. That way a game
-- that swaps callbacks at runtime (`host.update = scene.update`) stays wrapped.
--
-- A game (or a library such as hump.gamestate) may also chain:
-- `local old = host.update; host.update = function(dt) old(dt) ... end`.
-- `old` is then the wrapper, and the wrapper would call the new function,
-- which calls the wrapper, forever. So each assigned function remembers what
-- it replaced (`prev`), and while one is running, a call back into the
-- wrapper goes straight to its `prev` without running loupe again (ADR 0004).
local M = {}

local NOTHING = function() end

-- The wrapper served for `name`. It runs loupe's `wrapper` around the game's
-- current callback, unless a game function in the chain is already running.
local function wrapCallback(chain, name, wrapper)
  local function finish(saved, ...)
    chain.running[name] = saved
    return ...
  end
  -- Runs fn as the current link of the chain. No pcall: if fn throws, the
  -- game is going down anyway, and rethrowing would spoil the traceback
  -- the game's author sees.
  local function call(fn, ...)
    local saved = chain.running[name]
    chain.running[name] = fn
    return finish(saved, fn(...))
  end
  local function callOriginal(...)
    return call(chain.originals[name], ...)
  end

  return function(...)
    -- After remove, the only callers left are chains that captured the
    -- wrapper, starting from the callback that was current at remove.
    local current = chain.running[name] or (chain.removed and chain.originals[name])
    local nextFn = current and chain.prev[current]
    if nextFn then
      return call(nextFn, ...)
    elseif chain.removed then
      return
    end
    return wrapper(chain.originals[name] and callOriginal, ...)
  end
end

-- __newindex: assigning a wrapped callback replaces what its wrapper calls.
local function assign(chain, t, key, value)
  local wrapped = chain.wrapped[key]
  if not wrapped then
    rawset(t, key, value)
    return
  end
  if value == wrapped then
    return -- `host.update = host.update` would make the wrapper call itself
  end
  -- Keep the first: that's when a chaining function captured the wrapper.
  if type(value) == "function" and chain.prev[value] == nil then
    chain.prev[value] = chain.originals[key] or NOTHING
  end
  chain.originals[key] = value
end

-- wrappers[name] is called as wrapper(original, ...) where original calls
-- the game's current callback, or is nil if it hasn't defined one.
function M.install(host, wrappers)
  assert(getmetatable(host) == nil, "loupe: the callback table already has a metatable")

  local chain = {
    originals = {}, -- name -> the game's current callback
    wrapped = {}, -- name -> the wrapper served in its place
    -- prev[fn]: what fn replaced when it was assigned, i.e. what its captured
    -- reference to the wrapper stands for. Weak, so old callbacks can go.
    prev = setmetatable({}, { __mode = "k" }),
    running = {}, -- name -> the game function in name's chain executing now
    removed = false,
  }

  for name, wrapper in pairs(wrappers) do
    chain.originals[name] = rawget(host, name)
    rawset(host, name, nil)
    chain.wrapped[name] = wrapCallback(chain, name, wrapper)
  end

  setmetatable(host, {
    __index = chain.wrapped,
    __newindex = function(t, key, value)
      assign(chain, t, key, value)
    end,
  })

  local handle = {}

  function handle.original(name)
    return chain.originals[name]
  end

  function handle.remove()
    if chain.removed then
      return
    end
    chain.removed = true
    setmetatable(host, nil)
    for name in pairs(wrappers) do
      rawset(host, name, chain.originals[name])
    end
  end

  return handle
end

return M
