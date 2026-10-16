local fx = require("src.fx")
local space = require("src.space")

local M = {}

-- Watched as the `bullets` root: change these and the next shot uses them.
M.speed = 520
M.life = 1.1
M.radius = 2
M.color = { 1, 0.8, 0.35, 1 }

function M.fire(game, ship)
  local cos, sin = math.cos(ship.angle), math.sin(ship.angle)
  game.bullets[#game.bullets + 1] = {
    x = ship.x + cos * ship.r * 1.4,
    y = ship.y + sin * ship.r * 1.4,
    vx = ship.vx + cos * M.speed,
    vy = ship.vy + sin * M.speed,
    r = M.radius,
    life = M.life,
  }
  ship.cooldown = ship.fireDelay
  -- A little kick back sells the shot without changing how the ship handles.
  ship.vx, ship.vy = ship.vx - cos * 6, ship.vy - sin * 6
end

function M.update(game, dt)
  for i = #game.bullets, 1, -1 do
    local b = game.bullets[i]
    space.move(b, dt, game.w, game.h)
    b.life = b.life - dt
    if b.life <= 0 then
      table.remove(game.bullets, i)
    end
  end
end

function M.draw(game)
  local g = love.graphics
  for _, b in ipairs(game.bullets) do
    -- A short tail along the velocity reads as speed; it fades out at the end of life.
    local fade = math.min(1, b.life * 4)
    fx.stroke(M.color, function()
      g.line(b.x, b.y, b.x - b.vx * 0.025, b.y - b.vy * 0.025)
    end, fade)
    g.setColor(1, 1, 1, fade)
    g.circle("fill", b.x, b.y, b.r, 8)
  end
end

return M
