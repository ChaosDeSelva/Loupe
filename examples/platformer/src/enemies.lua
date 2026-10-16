-- Patrolling enemies: walk between `left` and `right`, turn at the ends.
local M = {}

function M.new(x, y, vx, left, right)
  return { x = x, y = y, w = 16, h = 20, vx = vx, left = left, right = right, stride = 0 }
end

function M.update(enemies, dt)
  for _, e in ipairs(enemies) do
    e.x = e.x + e.vx * dt
    -- Turn only when heading out of bounds, so a patrol edited (or dragged)
    -- in loupe can't trap an enemy flipping back and forth every frame.
    if (e.x < e.left and e.vx < 0) or (e.x + e.w > e.right and e.vx > 0) then
      e.vx = -e.vx
    end
    e.stride = e.stride + math.abs(e.vx) * dt
  end
end

function M.draw(e)
  local g = love.graphics
  local dir = e.vx < 0 and -1 or 1
  local phase = e.stride * 0.25
  local bob = math.abs(math.sin(phase)) * 2
  local cx, top = e.x + e.w / 2, e.y + bob

  -- Legs swing opposite each other; the body bobs once per step.
  g.setColor(0.35, 0.08, 0.12, 1)
  local swing = math.sin(phase) * 3
  g.rectangle("fill", cx - 6 + swing, e.y + e.h - 5, 4, 5, 1, 1)
  g.rectangle("fill", cx + 2 - swing, e.y + e.h - 5, 4, 5, 1, 1)

  -- Spikes along the back say "don't touch" without a tutorial.
  g.setColor(0.6, 0.12, 0.2, 1)
  for i = 0, 2 do
    local sx = e.x + 2 + i * 5
    g.polygon("fill", sx, top + 3, sx + 2.5, top - 3, sx + 5, top + 3)
  end
  g.setColor(0.9, 0.3, 0.35, 1)
  g.rectangle("fill", e.x, top + 1, e.w, e.h - 6, 5, 5)
  g.setColor(1, 0.55, 0.55, 0.5)
  g.rectangle("fill", e.x + 3, top + 3, 4, 3, 1, 1)

  -- One angry eye, looking where it walks.
  local ex, ey = cx + dir * 3, top + 7
  g.setColor(1, 1, 1, 1)
  g.circle("fill", ex, ey, 3, 10)
  g.setColor(0.1, 0.02, 0.05, 1)
  g.circle("fill", ex + dir, ey + 0.5, 1.5, 8)
  g.setLineWidth(1.5)
  g.line(ex - 3.5, ey - 4 - dir, ex + 3.5, ey - 4 + dir)
end

return M
