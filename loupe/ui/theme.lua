-- loupe's look: sizes in pixels at UI scale 1, colors as {r, g, b, a} in 0..1,
-- and font roles (a file in loupe/fonts/ and a size).
--
-- This module is itself the default theme. Contexts never use it directly:
-- theme.build(overrides, scale) returns a scaled copy with overrides merged,
-- so a game's theme tweaks can't leak into the shared module table.
local M = {}

M.space = { xs = 2, sm = 4, md = 8, lg = 12, xl = 16 }

M.padding = 10 -- inside panels and floating windows
M.spacing = 4 -- between rows
M.rowHeight = 24
M.controlPadding = 10 -- horizontal padding inside buttons and fields
M.titleHeight = 30 -- floating window title bar
M.headerHeight = 30 -- docked section header ("OBJECTS")
M.barPadding = 8 -- vertical padding of the top bar
M.indent = 14
M.radius = 6
M.radiusSmall = 5
M.hairline = 1
M.focusRing = 2
M.scrollbarWidth = 4
M.splitterGrab = 8 -- thickness of a splitter's grab area
M.sidebarDefaultMin = 300 -- the default width is a share of the screen within these
M.sidebarDefaultMax = 440
M.sidebarMin = 200 -- narrowest a dragged sidebar gets
M.freeMin = 160 -- width always left to the game
M.panelMinHeight = 90 -- shortest Objects or Inspector section
M.labelRatio = 0.4 -- share of a row taken by a widget's label
M.sidebarRatio = 0.24 -- default sidebar width as a share of the screen
M.objectsRatio = 0.42 -- default share of the sidebar taken by Objects
M.scrollRows = 3 -- rows per wheel notch

-- Fields that are not pixel sizes and so never scale.
local UNITLESS = {
  labelRatio = true,
  sidebarRatio = true,
  objectsRatio = true,
  scrollRows = true,
  scale = true,
}

M.fonts = {
  body = { file = "Inter-Regular.ttf", size = 13 },
  strong = { file = "Inter-SemiBold.ttf", size = 13 },
  small = { file = "Inter-Regular.ttf", size = 11 },
  title = { file = "Inter-SemiBold.ttf", size = 11 }, -- section headers
  mono = { file = "JetBrainsMono-Regular.ttf", size = 12 }, -- numbers
}

M.colors = {
  surface = { 0.063, 0.067, 0.078, 0.975 }, -- docked panels
  surfaceRaised = { 0.098, 0.102, 0.118, 0.985 }, -- floating windows, popovers
  titleBar = { 0.122, 0.129, 0.149, 1 },
  field = { 1, 1, 1, 0.045 }, -- value inputs
  fieldHover = { 1, 1, 1, 0.075 },
  control = { 1, 1, 1, 0.07 }, -- buttons
  controlHover = { 1, 1, 1, 0.11 },
  controlActive = { 1, 1, 1, 0.16 },
  hover = { 1, 1, 1, 0.05 }, -- rows
  border = { 1, 1, 1, 0.08 },
  borderStrong = { 1, 1, 1, 0.16 },
  text = { 0.925, 0.933, 0.953, 1 },
  textMuted = { 0.56, 0.58, 0.63, 1 },
  textFaint = { 0.38, 0.4, 0.45, 1 },
  textOnAccent = { 1, 1, 1, 1 },
  accent = { 0.357, 0.545, 0.965, 1 },
  accentHover = { 0.45, 0.62, 1, 1 },
  accentSoft = { 0.357, 0.545, 0.965, 0.16 },
  selection = { 0.357, 0.545, 0.965, 0.24 }, -- selected rows
  selectionText = { 0.357, 0.545, 0.965, 0.45 }, -- selected text in a field
  focus = { 0.357, 0.545, 0.965, 0.45 },
  warning = { 0.961, 0.698, 0.29, 1 },
  warningSoft = { 0.961, 0.698, 0.29, 0.14 },
  danger = { 0.949, 0.4, 0.4, 1 },
  success = { 0.33, 0.8, 0.55, 1 },
  scrollbar = { 1, 1, 1, 0.16 },
  scrollbarHot = { 1, 1, 1, 0.3 },
  shadow = { 0, 0, 0, 0.35 },
}

local function isList(t)
  return t[1] ~= nil
end

local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    out[k] = copy(v)
  end
  return out
end

-- Tables merge key by key; lists (colors) and plain values replace.
local function merge(into, from)
  for k, v in pairs(from) do
    if type(v) == "table" and type(into[k]) == "table" and not isList(v) then
      merge(into[k], v)
    else
      into[k] = copy(v)
    end
  end
end

local function round(v)
  return math.floor(v + 0.5)
end

local function scaleSizes(t, scale)
  for k, v in pairs(t) do
    if type(v) == "number" and not UNITLESS[k] then
      t[k] = v > 0 and math.max(1, round(v * scale)) or round(v * scale)
    end
  end
end

-- overrides: a partial theme (any of the fields above, at scale 1).
-- scale: UI scale (default 1). Returns a new, independent theme.
function M.build(overrides, scale)
  scale = scale or 1
  local t = {}
  for k, v in pairs(M) do
    if type(v) ~= "function" then
      t[k] = copy(v)
    end
  end
  if overrides then
    merge(t, overrides)
  end
  scaleSizes(t, scale)
  scaleSizes(t.space, scale)
  for _, font in pairs(t.fonts) do
    font.size = math.max(1, round(font.size * scale))
  end
  t.scale = scale
  return t
end

return M
