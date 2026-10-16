-- Where loupe's docked panels go, computed from scratch every frame so the
-- overlay follows window resizes, fullscreen and UI scale changes (ADR 0008):
--
--   +--------------------------------------+
--   | bar                                  |
--   +-----------+--------------------------+
--   | objects   |                          |
--   +-----------+   free (the game, for    |
--   | inspector |   world picking)         |
--   +-----------+--------------------------+
--
-- Pure: no LÖVE, no UI context. Sizes come from a built (scaled) theme.
local M = {}

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function round(v)
  return math.floor(v + 0.5)
end

local function rect(x, y, w, h)
  return { x = x, y = y, w = w, h = h }
end

local function sidebarWidth(screenW, theme, split)
  local scale = theme.scale or 1
  local want
  if split.sidebar then
    want = round(split.sidebar * scale)
  else
    want =
      clamp(round(screenW * theme.sidebarRatio), theme.sidebarDefaultMin, theme.sidebarDefaultMax)
  end
  local maxW = math.max(0, screenW - theme.freeMin)
  return clamp(want, math.min(theme.sidebarMin, maxW), maxW)
end

-- split = { sidebar = width in unscaled pixels?, objects = 0..1? } (the
-- splitter state; nil fields use the defaults). barHeight: the top bar's
-- height for this frame. Returns rects for bar, sidebar, objects, inspector,
-- free, sidebarSplitter and sectionSplitter.
function M.compute(screenW, screenH, theme, split, barHeight)
  screenW, screenH = math.max(0, screenW), math.max(0, screenH)
  local barH = math.min(barHeight, screenH)
  local sideW = sidebarWidth(screenW, theme, split)
  local sideY, sideH = barH, screenH - barH

  local minH = math.min(theme.panelMinHeight, math.floor(sideH / 2))
  local ratio = split.objects or theme.objectsRatio
  local objectsH = clamp(round(sideH * ratio), minH, sideH - minH)

  local grab = theme.splitterGrab
  return {
    bar = rect(0, 0, screenW, barH),
    sidebar = rect(0, sideY, sideW, sideH),
    objects = rect(0, sideY, sideW, objectsH),
    inspector = rect(0, sideY + objectsH, sideW, sideH - objectsH),
    free = rect(sideW, sideY, screenW - sideW, sideH),
    sidebarSplitter = rect(sideW - grab / 2, sideY, grab, sideH),
    sectionSplitter = rect(0, sideY + objectsH - grab / 2, sideW, grab),
  }
end

-- The sidebar width to store for a splitter dragged to x (screen pixels).
function M.sidebarFromDrag(x, theme)
  return x / (theme.scale or 1)
end

-- The Objects share to store for a splitter dragged to y, given this frame's rects.
function M.objectsFromDrag(y, rects)
  local side = rects.sidebar
  if side.h <= 0 then
    return 0.5
  end
  return clamp((y - side.y) / side.h, 0, 1)
end

return M
