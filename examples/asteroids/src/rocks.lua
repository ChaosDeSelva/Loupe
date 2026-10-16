local fx = require("src.fx")
local space = require("src.space")

local M = {}

-- Shared per-size definitions, referenced from each rock as `rock.def`
-- (the same pattern many LÖVE games use for unit/building stats).
M.defs = {
  large = {
    r = 40,
    minSpeed = 30,
    maxSpeed = 60,
    score = 20,
    splitsInto = "medium",
    color = { 0.45, 0.7, 1, 1 },
  },
  medium = {
    r = 22,
    minSpeed = 50,
    maxSpeed = 95,
    score = 50,
    splitsInto = "small",
    color = { 0.75, 0.5, 1, 1 },
  },
  small = { r = 12, minSpeed = 80, maxSpeed = 140, score = 100, color = { 1, 0.45, 0.75, 1 } },
}

local OUTLINE_POINTS = 11
local NO_COLOR = { 1, 1, 1, 1 } -- for a size whose color was deleted in loupe

-- The rock's size color, or white.
function M.color(rock)
  return rock.def.color or NO_COLOR
end

local function jaggedOutline(points)
  local outline = {}
  for i = 1, points do
    outline[i] = 0.75 + love.math.random() * 0.35
  end
  return outline
end

function M.spawn(game, size, x, y)
  local def = M.defs[size]
  local heading = love.math.random() * math.pi * 2
  local speed = def.minSpeed + love.math.random() * (def.maxSpeed - def.minSpeed)
  local rock = {
    size = size,
    def = def,
    x = x,
    y = y,
    vx = math.cos(heading) * speed,
    vy = math.sin(heading) * speed,
    r = def.r,
    spin = (love.math.random() - 0.5) * 2,
    angle = 0,
    -- Radius multipliers, not points, so changing `r` live reshapes the rock.
    outline = jaggedOutline(OUTLINE_POINTS),
  }
  game.rocks[#game.rocks + 1] = rock
  return rock
end

-- Spawn along the screen edge so new rocks never appear on top of the ship.
function M.spawnAtEdge(game, size)
  if love.math.random() < 0.5 then
    return M.spawn(game, size, love.math.random() * game.w, 0)
  end
  return M.spawn(game, size, 0, love.math.random() * game.h)
end

function M.split(game, index)
  local rock = table.remove(game.rocks, index)
  local smaller = rock.def.splitsInto
  if smaller then
    M.spawn(game, smaller, rock.x, rock.y)
    M.spawn(game, smaller, rock.x, rock.y)
  end
  return rock.def.score
end

function M.update(game, dt)
  for _, rock in ipairs(game.rocks) do
    space.move(rock, dt, game.w, game.h)
    rock.angle = rock.angle + rock.spin * dt
  end
end

-- Outline vertices around (0, 0), so wrapped copies only need a translate.
local function vertices(rock)
  local verts, n = {}, #rock.outline
  for i, scale in ipairs(rock.outline) do
    local a = rock.angle + (i / n) * math.pi * 2
    verts[#verts + 1] = math.cos(a) * rock.r * scale
    verts[#verts + 1] = math.sin(a) * rock.r * scale
  end
  return verts
end

function M.draw(game)
  local g = love.graphics
  for _, rock in ipairs(game.rocks) do
    local verts = vertices(rock)
    local color = M.color(rock)
    local function outline()
      g.polygon("line", verts)
    end
    space.eachImage(rock, game.w, game.h, rock.r * 1.2, function(ox, oy)
      g.push()
      g.translate(rock.x + ox, rock.y + oy)
      -- The outline is jagged (not convex), but every point sees the center,
      -- so a fan of triangles fills it correctly. The fill hides the stars.
      g.setColor(0.02, 0.025, 0.06, 0.9)
      local n = #verts
      for i = 1, n, 2 do
        local j = i + 2 > n and 1 or i + 2
        g.polygon("fill", 0, 0, verts[i], verts[i + 1], verts[j], verts[j + 1])
      end
      fx.stroke(color, outline)
      g.pop()
    end)
  end
end

return M
