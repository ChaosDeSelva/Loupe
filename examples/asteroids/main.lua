-- A small, complete asteroids game written in plain-LÖVE style: flat tables,
-- `x, y, r` fields, game state in a local. It's loupe's first test bed, so how
-- it looks and feels is driven by plain numbers you can drag live in loupe:
-- `game.ship` (handling), `rockSizes`, `bullets`, `fx` (glow, particles,
-- shake, stars) and `sound`.

-- Examples share the repo's copy of loupe (and examples/shared). In your own
-- game, copy the loupe/ folder next to main.lua and skip this line.
local repo = love.filesystem.getSource() .. "/../../"
package.path = repo .. "?.lua;" .. repo .. "?/init.lua;" .. package.path

local loupe = require("loupe")
local sfx = require("examples.shared.sfx")
local smoke = require("examples.shared.smoke")
local window = require("examples.shared.window")

local bullets = require("src.bullets")
local fx = require("src.fx")
local hud = require("src.hud")
local rocks = require("src.rocks")
local ship = require("src.ship")
local space = require("src.space")
local starfield = require("src.starfield")

local game
local best = 0 -- survives restarts, unlike `game`
local clock = 0
local MAX_DT = 1 / 30 -- a long hitch steps the game this far at most

local function newWave(g)
  g.wave = g.wave + 1
  g.bannerTime = g.state == "play" and hud.BANNER_TIME or 0
  for _ = 1, 3 + g.wave do
    rocks.spawnAtEdge(g, "large")
  end
end

-- `state` is "title" (rocks drift behind the menu), "play" or "over".
local function newGame(state)
  local w, h = love.graphics.getDimensions()
  local g = {
    state = state,
    w = w,
    h = h,
    score = 0,
    wave = 0,
    lives = 3,
    extraLifeEvery = 10000,
    nextExtraLife = 10000,
    respawnDelay = 1.8, -- seconds between losing a ship and the next one
    waveDelay = 2, -- seconds of calm after clearing a wave
    waveTimer = 0,
    bannerTime = 0,
    rocks = {},
    bullets = {},
    ship = ship.new(w / 2, h / 2),
  }
  newWave(g)
  fx.clear()
  return g
end

local function startGame()
  game = newGame("play")
  sfx.play("start")
end

-- The playfield is the whole window; fold everything into it after a resize.
local function fitToWindow()
  local w, h = love.graphics.getDimensions()
  game.w, game.h = w, h
  space.rewrap(game.rocks, w, h)
  space.rewrap(game.bullets, w, h)
  space.rewrap({ game.ship }, w, h)
end

local function addScore(g, points)
  g.score = g.score + points
  best = math.max(best, g.score)
  if g.score >= g.nextExtraLife then
    g.lives = g.lives + 1
    g.nextExtraLife = g.nextExtraLife + g.extraLifeEvery
    fx.popup(g.ship.x, g.ship.y - 30, "1UP", g.ship.color)
    sfx.play("extraLife")
  end
end

local function destroyRock(g, index)
  local rock = g.rocks[index]
  local color = rocks.color(rock)
  local size = rock.r / fx.BIG_RADIUS
  fx.explode(rock.x, rock.y, color, rock.r)
  fx.shake(fx.tune.shakeOnRock * size)
  fx.popup(rock.x, rock.y, tostring(rock.def.score), color)
  -- Bigger rocks boom lower.
  sfx.play("boom", 1.6 - math.min(1, size) * 0.8, 0.08)
  addScore(g, rocks.split(g, index))
end

local function killShip(g)
  local s = g.ship
  fx.shipExplosion(s)
  fx.shake(1)
  sfx.play("bigBoom")
  s.dead, s.thrusting, s.respawnIn = true, false, g.respawnDelay
  g.lives = g.lives - 1
  if g.lives <= 0 then
    g.state = "over"
  end
end

