-- Drives a UI context frame by frame with synthetic input.
--
-- Specs find widgets by id, not by pixel: after a frame, driver.at(ctx, key)
-- returns the center of the widget whose id is `key` or ends in "/key"
-- ("Pause", "game/ship", "loupe.toolbar/pick"). Labels with "##id" are found
-- by their id part. Geometry comes from the theme, so restyling doesn't
-- break specs that only care about behavior.
local theme = require("loupe.ui.theme")
local ui = require("loupe.ui")

local M = {}

M.WIN = { x = 10, y = 10, w = 200, h = 300 }

-- The test font: every byte is 7px wide, every role 14px tall.
M.CHAR = 7

function M.new(opts)
  opts = opts or {}
  return ui.new({
    measure = function(text)
      return #text * M.CHAR
    end,
    lineHeight = 14,
    theme = opts.theme or theme.build(),
    clipboard = opts.clipboard,
  })
end

-- Top of row n in the default test window (a floating window with a title).
function M.row(n, ctx)
  local t = ctx and ctx.theme or theme
  local rowHeight = ctx and ctx.rowHeight or t.rowHeight
  return M.WIN.y + t.titleHeight + (n - 1) * (rowHeight + t.spacing)
end

-- Last frame's rect of the widget with this id (or id suffix). Errors when
-- nothing or more than one widget matches, so a typo can't pass silently.
function M.rect(ctx, key)
  local exact = ctx:rectOf(key)
  if exact then
    return exact
  end
  local found, names = nil, {}
  for id, r in pairs(ctx.rects) do
    if id:sub(-#key - 1) == "/" .. key then
      if found then
        error(("ui_driver: %q matches more than one widget"):format(key), 2)
      end
      found = r
    end
    names[#names + 1] = id
  end
  if not found then
    table.sort(names)
    error(
      ("ui_driver: no widget %q last frame; have:\n  %s"):format(key, table.concat(names, "\n  ")),
      2
    )
  end
  return found
end

-- The center of a widget (dx, dy: offsets from its left/top edge instead).
function M.at(ctx, key, dx, dy)
  local r = M.rect(ctx, key)
  local x = dx and (r.x + dx) or (r.x + math.floor(r.w / 2))
  local y = dy and (r.y + dy) or (r.y + math.floor(r.h / 2))
  return x, y
end

function M.input(fields)
  local snapshot = {
    x = -100,
    y = -100,
    down = false,
    pressed = false,
    released = false,
    wheel = 0,
    typed = {},
  }
  fields = fields or {}
  for k, v in pairs(fields) do
    snapshot[k] = v
  end
  -- Shorthand: `text` and `keys` become ordered typing, text first.
  if not fields.typed then
    snapshot.typed = {}
    if fields.text then
      snapshot.typed[1] = { text = fields.text }
    end
    for _, key in ipairs(fields.keys or {}) do
      snapshot.typed[#snapshot.typed + 1] = { key = key }
    end
  end
  snapshot.text, snapshot.keys = nil, nil
  return snapshot
end

-- Runs one frame and returns the emitted commands.
function M.frame(ctx, fields, build, screenW, screenH)
  ctx:beginFrame(M.input(fields), screenW, screenH)
  build(ctx)
  return ctx:endFrame()
end

-- Wraps a build function in the default test window.
function M.inWindow(build, rect)
  return function(ctx)
    ctx:beginWindow("w", "Test", rect or M.WIN)
    build(ctx)
    ctx:endWindow()
  end
end

function M.click(x, y)
  return { x = x, y = y, pressed = true, released = true }
end

function M.press(x, y)
  return { x = x, y = y, pressed = true, down = true }
end

function M.hold(x, y)
  return { x = x, y = y, down = true }
end

function M.release(x, y)
  return { x = x, y = y, released = true }
end

-- First text command whose text contains `pattern` (plain match).
function M.findText(commands, pattern)
  for _, cmd in ipairs(commands) do
    if cmd[1] == "text" and cmd[2]:find(pattern, 1, true) then
      return cmd
    end
  end
end

-- First text command showing exactly `text`.
function M.findExact(commands, text)
  for _, cmd in ipairs(commands) do
    if cmd[1] == "text" and cmd[2] == text then
      return cmd
    end
  end
end

-- First command of a kind drawn in `color` (compared by identity).
local COLOR_AT = { rect = 6, outline = 6, text = 5, circle = 5, line = 3, poly = 3 }

function M.findColor(commands, kind, color)
  for _, cmd in ipairs(commands) do
    if cmd[1] == kind and cmd[COLOR_AT[kind]] == color then
      return cmd
    end
  end
end

function M.count(commands, kind)
  local n = 0
  for _, cmd in ipairs(commands) do
    if cmd[1] == kind then
      n = n + 1
    end
  end
  return n
end

return M
