local physics = require("src.physics")
local sprites = require("src.sprites")
assert(physics.sweepCircle(0, 0, 100, 0, 50, 0, 5) == 0.45, "fast projectile crosses target")
assert(not physics.sweepCircle(0, 0, 100, 0, 50, 20, 5), "sweep misses outside radius")
assert(physics.sweepCircle(0, 0, 0, 0, 0, 0, 5) == 0, "overlapping stationary projectile")
assert(not physics.sweepCircle(0, 0, 0, 0, 10, 0, 5), "separated stationary projectile")
assert(physics.sweepCircle(0, 5, 100, 5, 50, 0, 5) == 0.5, "tangent counts as collision")
assert(sprites.frame(0, 24, 16, false) == 1)
assert(sprites.frame(15 / 24, 24, 16, false) == 16)
assert(sprites.frame(16 / 24, 24, 16, false) == nil, "one-shot animation stops")
assert(sprites.frame(16 / 24, 24, 16, true) == 1, "loop wraps")
local sim = require("src.sim")
local game = sim.new(1)
game.spawnQueue = {}
game.player.y = 750
sim.spawn(game, "drone")
sim.spawn(game, "drone")
for i, e in ipairs(game.enemies) do
  e.x = i == 1 and 180 or 140
  e.y = 300
  e.r = 5
  e.speed = 0
end
local far, near = game.enemies[1], game.enemies[2]
game.bullets = { { x = 100, y = 300, vx = 2000, vy = 0, travel = 0, r = 1, damage = 3 } }
sim.update(game, 0.05, {})
assert(near.hp == 8 and far.hp == 11, "sweep hits nearest target regardless of array order")
print("PASS: swept collisions, nearest impact, atlas timing and loop boundaries")

-- Read real PNG headers: mocked dimensions alone missed the first-kill crash.
local function dimension(bytes, offset)
  local a, b, c, d = bytes:byte(offset, offset + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end
local previousLove = love
for _, asset in ipairs({ { "laser-atlas", 2 }, { "burst-atlas", 4 }, { "exhaust-atlas", 4, 2 } }) do
  local path = "assets/effects/" .. asset[1] .. ".png"
  local file = assert(io.open(path, "rb"))
  local header = file:read(24)
  file:close()
  local width, height = dimension(header, 17), dimension(header, 21)
  local quads = {}
  love = {
    graphics = {
      newImage = function()
        return {
          getDimensions = function()
            return width, height
          end,
          setFilter = function() end,
        }
      end,
      newQuad = function(x, y, w, h)
        assert(x >= 0 and y >= 0 and x + w <= width and y + h <= height)
        local quad = { x, y, w, h }
        quads[#quads + 1] = quad
        return quad
      end,
      setColor = function() end,
      draw = function(_, quad)
        assert(quad, "valid frame must be drawn")
      end,
    },
  }
  local sheet = sprites.load(path, asset[2], asset[3] or asset[2], 24, false)
  assert(#quads == asset[2] * (asset[3] or asset[2]))
  for frame = 0, sheet.count - 1 do
    assert(sprites.draw(sheet, frame / 24, 100, 100, 80))
  end
end
love = previousLove
print("PASS: real laser and explosion assets load and draw every frame")

-- Extra beam equipment must stay symmetric at every permanent/temporary tier.
local draws = {}
love = {
  graphics = {
    push = function() end,
    pop = function() end,
    translate = function() end,
    rotate = function() end,
    setColor = function() end,
    newImage = function(path)
      return {
        path = path,
        getWidth = function()
          return 256
        end,
        getHeight = function()
          return 256
        end,
        getDimensions = function()
          return 256, 256
        end,
        setFilter = function() end,
      }
    end,
    draw = function(img, x, y)
      draws[#draws + 1] = { path = img.path, x = x, y = y }
    end,
  },
}
local art = require("src.art")
local ship = art.ship
art.ship = function() end
for beams = 1, 5 do
  draws = {}
  art.loadout({ x = 0, y = 0, tilt = 0 }, beams, false, 0, 0)
  assert(#draws == 2 * math.ceil((beams - 1) / 2))
  for i = 1, #draws, 2 do
    assert(
      draws[i].x == -draws[i + 1].x and draws[i].y == draws[i + 1].y,
      "blaster mounts must come in mirrored pairs"
    )
  end
end
draws = {}
art.loadout({ x = 0, y = 0, tilt = 0 }, 2, true, 1, 0, { power = 1, magnet = 1 })
assert(#draws == 6, "paired guns, paired boosters, pulse core and tractor lens combine")
art.ship = ship
love = previousLove
print("PASS: symmetric blaster tiers and combined upgrade attachments")
