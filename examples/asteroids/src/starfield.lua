-- A parallax starfield and faint nebula behind the playfield. The ship never
-- leaves the screen, so moving the backdrop against its velocity is what
-- sells speed. Stars are stored in 0..1 units, so any window size works.
local M = {}

local random = love.math.random

-- Depth per layer: far stars barely move, near ones move the most.
local DEPTHS = { 0.15, 0.4, 1 }
local NEBULAE = {
  { u = 0.25, v = 0.3, size = 0.7, color = { 0.35, 0.15, 0.6 } },
  { u = 0.75, v = 0.7, size = 0.6, color = { 0.05, 0.35, 0.5 } },
  { u = 0.6, v = 0.15, size = 0.4, color = { 0.5, 0.1, 0.3 } },
}

local stars, builtFor = {}, nil
local scrollX, scrollY, clock = 0, 0, 0

local function build(count)
  stars = {}
  for i = 1, math.max(0, math.floor(count)) do
    local layer = (i % #DEPTHS) + 1
    stars[i] = {
      u = random(),
      v = random(),
      depth = DEPTHS[layer],
      size = 0.6 + layer * 0.45 + random() * 0.5,
      phase = random() * math.pi * 2,
      speed = 1 + random() * 3,
    }
  end
  builtFor = count
end

function M.update(dt, ship, tune)
  -- Rebuilding on change keeps the `fx.stars` count live-tweakable.
  if builtFor ~= tune.stars then
    build(tune.stars)
  end
  clock = clock + dt
  local vx, vy = 0, 0
  if ship and not ship.dead then
    vx, vy = ship.vx, ship.vy
  end
  scrollX = scrollX - (vx * tune.starParallax + tune.starDrift) * dt
  scrollY = scrollY - vy * tune.starParallax * dt
end

function M.draw(w, h, tune)
  local g = love.graphics
  g.setBlendMode("add")
  local extent = math.max(w, h)
  for _, n in ipairs(NEBULAE) do
    -- Stacked faint discs make a soft radial falloff without a shader.
    local x = (n.u * w + scrollX * 0.05) % (w * 1.4) - w * 0.2
    local y = (n.v * h + scrollY * 0.05) % (h * 1.4) - h * 0.2
    local c = n.color
    for step = 1, 10 do
      g.setColor(c[1], c[2], c[3], 0.014 * tune.nebula)
      g.circle("fill", x, y, extent * n.size * step / 10, 48)
    end
  end
  for _, s in ipairs(stars) do
    local x = (s.u * w + scrollX * s.depth) % w
    local y = (s.v * h + scrollY * s.depth) % h
    local twinkle = 1 - tune.twinkle * 0.5 * (1 + math.sin(clock * s.speed + s.phase))
    g.setColor(0.75, 0.85, 1, (0.25 + s.depth * 0.6) * twinkle)
    g.rectangle("fill", x, y, s.size, s.size)
  end
  g.setBlendMode("alpha")
end

return M
