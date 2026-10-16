-- A fake `love` global for specs. Graphics calls are recorded instead of
-- drawn, so tests can assert on exactly what would hit the screen.
local M = {}

local saved
local installed = false

local function recorder(calls)
  return setmetatable({}, {
    __index = function(t, name)
      local fn = function(...)
        calls[#calls + 1] = { name, ... }
      end
      rawset(t, name, fn)
      return fn
    end,
  })
end

-- opts.graphics = false omits love.graphics, like a headless `--sim` run.
function M.install(opts)
  opts = opts or {}
  if not installed then
    saved = rawget(_G, "love")
    installed = true
  end

  local fake = { calls = {} }
  local love = {
    handlers = {},
    timer = {
      getTime = function()
        return 0
      end,
    },
  }
  if opts.graphics ~= false then
    love.graphics = recorder(fake.calls)
    -- Queries return values instead of being recorded.
    rawset(love.graphics, "getWidth", function()
      return 800
    end)
    rawset(love.graphics, "getHeight", function()
      return 600
    end)
    rawset(love.graphics, "getDPIScale", function()
      return 1
    end)
    rawset(love.graphics, "newFont", function()
      return {
        getWidth = function(_, text)
          return #text * 7
        end,
        getHeight = function()
          return 14
        end,
      }
    end)
  end
  love.mouse = {
    getPosition = function()
      return fake.mouseX, fake.mouseY
    end,
  }
  fake.mouseX, fake.mouseY = 0, 0

  -- Held keys for modifier checks: fake.keysDown.lctrl = true
  fake.keysDown = {}
  fake.keyRepeat = false
  love.keyboard = {
    hasKeyRepeat = function()
      return fake.keyRepeat
    end,
    setKeyRepeat = function(on)
      fake.keyRepeat = on
    end,
    isDown = function(...)
      for _, key in ipairs({ ... }) do
        if fake.keysDown[key] then
          return true
        end
      end
      return false
    end,
  }

  -- An in-memory save directory. Point fake.source at a real folder to
  -- exercise writing next to main.lua. fake.modtimes[name] is the file's
  -- modification time as getInfo reports it.
  fake.files = {}
  fake.modtimes = {}
  fake.source = "/nonexistent/loupe-test-game"
  fake.fused = false
  fake.requirePath = "?.lua;?/init.lua" -- LÖVE's default
  love.filesystem = {
    getRequirePath = function()
      return fake.requirePath
    end,
    getSource = function()
      return fake.source
    end,
    isFused = function()
      return fake.fused
    end,
    getSaveDirectory = function()
      return "/save"
    end,
    getInfo = function(name)
      return fake.files[name] and { type = "file", modtime = fake.modtimes[name] } or nil
    end,
    -- Like LÖVE 11.5: a missing file returns nil and a message; a syntax error throws.
    load = function(name)
      local text = fake.files[name]
      if not text then
        return nil, "Could not open file " .. name .. ". Does not exist."
      end
      local chunk, err = loadstring(text, "@" .. name)
      if not chunk then
        error("Syntax error: " .. err .. "\n", 0)
      end
      return chunk
    end,
    read = function(name)
      return fake.files[name]
    end,
    write = function(name, text)
      fake.files[name] = text
      return true
    end,
  }

  fake.love = love
  rawset(_G, "love", love)
  return fake
end

function M.uninstall()
  if installed then
    rawset(_G, "love", saved)
    saved = nil
    installed = false
  end
end

return M
