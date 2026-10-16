-- The only place loupe draws. Replays UI draw commands with love.graphics in
-- screen space, isolated from whatever state the game left behind.
local defaultTheme = require("loupe.ui.theme")
local escape = require("loupe.ui.escape")

local M = {}

-- Where loupe's fonts live. Through love.filesystem: loupe's folder relative
-- to the game, from the module name ("loupe", or "libs/loupe" when required
-- as "libs.loupe"). Through io: this file's own folder, for games (like the
-- examples) that require loupe through package.path from outside the game.
local MODULE_DIR = ((...) or "loupe.ui.render_love"):gsub("%.ui%.render_love$", ""):gsub("%.", "/")
local SOURCE_DIR = debug.getinfo(1, "S").source:match("^@(.*)[/\\]ui[/\\]render_love%.lua$")

local fontSpecs = defaultTheme.fonts
local roles = {} -- role -> Font, for the current specs and DPI
local cache = {} -- "file|size|dpi" -> Font
local fileData = {} -- file -> FileData read with io, or false when unavailable
local dpi

local function dpiScale()
  local g = love.graphics
  return g.getDPIScale and g.getDPIScale() or 1
end

local function readWithIo(file)
  if fileData[file] ~= nil then
    return fileData[file]
  end
  fileData[file] = false
  local fs = love.filesystem
  if SOURCE_DIR and fs and fs.newFileData then
    local f = io.open(SOURCE_DIR .. "/fonts/" .. file, "rb")
    if f then
      local bytes = f:read("*a")
      f:close()
      local ok, data = pcall(fs.newFileData, bytes, file)
      fileData[file] = ok and data or false
    end
  end
  return fileData[file]
end

-- A missing or broken font file is never an error: users may delete the
-- fonts folder to save space, and LÖVE's default font still reads fine.
local function loadFont(file, size)
  local g, fs = love.graphics, love.filesystem
  local path = MODULE_DIR .. "/fonts/" .. file
  if fs and fs.getInfo and fs.getInfo(path) then
    local ok, font = pcall(g.newFont, path, size, "normal", dpi)
    if ok and font then
      return font
    end
  end
  local data = readWithIo(file)
  if data then
    local ok, font = pcall(g.newFont, data, size, "normal", dpi)
    if ok and font then
      return font
    end
  end
  return g.newFont(size, "normal", dpi)
end

local function getFont(role)
  local font = roles[role or "body"]
  if font then
    return font
  end
  dpi = dpi or dpiScale()
  local spec = fontSpecs[role or "body"] or fontSpecs.body
  local key = spec.file .. "|" .. spec.size .. "|" .. dpi
  font = cache[key]
  if not font then
    font = loadFont(spec.file, spec.size)
    cache[key] = font
  end
  roles[role or "body"] = font
  return font
end

-- Uses the theme's font roles (theme.build output). Call again when the UI
-- scale changes; fonts already made for a size are reused.
function M.configure(theme)
  fontSpecs = theme.fonts
  roles = {}
end

function M.font(role)
  return getFont(role)
end

function M.measure(text, role)
  return getFont(role):getWidth(text)
end

function M.lineHeight(role)
  return getFont(role):getHeight()
end

local function setColor(g, color)
  g.setColor(color[1], color[2], color[3], color[4] or 1)
end

local function replay(g, cmd)
  local kind = cmd[1]
  if kind == "rect" then
    setColor(g, cmd[6])
    local r = cmd.radius or 0
    g.rectangle("fill", cmd[2], cmd[3], cmd[4], cmd[5], r, r, 8)
  elseif kind == "outline" then
    setColor(g, cmd[6])
    local width = cmd.width or 1
    local half = width / 2
    local r = math.max(0, (cmd.radius or 0) - half)
    g.setLineWidth(width)
    -- Inset by half the line so the stroke stays inside the box, crisp at 1px.
    g.rectangle("line", cmd[2] + half, cmd[3] + half, cmd[4] - width, cmd[5] - width, r, r, 8)
  elseif kind == "text" then
    setColor(g, cmd[5])
    g.setFont(getFont(cmd.font))
    -- Whole pixels keep glyphs sharp. Every box is one line tall; the UI
    -- escapes its own text, and this catches text built elsewhere.
    g.print(escape.oneLine(cmd[2]), math.floor(cmd[3]), math.floor(cmd[4]))
  elseif kind == "line" then
    setColor(g, cmd[3])
    g.setLineWidth(cmd.width or 1)
    g.line(cmd[2])
  elseif kind == "circle" then
    setColor(g, cmd[5])
    g.circle("fill", cmd[2], cmd[3], cmd[4], 16)
  elseif kind == "poly" then
    setColor(g, cmd[3])
    g.polygon("fill", cmd[2])
  elseif kind == "clip" then
    g.setScissor(cmd[2], cmd[3], math.max(0, cmd[4]), math.max(0, cmd[5]))
  elseif kind == "unclip" then
    g.setScissor()
  else
    error("loupe: unknown draw command '" .. tostring(kind) .. "'", 0)
  end
end

local function replayAll(g, commands)
  for _, cmd in ipairs(commands) do
    replay(g, cmd)
  end
end

function M.draw(commands)
  local g = love.graphics
  local scale = dpiScale()
  if scale ~= dpi then
    -- Moved to a screen with another pixel density: re-rasterize the fonts.
    dpi, roles = scale, {}
  end
  g.push("all")
  -- Undo the game's camera, scissor, canvas and shader so the overlay is always on screen.
  g.origin()
  g.setScissor()
  g.setCanvas()
  g.setShader()
  g.setLineWidth(1)
  g.setLineStyle("smooth")
  g.setFont(getFont("body"))
  -- A failing command must not leave the game's graphics state pushed.
  local ok, err = pcall(replayAll, g, commands)
  g.pop()
  if not ok then
    error(err, 0)
  end
end

return M
