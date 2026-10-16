-- Swept circle collision prevents fast projectiles tunneling through small targets.
-- Returns the earliest normalized impact time (0..1), or nil.
local M = {}
function M.sweepCircle(x0, y0, x1, y1, cx, cy, radius)
  local dx, dy, ox, oy = x1 - x0, y1 - y0, x0 - cx, y0 - cy
  local c = ox * ox + oy * oy - radius * radius
  if c <= 0 then
    return 0
  end
  local a = dx * dx + dy * dy
  if a == 0 then
    return nil
  end
  local b = 2 * (ox * dx + oy * dy)
  local discriminant = b * b - 4 * a * c
  if discriminant < 0 then
    return nil
  end
  local t = (-b - math.sqrt(discriminant)) / (2 * a)
  if t >= 0 and t <= 1 then
    return t
  end
end
return M
