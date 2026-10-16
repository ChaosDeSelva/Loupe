-- Fonts by pixel size, created once. The examples scale their text with the
-- window, and building a Font every frame would be slow and leak memory.
local M = {}

local cache = {}

function M.get(px)
  px = math.max(6, math.floor(px + 0.5))
  local font = cache[px]
  if not font then
    font = love.graphics.newFont(px)
    cache[px] = font
  end
  return font
end

return M
