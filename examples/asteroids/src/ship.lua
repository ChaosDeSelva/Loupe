local fx = require("src.fx")
local space = require("src.space")

local M = {}

function M.new(x, y)
  return {
    x = x,
    y = y,
    vx = 0,
    vy = 0,
    r = 12,
    angle = -math.pi / 2,
    -- Handling: all plain numbers, so they're fun to drag in loupe.
    thrust = 260,
    turnSpeed = 4,
    drag = 0.6,
    maxSpeed = 480,
    fireDelay = 0.16,
    spawnShield = 2.5, -- seconds of invulnerability after (re)spawning
    cooldown = 0,
    invulnerable = 2.5,
    thrusting = false,
    dead = false,
    respawnIn = 0,
    color = { 0.55, 1, 0.95, 1 },
    flameColor = { 1, 0.45, 0.15, 1 },
  }
end

-- The hull, nose along +x, as a flat vertex list. The HUD reuses it for lives.
function M.outline(r)
  return { r * 1.4, 0, -r, -r * 0.8, -r * 0.5, 0, -r, r * 0.8 }
end

function M.respawn(ship, x, y)
  ship.x, ship.y, ship.vx, ship.vy = x, y, 0, 0
  ship.angle = -math.pi / 2
  ship.dead, ship.thrusting = false, false
  ship.invulnerable = ship.spawnShield
end

local function steer(ship, dt)
  local kb = love.keyboard
  if kb.isDown("left", "a") then
    ship.angle = ship.angle - ship.turnSpeed * dt
  end
  if kb.isDown("right", "d") then
    ship.angle = ship.angle + ship.turnSpeed * dt
  end
  ship.thrusting = kb.isDown("up", "w")
  if ship.thrusting then
    ship.vx = ship.vx + math.cos(ship.angle) * ship.thrust * dt
    ship.vy = ship.vy + math.sin(ship.angle) * ship.thrust * dt
  end
end

-- Drag, then a hard cap at maxSpeed.
local function slow(ship, dt)
  local damping = math.max(0, 1 - ship.drag * dt)
  ship.vx, ship.vy = ship.vx * damping, ship.vy * damping
  local speed = math.sqrt(ship.vx * ship.vx + ship.vy * ship.vy)
  if speed > ship.maxSpeed then
    local k = ship.maxSpeed / speed
    ship.vx, ship.vy = ship.vx * k, ship.vy * k
  end
end

function M.update(ship, dt, game)
  steer(ship, dt)
  slow(ship, dt)
  space.move(ship, dt, game.w, game.h)

  ship.cooldown = math.max(0, ship.cooldown - dt)
  ship.invulnerable = math.max(0, ship.invulnerable - dt)
end

function M.canFire(ship)
  return ship.cooldown == 0
end

function M.draw(ship, game, time)
  local g = love.graphics
  local r = ship.r
  local hull = M.outline(r)
  -- Flicker while invulnerable so the player can tell, plus a shield bubble.
  local shielded = ship.invulnerable > 0
  local alpha = (shielded and math.floor(ship.invulnerable * 10) % 2 == 0) and 0.35 or 1
  local flame = r * (1.3 + love.math.random() * 0.7)
  space.eachImage(ship, game.w, game.h, r * 3, function(ox, oy)
    g.push()
    g.translate(ship.x + ox, ship.y + oy)
    if shielded then
      local pulse = 0.25 + 0.15 * math.sin(time * 10)
      fx.stroke(ship.color, function()
        g.circle("line", 0, 0, r * 2, 32)
      end, pulse * math.min(1, ship.invulnerable))
    end
    g.rotate(ship.angle)
    if ship.thrusting then
      fx.stroke(ship.flameColor, function()
        g.polygon("line", -r * 0.6, -r * 0.35, -r * 0.6 - flame, 0, -r * 0.6, r * 0.35)
      end, alpha)
    end
    -- Fill first so stars don't show through the hull.
    g.setColor(0.02, 0.03, 0.08, alpha)
    g.polygon("fill", hull[1], hull[2], hull[3], hull[4], hull[5], hull[6])
    g.polygon("fill", hull[1], hull[2], hull[5], hull[6], hull[7], hull[8])
    fx.stroke(ship.color, function()
      g.polygon("line", hull)
    end, alpha)
    g.pop()
  end)
end

return M
