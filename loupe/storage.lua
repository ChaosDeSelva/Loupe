-- Reads and writes loupe_overrides.lua (ADR 0003).
--
-- Running unfused from a folder, the file lives next to main.lua so it can be
-- committed with the game; love.filesystem can't write there, so plain io is
-- used. Fused or packaged games use the save directory instead.
local M = {}

M.FILE = "loupe_overrides.lua"

-- The game's folder, or nil when the source isn't a writable folder (fused,
-- or a .love archive). Also tells init whether hot reload makes sense.
local function sourceFolder()
  local fs = love.filesystem
  if fs.isFused() then
    return nil
  end
  local folder = fs.getSource()
  -- A folder has a readable main.lua inside it; a .love archive doesn't.
  local probe = io.open(folder .. "/main.lua", "r")
  if not probe then
    return nil
  end
  probe:close()
  return folder
end
M.sourceFolder = sourceFolder

-- Returns the file's text, or nil if there isn't one.
function M.read()
  local folder = sourceFolder()
  if folder then
    local f = io.open(folder .. "/" .. M.FILE, "r")
    if not f then
      return nil
    end
    local text = f:read("*a")
    f:close()
    return text
  end
  if love.filesystem.getInfo(M.FILE) then
    return love.filesystem.read(M.FILE)
  end
end

-- Writes a temp file next to `path`, then renames it over `path`, so a
-- failed write (disk full, killed mid-save) never leaves a truncated file.
local function writeReplacing(path, text)
  local temp = path .. ".tmp"
  local f, err = io.open(temp, "w")
  if not f then
    return false, err
  end
  local wrote, writeErr = f:write(text)
  local closed, closeErr = f:close()
  if not (wrote and closed) then
    os.remove(temp)
    return false, writeErr or closeErr
  end
  local renamed, renameErr = os.rename(temp, path)
  if not renamed then
    -- Windows won't rename over an existing file.
    os.remove(path)
    renamed, renameErr = os.rename(temp, path)
  end
  if not renamed then
    os.remove(temp)
    return false, renameErr
  end
  return true
end

-- Returns true and the full path written, or false and an error message.
function M.write(text)
  local folder = sourceFolder()
  if folder then
    local path = folder .. "/" .. M.FILE
    local ok, err = writeReplacing(path, text)
    if not ok then
      return false, tostring(err)
    end
    return true, path
  end
  local ok, err = love.filesystem.write(M.FILE, text)
  if not ok then
    return false, tostring(err)
  end
  return true, love.filesystem.getSaveDirectory() .. "/" .. M.FILE
end

M.MAX_INSTRUCTIONS = 1e6
local BYTECODE_MARK = 27 -- "\27": the first byte of every precompiled Lua chunk

local function tooLong()
  error("took too long to run (over " .. M.MAX_INSTRUCTIONS .. " instructions)", 2)
end

-- Calls chunk with the instruction limit, putting back any previous hook.
local function runLimited(chunk)
  local hook, mask, count = debug.gethook()
  debug.sethook(tooLong, "", M.MAX_INSTRUCTIONS)
  local ok, result = pcall(chunk)
  if hook then
    debug.sethook(hook, mask, count)
  else
    debug.sethook()
  end
  return ok, result
end

-- Runs the file's text as source (never bytecode) with an empty environment
-- and an instruction limit: it can't reach globals such as os, io or the
-- game, and can't hang the game. It isn't a full sandbox: string methods are
-- still reachable and memory isn't limited (ADR 0003). Returns data, or nil
-- and an error.
function M.parse(text)
  if text:byte(1) == BYTECODE_MARK then
    return nil, M.FILE .. " is precompiled bytecode; only Lua source is loaded"
  end
  local chunk, err = loadstring(text, "=" .. M.FILE)
  if not chunk then
    return nil, err
  end
  setfenv(chunk, {})
  -- LuaJIT's compiled code never calls count hooks, so a loop would escape
  -- the limit once compiled. Interpreting is plenty fast for a data file.
  local jit = rawget(_G, "jit")
  if jit then
    jit.off(chunk, true)
  end
  local ok, data = runLimited(chunk)
  if not ok then
    return nil, tostring(data)
  end
  return data
end

return M
