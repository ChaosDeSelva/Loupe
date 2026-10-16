-- Shared helpers for things that move through a wrapping playfield.
local M = {}

function M.move(obj, dt, w, h)
  obj.x = (obj.x + obj.vx * dt) % w
  obj.y = (obj.y + obj.vy * dt) % h
end

-- Measures to the nearest wrapped copy when w and h are given, so a rock
-- poking over the right edge still hits a ship at the left edge.
function M.overlaps(a, b, w, h)
  local dx, dy = a.x - b.x, a.y - b.y
  if w then
    dx = dx - w * math.floor(dx / w + 0.5)
    dy = dy - h * math.floor(dy / h + 0.5)
  end
  local reach = a.r + b.r
  return dx * dx + dy * dy < reach * reach
end

-- Calls fn(ox, oy) for every place obj shows up: its own spot, plus the
-- opposite edge(s) while it straddles one, so nothing pops across the wrap.
function M.eachImage(obj, w, h, margin, fn)
  local ox = obj.x < margin and w or (obj.x > w - margin and -w or nil)
  local oy = obj.y < margin and h or (obj.y > h - margin and -h or nil)
  fn(0, 0)
  if ox then
    fn(ox, 0)
  end
  if oy then
    fn(0, oy)
  end
  if ox and oy then
    fn(ox, oy)
  end
end

-- After a window resize, fold everything back into the new playfield.
function M.rewrap(list, w, h)
  for _, obj in ipairs(list) do
    obj.x, obj.y = obj.x % w, obj.y % h
  end
end

return M
