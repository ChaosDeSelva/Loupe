-- Hover, click-to-select and drag-to-move for objects in the game world.
--
-- view.toWorld(sx, sy) and view.toScreen(wx, wy) map between the screen and
-- the game's world (camera, letterbox). Drags are measured in world units:
-- the pointer and the drag start both go through toWorld, so zoom and camera
-- offsets cancel out.
local geometry = require("loupe.core.geometry")

local M = {}
M.__index = M

local DRAG_THRESHOLD = 3 -- screen pixels
local CYCLE_DISTANCE = 3 -- screen pixels: a click this close to the last one cycles

function M.new()
  -- drag: the object being moved. press: the current mouse press, for telling
  -- clicks from drags. last: where the last pick happened and what it chose.
  return setmetatable({ drag = nil, press = nil, last = nil }, M)
end

local function assign(entry, key, value)
  entry.value[key] = value
end

local function indexOf(hits, value)
  for i, e in ipairs(hits) do
    if e.value == value then
      return i
    end
  end
end

local function distance(ax, ay, bx, by)
  return math.abs(ax - bx) + math.abs(ay - by)
end

-- A press picks the smallest object under the pointer, or, when it lands where
-- the last pick did, the object picked then (so it can be dragged). Releasing
-- that press without dragging moves on to the next larger object: clicking
-- the same spot repeatedly walks through everything stacked there.
local function pressAt(self, input, hits)
  local last, index = self.last, 1
  local again = last ~= nil
    and distance(input.x, input.y, last.x, last.y) <= CYCLE_DISTANCE
    and indexOf(hits, last.value)
  if again then
    index = again
  end
  self.press = { x = input.x, y = input.y, hits = hits, index = index, again = again }
  self.last = { x = input.x, y = input.y, value = hits[index].value }
  return hits[index]
end

local function releaseAt(self, input)
  local press = self.press
  self.press = nil
  if not press.again or #press.hits < 2 then
    return
  end
  if press.moved or distance(input.x, input.y, press.x, press.y) >= DRAG_THRESHOLD then
    return
  end
  local nextEntry = press.hits[press.index % #press.hits + 1]
  self.last.value = nextEntry.value
  return nextEntry
end

-- input: the UI's frame snapshot. free: the pointer isn't over loupe's UI.
-- list: geometry.collect(...). set(entry, key, value) performs drag writes
-- (default: plain assignment). Returns { hover = entry?, picked = entry? }.
function M:frame(input, free, list, view, set)
  set = set or assign
  local result = {}
  local wx, wy = view.toWorld(input.x, input.y)

  local hits
  if free and not self.drag then
    hits = geometry.hits(list, wx, wy)
    result.hover = hits[1]
  end

  if free and input.pressed then
    if result.hover then
      result.picked = pressAt(self, input, hits)
    else
      self.last = nil
    end
  end

  if result.picked then
    local obj = result.picked.value
    if type(obj.x) == "number" and type(obj.y) == "number" then
      self.drag = {
        entry = result.picked,
        screenX = input.x,
        screenY = input.y,
        worldX = wx,
        worldY = wy,
        startX = obj.x,
        startY = obj.y,
        moved = false,
      }
    end
  end

  local press = self.press
  if press and input.down and distance(input.x, input.y, press.x, press.y) >= DRAG_THRESHOLD then
    press.moved = true -- dragged away, even if it comes back: not a click
  end

  local drag = self.drag
  if drag and input.down then
    local far = distance(input.x, input.y, drag.screenX, drag.screenY)
    if far >= DRAG_THRESHOLD then
      drag.moved = true
    end
    if drag.moved then
      set(drag.entry, "x", drag.startX + (wx - drag.worldX))
      set(drag.entry, "y", drag.startY + (wy - drag.worldY))
    end
  end
  if input.released then
    self.drag = nil
    if self.press then
      result.picked = releaseAt(self, input) or result.picked
    end
  end
  return result
end

local function screenBox(box, view)
  local x1, y1 = view.toScreen(box.x, box.y)
  local x2, y2 = view.toScreen(box.x + box.w, box.y + box.h)
  return x1, y1, x2 - x1, y2 - y1
end

-- Draw commands for the hover outline and the selection outline + path label.
-- Boxes are { x, y, w, h } in world space; selected may carry a path.
-- style: { colors, measure(text, font), lineHeight } (the UI theme's colors
-- and font metrics). area: the screen rect left to the game; everything is
-- clipped to it and the label kept inside it.
function M.highlight(hover, selected, view, style, area)
  local cmds = {}
  if not (hover or selected) then
    return cmds
  end
  local c = style.colors
  cmds[1] = { "clip", area.x, area.y, area.w, area.h }
  if hover then
    local x, y, w, h = screenBox(hover, view)
    cmds[#cmds + 1] = { "outline", x, y, w, h, c.textMuted, radius = 3 }
  end
  if selected then
    local x, y, w, h = screenBox(selected, view)
    cmds[#cmds + 1] = { "rect", x, y, w, h, c.accentSoft, radius = 3 }
    cmds[#cmds + 1] = { "outline", x, y, w, h, c.accent, radius = 3, width = 2 }
    if selected.path then
      local pad = 6
      local pillW = style.measure(selected.path, "small") + 2 * pad
      local pillH = style.lineHeight + 6
      local gap = 4
      local py = y - pillH - gap
      if py < area.y then
        py = y + h + gap
      end
      local px = math.max(area.x, math.min(x, area.x + area.w - pillW))
      cmds[#cmds + 1] = { "rect", px, py, pillW, pillH, c.accent, radius = pillH / 2 }
      cmds[#cmds + 1] = {
        "text",
        selected.path,
        px + pad,
        py + 3,
        c.textOnAccent,
        font = "small",
      }
    end
  end
  cmds[#cmds + 1] = { "unclip" }
  return cmds
end

return M
