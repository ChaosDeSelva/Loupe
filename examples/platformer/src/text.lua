-- Crisp text inside the scaled virtual view: pick a font at the real on-screen
-- size, then draw it shrunk by the view scale. A 12px font scaled up 3x would
-- be blurry; a 36px font scaled by 1/3 is sharp at any window size.
local fonts = require("examples.shared.fonts")
local view = require("src.view")

local M = {}

-- size is in virtual pixels. With align ("left", "center", "right"), the text
-- is laid out in a box `width` virtual pixels wide starting at x.
function M.print(str, x, y, size, align, width)
  local g = love.graphics
  local s = view.getScale()
  local font = fonts.get(size * s)
  g.setFont(font)
  if align then
    g.printf(str, x, y, width * s, align, 0, 1 / s, 1 / s)
  else
    g.print(str, x, y, 0, 1 / s, 1 / s)
  end
end

-- Same, with a dark drop shadow so it reads over the bright sky.
function M.shadowed(str, x, y, size, color, align, width)
  local g = love.graphics
  local alpha = color[4] or 1
  g.setColor(0.05, 0.03, 0.1, 0.6 * alpha)
  M.print(str, x + size * 0.08, y + size * 0.08, size, align, width)
  g.setColor(color[1], color[2], color[3], alpha)
  M.print(str, x, y, size, align, width)
end

return M