local function resolveHits(g)
  for bi = #g.bullets, 1, -1 do
    local b = g.bullets[bi]
    for ri = #g.rocks, 1, -1 do
      if space.overlaps(b, g.rocks[ri], g.w, g.h) then
        destroyRock(g, ri)
        table.remove(g.bullets, bi)
        break
      end
    end
  end

  local s = g.ship
  if g.state == "play" and not s.dead and s.invulnerable == 0 then
    for ri = #g.rocks, 1, -1 do
      if space.overlaps(s, g.rocks[ri], g.w, g.h) then
        destroyRock(g, ri)
        killShip(g)
        return
      end
    end
  end
end

local function updateShip(g, dt)
  local s = g.ship
  if s.dead then
    s.respawnIn = s.respawnIn - dt
    if s.respawnIn <= 0 then
      ship.respawn(s, g.w / 2, g.h / 2)
      fx.ring(s.x, s.y, s.r * 6, s.color, 0.6)
    end
    return
  end
  ship.update(s, dt, g)
  if love.keyboard.isDown("space") and ship.canFire(s) then
    bullets.fire(g, s)
    sfx.play("laser", 1, 0.06)
  end
  if s.thrusting then
    fx.thrust(s, dt)
  end
end

-- A short calm between waves, counted only while the field is empty.
local function updateWaves(g, dt)
  if #g.rocks == 0 then
    g.waveTimer = g.waveTimer + dt
    if g.waveTimer >= g.waveDelay then
      g.waveTimer = 0
      newWave(g)
    end
  end
  g.bannerTime = math.max(0, g.bannerTime - dt)
end

function love.load(args)
  local smokeRun = smoke.start(args)
  -- Smoke runs draw the overlay too, so CI exercises loupe's real renderer.
  loupe.setOpen(smokeRun)
  sfx.load({ "laser", "boom", "bigBoom", "start", "extraLife" })
  -- Smoke runs skip the title so they exercise the actual game.
  game = newGame(smokeRun and "play" or "title")
end

function love.resize()
  fitToWindow()
end

function love.update(dt)
  smoke.tick()
  dt = math.min(dt, MAX_DT)
  clock = clock + dt
  local g = game
  if g.state == "play" then
    updateShip(g, dt)
  end
  bullets.update(g, dt)
  rocks.update(g, dt)
  resolveHits(g)
  updateWaves(g, dt)
  fx.update(dt)
  starfield.update(dt, g.state == "play" and g.ship or nil, fx.tune)
  hud.update(dt, g)
end

function love.draw()
  local g = love.graphics
  local w, h = game.w, game.h
  -- "all" also restores blend mode and line join, so loupe draws on a clean slate.
  g.push("all")
  g.clear(0.01, 0.012, 0.035)
  starfield.draw(w, h, fx.tune)

  g.translate(fx.shakeOffset())
  rocks.draw(game)
  bullets.draw(game)
  if game.state == "play" and not game.ship.dead then
    ship.draw(game.ship, game, clock)
  end
  fx.drawWorld()

  g.origin()
  hud.draw(game, best, w, h)
  fx.drawFlash(w, h)
  g.pop()
end

function love.keypressed(key)
  if window.isFullscreenKey(key) then
    window.toggleFullscreen()
    fitToWindow()
  elseif key == "escape" then
    love.event.quit()
  elseif key == "r" then
    startGame()
  elseif (key == "return" or key == "kpenter") and game.state ~= "play" then
    startGame()
  elseif key == "m" then
    sfx.toggleMute()
  end
end

-- A getter, because R replaces `game` with a fresh table.
loupe.watch(function()
  return game
end, "game")
loupe.watch(rocks.defs, "rockSizes") -- shared by every rock of a size
loupe.watch(bullets, "bullets") -- speed, life, radius and color tunables
loupe.watch(fx.tune, "fx") -- glow, particles, shake and starfield
loupe.watch(sfx.settings, "sound")

-- Last, so loupe wraps the callbacks defined above. F1 opens it.
loupe.attach()
