-- A small corner pill shown when the overlay is hidden but game time isn't
-- running normally (otherwise a paused game would just look frozen), with a
-- card under it when something needs attention, such as a failed hot reload.
-- Plain draw commands, not a UI window, so it never captures the mouse.
local utf8 = require("loupe.ui.utf8")

local M = {}

M.MAX_LINES = 8

-- Splits one word that is wider than a line into pieces that fit.
local function breakWord(word, width, measure, font)
  local pieces, piece = {}, ""
  local pos = 0
  while pos < #word do
    local nextPos = utf8.next(word, pos)
    local char = word:sub(pos + 1, nextPos)
    if piece ~= "" and measure(piece .. char, font) > width then
      pieces[#pieces + 1] = piece
      piece = ""
    end
    piece = piece .. char
    pos = nextPos
  end
  pieces[#pieces + 1] = piece
  return pieces
end

-- Greedy word wrap. Returns a list of lines, each at most `width` wide.
function M.wrap(text, width, measure, font)
  local lines, line = {}, nil
  for word in text:gmatch("%S+") do
    local candidate = line and (line .. " " .. word) or word
    if measure(candidate, font) <= width then
      line = candidate
    else
      if line then
        lines[#lines + 1] = line
      end
      if measure(word, font) > width then
        local pieces = breakWord(word, width, measure, font)
        for i = 1, #pieces - 1 do
          lines[#lines + 1] = pieces[i]
        end
        line = pieces[#pieces]
      else
        line = word
      end
    end
  end
  if line then
    lines[#lines + 1] = line
  end
  return lines
end

-- theme: the active (built) theme. measure(text, font): text width.
-- lineHeight: a number, or function(font) -> height.
-- alert: optional warning text shown in a card under the pill.
function M.build(clock, screenWidth, alert, theme, measure, lineHeight)
  local c, s = theme.colors, theme.space
  local function height(font)
    return type(lineHeight) == "function" and lineHeight(font) or lineHeight
  end
  local margin = s.md
  local h = theme.rowHeight
  local label = clock.paused and "PAUSED" or "RUNNING"
  local speed = ("x%g"):format(clock.scale)
  local dot = math.max(3, math.floor(h * 0.13))
  local width = s.md
    + 2 * dot
    + s.sm
    + measure(label, "title")
    + s.md
    + measure(speed, "small")
    + s.lg
  local x, y = screenWidth - margin - width, margin
  local cmds = {
    { "rect", x, y + 2, width, h, c.shadow, radius = h / 2 },
    { "rect", x, y, width, h, c.surfaceRaised, radius = h / 2 },
    { "outline", x, y, width, h, c.border, radius = h / 2 },
    { "circle", x + s.md + dot, y + h / 2, dot, clock.paused and c.warning or c.success },
  }
  local tx = x + s.md + 2 * dot + s.sm
  cmds[#cmds + 1] = {
    "text",
    label,
    tx,
    y + math.floor((h - height("title")) / 2),
    clock.paused and c.warning or c.textMuted,
    font = "title",
  }
  cmds[#cmds + 1] = {
    "text",
    speed,
    tx + measure(label, "title") + s.md,
    y + math.floor((h - height("small")) / 2),
    c.textMuted,
    font = "small",
  }

  if alert then
    local pad, bar = s.lg, 3
    local cardW = math.min(screenWidth - 2 * margin, math.floor(460 * (theme.scale or 1)))
    local lines = M.wrap(alert, cardW - 2 * pad - bar, measure)
    if #lines > M.MAX_LINES then
      local kept = {}
      for i = 1, M.MAX_LINES do
        kept[i] = lines[i]
      end
      kept[M.MAX_LINES] = kept[M.MAX_LINES] .. " ..."
      lines = kept
    end
    local lh = height("body") + 2
    local cardH = 2 * pad + #lines * lh
    local cx, cy = screenWidth - margin - cardW, y + h + s.sm
    cmds[#cmds + 1] = { "rect", cx, cy + 2, cardW, cardH, c.shadow, radius = theme.radius + 2 }
    cmds[#cmds + 1] = { "rect", cx, cy, cardW, cardH, c.surfaceRaised, radius = theme.radius }
    cmds[#cmds + 1] = { "outline", cx, cy, cardW, cardH, c.border, radius = theme.radius }
    cmds[#cmds + 1] =
      { "rect", cx + pad / 2, cy + pad, bar, cardH - 2 * pad, c.warning, radius = 1 }
    for i, line in ipairs(lines) do
      cmds[#cmds + 1] = {
        "text",
        line,
        cx + pad + bar,
        cy + pad + (i - 1) * lh,
        i == 1 and c.warning or c.text,
      }
    end
  end
  return cmds
end

return M
