-- Small particle lists shared by the examples.
--
-- Particles live outside the watched game state on purpose: hundreds of
-- short-lived specks would flood loupe's Objects window and make world
-- picking noisy. Their *tunables* (counts, speeds) are what the games expose.
local M = {}

local random = love.math.random

function M.new(max)
  return { items = {}, max = max or 2000 }
end

-- p: x, y, vx, vy, life, size, color ({r, g, b[, a]}), and optionally color2
-- (faded to over the particle's life), gravity, drag, spin and shape:
-- "dot", "streak" (a line along the velocity), "shard" (a spinning line),
-- "square" or "twinkle" (a little four-point star).
function M.add(sys, p)
  if #sys.items >= sys.max then
    return nil
  end
  p.age = 0
  p.vx, p.vy = p.vx or 0, p.vy or 0
  p.gravity, p.drag = p.gravity or 0, p.drag or 0
  p.spin, p.angle = p.spin or 0, p.angle or 0
  p.shape = p.shape or "dot"
  sys.items[#sys.items + 1] = p
  return p
end

-- n particles flying out of x, y. o: speedMin/speedMax, lifeMin/lifeMax,
-- angle and spread (radians; full circle by default), vx/vy (inherited
-- velocity), and the per-particle fields listed for M.add.
function M.burst(sys, x, y, n, o)
  for _ = 1, n do
    local a = (o.angle or 0) + (random() - 0.5) * (o.spread or math.pi * 2)
    local speed = o.speedMin + random() * (o.speedMax - o.speedMin)
    M.add(sys, {
      x = x,
      y = y,
      vx = math.cos(a) * speed + (o.vx or 0),
      vy = math.sin(a) * speed + (o.vy or 0),
      life = o.lifeMin + random() * (o.lifeMax - o.lifeMin),
      size = o.size or 2,
      color = o.color,
      color2 = o.color2,
      gravity = o.gravity,
      drag = o.drag,
      spin = o.spin and (random() - 0.5) * 2 * o.spin,
      angle = random() * math.pi * 2,
      shape = o.shape,
    })
  end
end

function M.update(sys, dt)
  local items = sys.items
  for i = #items, 1, -1 do
    local p = items[i]
    p.age = p.age + dt
    if p.age >= p.life then
      -- Swap-remove: order doesn't matter, and the moved item was already updated.
      items[i] = items[#items]
      items[#items] = nil
    else
      local damping = math.max(0, 1 - p.drag * dt)
      p.vx = p.vx * damping
      p.vy = (p.vy + p.gravity * dt) * damping
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
      p.angle = p.angle + p.spin * dt
    end
  end
end

function M.clear(sys)
  sys.items = {}
end

local function setColor(p, t)
  local c, c2 = p.color, p.color2
  local a = (c[4] or 1) * (1 - t)
  if c2 then
    love.graphics.setColor(
      c[1] + (c2[1] - c[1]) * t,
      c[2] + (c2[2] - c[2]) * t,
      c[3] + (c2[3] - c[3]) * t,
      a
    )
  else
    love.graphics.setColor(c[1], c[2], c[3], a)
  end
end

-- Draws with the current blend mode, so callers choose additive or alpha.
function M.draw(sys)
  local g = love.graphics
  for _, p in ipairs(sys.items) do
    local t = p.age / p.life
    setColor(p, t)
    local size = p.size
    if p.shape == "streak" then
      g.setLineWidth(size)
      g.line(p.x, p.y, p.x - p.vx * 0.045, p.y - p.vy * 0.045)
    elseif p.shape == "shard" then
      local dx, dy = math.cos(p.angle) * size / 2, math.sin(p.angle) * size / 2
      g.setLineWidth(1.5)
      g.line(p.x - dx, p.y - dy, p.x + dx, p.y + dy)
    elseif p.shape == "square" then
      -- Squashing one side by |cos| fakes a flake tumbling in 3D.
      local w = size * math.abs(math.cos(p.angle))
      g.rectangle("fill", p.x - w / 2, p.y - size / 2, w, size)
    elseif p.shape == "twinkle" then
      local s = size * math.sin(math.pi * t)
      g.setLineWidth(1)
      g.line(p.x - s, p.y, p.x + s, p.y)
      g.line(p.x, p.y - s, p.x, p.y + s)
    else
      g.circle("fill", p.x, p.y, size * (1 - t * 0.5), 8)
    end
  end
end

return M
