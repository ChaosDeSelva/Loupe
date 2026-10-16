-- Juice: the glowing vector look, particles, shock rings, score popups,
-- screen shake and the hit flash. Nothing here changes the rules of the game.
local fonts = require("examples.shared.fonts")
local particles = require("examples.shared.particles")

local M = {}

local random = love.math.random

-- The radius effects are sized for (a large rock); smaller things get
-- proportionally smaller explosions and shake.
M.BIG_RADIUS = 40

-- Watched as the `fx` root: every number here is safe to drag live.
M.tune = {
  glow = 0.5, -- halo brightness; 0 turns the glow off
  glowPasses = 3, -- halo layers, each wider and fainter
  glowSpread = 3, -- extra line width per halo layer, in pixels
  lineWidth = 1.6,
  shakeStrength = 16, -- pixels of offset at full trauma
  shakeDecay = 1.8, -- trauma lost per second
  shakeOnRock = 0.22, -- trauma added by destroying a large rock
  rockSparks = 28, -- particles for a large rock; smaller rocks get fewer
  shipSparks = 110,
  thrustRate = 110, -- trail particles per second while thrusting
  maxParticles = 2500,
  flash = 0.35, -- white flash when the ship is hit
  stars = 240, -- starfield size, split across three parallax layers
  starParallax = 0.06, -- how strongly the stars react to the ship's speed
  starDrift = 6, -- constant drift, pixels per second, so the title screen moves
  twinkle = 0.6,
  nebula = 1, -- brightness of the background clouds
}

local sparks = particles.new()
local rings, popups = {}, {}
local trauma, flash, clock, thrustCarry = 0, 0, 0, 0

function M.clear()
  particles.clear(sparks)
  rings, popups = {}, {}
  trauma, flash, thrustCarry = 0, 0, 0
end

-- Strokes a shape drawn by drawShape: wide faint additive passes underneath
-- (the "glow"), then a thin bright core. Cheaper than a blur shader, and it
-- needs no canvas, so HiDPI and resizes need no extra handling.
function M.stroke(color, drawShape, alpha)
  local g, t = love.graphics, M.tune
  local r, gr, b = color[1], color[2], color[3]
  alpha = (alpha or 1) * (color[4] or 1)
  g.setLineJoin("bevel") -- thick mitered joins spike at sharp corners
  if t.glow > 0 then
    g.setBlendMode("add")
    for i = t.glowPasses, 1, -1 do
      g.setLineWidth(t.lineWidth + i * t.glowSpread)
      g.setColor(r, gr, b, t.glow * alpha / (i + 1))
      drawShape()
    end
    g.setBlendMode("alpha")
  end
  g.setLineWidth(t.lineWidth)
  -- Pushing the core toward white reads as "hot" next to the colored halo.
  g.setColor(r + (1 - r) * 0.45, gr + (1 - gr) * 0.45, b + (1 - b) * 0.45, alpha)
  drawShape()
end

function M.shake(amount)
  trauma = math.min(1, trauma + amount)
end

-- Squaring trauma makes small hits subtle and big ones violent; noise (not
-- random) keeps the motion smooth instead of jittery.
function M.shakeOffset()
  local amount = M.tune.shakeStrength * trauma * trauma
  if amount <= 0 then
    return 0, 0
  end
  local nx = love.math.noise(clock * 25, 0.5) * 2 - 1
  local ny = love.math.noise(0.5, clock * 25) * 2 - 1
  return nx * amount, ny * amount
end

