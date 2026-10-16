-- Box overlap for top-left x, y with w, h (bump.lua style).
local M = {}

function M.overlaps(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return M