function M.ring(x, y, radius, color, life)
  rings[#rings + 1] = { x = x, y = y, radius = radius, color = color, age = 0, life = life or 0.5 }
end

function M.popup(x, y, text, color)
  popups[#popups + 1] = { x = x, y = y, text = text, color = color, age = 0, life = 0.9 }
end

function M.explode(x, y, color, radius)
  local scale = radius / M.BIG_RADIUS
  particles.burst(sparks, x, y, math.floor(M.tune.rockSparks * scale + 0.5) + 4, {
    speedMin = 40,
    speedMax = 260 * (0.6 + scale * 0.4),
    lifeMin = 0.3,
    lifeMax = 0.9,
    size = 1.6,
    drag = 2.2,
    color = { 1, 1, 1, 1 },
    color2 = color,
    shape = "streak",
  })
  particles.burst(sparks, x, y, math.floor(6 * scale) + 2, {
    speedMin = 20,
    speedMax = 90,
    lifeMin = 0.6,
    lifeMax = 1.4,
    size = radius * 0.5,
    spin = 6,
    drag = 0.8,
    color = color,
    shape = "shard",
  })
  M.ring(x, y, radius * 2.2, color, 0.45)
end

function M.shipExplosion(ship)
  particles.burst(sparks, ship.x, ship.y, M.tune.shipSparks, {
    speedMin = 60,
    speedMax = 420,
    lifeMin = 0.4,
    lifeMax = 1.6,
    size = 2,
    drag = 1.6,
    vx = ship.vx * 0.5,
    vy = ship.vy * 0.5,
    color = { 1, 1, 1, 1 },
    color2 = ship.flameColor,
    shape = "streak",
  })
  -- The hull breaks into spinning pieces of its own outline.
  particles.burst(sparks, ship.x, ship.y, 5, {
    speedMin = 30,
    speedMax = 110,
    lifeMin = 1.2,
    lifeMax = 2,
    size = ship.r * 1.4,
    spin = 5,
    drag = 0.5,
    vx = ship.vx * 0.6,
    vy = ship.vy * 0.6,
    color = ship.color,
    shape = "shard",
  })
  M.ring(ship.x, ship.y, ship.r * 9, ship.color, 0.7)
  M.ring(ship.x, ship.y, ship.r * 5, ship.flameColor, 0.5)
  flash = M.tune.flash
end

-- Emits trail particles at thrustRate per second, carrying the fraction over
-- so the trail is even at any frame rate.
function M.thrust(ship, dt)
  thrustCarry = thrustCarry + M.tune.thrustRate * dt
  local cos, sin = math.cos(ship.angle), math.sin(ship.angle)
  local bx, by = ship.x - cos * ship.r * 0.7, ship.y - sin * ship.r * 0.7
  while thrustCarry >= 1 do
    thrustCarry = thrustCarry - 1
    local a = ship.angle + math.pi + (random() - 0.5) * 0.6
    local speed = 90 + random() * 120
    particles.add(sparks, {
      x = bx,
      y = by,
      vx = ship.vx + math.cos(a) * speed,
      vy = ship.vy + math.sin(a) * speed,
      life = 0.25 + random() * 0.3,
      size = 1.5 + random() * 1.5,
      drag = 2,
      color = { 1, 0.9, 0.5, 0.9 },
      color2 = ship.flameColor,
    })
  end
end

function M.update(dt)
  clock = clock + dt
  sparks.max = M.tune.maxParticles
  particles.update(sparks, dt)
  for i = #rings, 1, -1 do
    rings[i].age = rings[i].age + dt
    if rings[i].age >= rings[i].life then
      table.remove(rings, i)
    end
  end
  for i = #popups, 1, -1 do
    local p = popups[i]
    p.age, p.y = p.age + dt, p.y - 30 * dt
    if p.age >= p.life then
      table.remove(popups, i)
    end
  end
  trauma = math.max(0, trauma - M.tune.shakeDecay * dt)
  flash = math.max(0, flash - dt * 1.5)
end

function M.drawWorld()
  local g = love.graphics
  g.setBlendMode("add")
  particles.draw(sparks)
  g.setBlendMode("alpha")
  for _, ring in ipairs(rings) do
    local t = ring.age / ring.life
    local radius = ring.radius * (1 - (1 - t) ^ 3) -- fast out, slow settle
    M.stroke(ring.color, function()
      g.circle("line", ring.x, ring.y, radius, 48)
    end, (1 - t) * 0.8)
  end
  g.setFont(fonts.get(14))
  for _, p in ipairs(popups) do
    local c = p.color
    g.setColor(c[1], c[2], c[3], 1 - (p.age / p.life) ^ 2)
    g.printf(p.text, p.x - 50, p.y - 7, 100, "center")
  end
end

-- Full-screen additive flash, drawn after everything else.
function M.drawFlash(w, h)
  if flash > 0 then
    local g = love.graphics
    g.setBlendMode("add")
    g.setColor(1, 0.9, 0.8, flash)
    g.rectangle("fill", 0, 0, w, h)
    g.setBlendMode("alpha")
  end
end

return M
