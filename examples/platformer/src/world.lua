-- The level and its rules. Everything uses top-left x, y with w, h (bump.lua
-- style), except coins, which are x, y + radius.
local aabb = require("src.aabb")
local backdrop = require("src.backdrop")
local camera = require("src.camera")
local enemies = require("src.enemies")
local particles = require("examples.shared.particles")
local player = require("src.player")
local sfx = require("examples.shared.sfx")
local text = require("src.text")
local view = require("src.view")

local M = {}

M.LEVEL_WIDTH = 2400
M.LEVEL_HEIGHT = view.HEIGHT

local random = love.math.random

-- Kept out of `game` so loupe's picking isn't flooded (see shared/particles).
-- `dust` blends normally; `sparks` are additive, for light.
local dust, sparks = particles.new(), particles.new()
local popups = {}

local SPAWN_X, SPAWN_Y = 40, 260
local RESPAWN_DELAY = 0.8 -- seconds between dying and reappearing
local FALL_MARGIN = 60 -- how far below the level counts as falling out
local POPUP_LIFE = 0.8 -- seconds a "+1" or "STOMP" stays up
local CELEBRATION_LENGTH = 5 -- seconds of fireworks after the flag
local FIREWORK_COLORS = { { 1, 0.4, 0.4 }, { 0.4, 1, 0.6 }, { 0.5, 0.7, 1 }, { 1, 0.85, 0.3 } }

local COIN_SPOTS = {
  { 260, 220 },
  { 445, 170 },
  { 640, 250 }, -- over the first pit: a reason to jump it high
  { 820, 210 },
  { 1030, 150 },
  { 1220, 250 },
  { 1440, 220 },
  { 1600, 170 },
  { 1800, 290 },
  { 2015, 230 },
  { 2135, 180 },
  { 2210, 290 },
}

local function box(x, y, w, h)
  return { x = x, y = y, w = w, h = h }
end

-- Effect tunables, all live-editable.
local function newFx()
  return {
    shakeStrength = 6, -- pixels at full trauma
    shakeDecay = 2.5,
    shake = 0, -- current trauma, 0..1
    dustCount = 8, -- puffs on landing
    coinBurst = 14,
    coinSparkle = 1.5, -- twinkles per coin per second
    stompBurst = 22,
    deathBurst = 40,
    fireworkEvery = 0.35, -- seconds between celebration fireworks
    fireworkSparks = 60,
    confetti = 120,
    stompBounce = 0.75, -- bounce off an enemy at this fraction of a jump
  }
end

local function newCoins()
  local coins = {}
  for i, spot in ipairs(COIN_SPOTS) do
    coins[i] = { x = spot[1], y = spot[2], r = 6 }
  end
  return coins
end

function M.new()
  local g = {
    score = 0,
    coinsTotal = 0,
    deaths = 0,
    time = 0, -- level timer, stops at the flag
    clock = 0, -- animation time, never stops
    state = "play", -- "play", then "won" at the flag
    respawnIn = 0,
    spawn = { x = SPAWN_X, y = SPAWN_Y }, -- drag it in loupe to start somewhere else
    player = player.new(SPAWN_X, SPAWN_Y),
    camera = camera.new(view.WIDTH, view.HEIGHT),
    backdrop = backdrop.new(),
    fx = newFx(),
    platforms = {
      box(0, 320, 600, 40),
      box(680, 320, 500, 40),
      box(1260, 320, 1140, 40),
      box(220, 250, 90, 12),
      box(400, 200, 90, 12),
      box(760, 240, 120, 12),
      box(980, 180, 100, 12),
      box(1400, 250, 80, 12),
      box(1560, 200, 80, 12),
      box(1980, 260, 70, 12),
      box(2100, 210, 70, 12),
    },
    coins = newCoins(),
    enemies = {
      enemies.new(900, 300, 50, 700, 1150),
      enemies.new(1700, 300, 70, 1300, 2100),
      enemies.new(2000, 300, -60, 1850, 2250),
    },
    flag = box(2300, 260, 12, 60),
    celebration = 0, -- seconds since reaching the flag
    nextFirework = 0,
  }
  g.coinsTotal = #g.coins
  particles.clear(dust)
  particles.clear(sparks)
  popups = {}
  camera.snap(g.camera, g.player, M.LEVEL_WIDTH, M.LEVEL_HEIGHT)
  return g
end

function M.pressJump(g)
  if g.state == "play" and g.respawnIn == 0 then
    player.pressJump(g.player)
  end
end

local function shake(g, amount)
  g.fx.shake = math.min(1, g.fx.shake + amount)
end

local function puff(x, y, n, spread)
  particles.burst(dust, x, y, n, {
    angle = -math.pi / 2,
    spread = spread or math.pi,
    speedMin = 15,
    speedMax = 60,
    lifeMin = 0.25,
    lifeMax = 0.5,
    size = 2.5,
    drag = 4,
    gravity = -20,
    color = { 1, 0.95, 0.9, 0.7 },
  })
end

local function popup(x, y, str, color)
  popups[#popups + 1] = { x = x, y = y, text = str, color = color, age = 0 }
end

local function die(g)
  local p = g.player
  particles.burst(sparks, p.x + p.w / 2, p.y + p.h / 2, g.fx.deathBurst, {
    speedMin = 40,
    speedMax = 220,
    lifeMin = 0.4,
    lifeMax = 0.9,
    size = 2.5,
    drag = 2,
    gravity = 300,
    color = { 1, 1, 0.8, 1 },
    color2 = p.color,
  })
  shake(g, 0.6)
  sfx.play("hurt")
  g.deaths = g.deaths + 1
  g.respawnIn = RESPAWN_DELAY
end

local function respawn(g)
  local p = g.player
  p.x, p.y, p.vx, p.vy = g.spawn.x, g.spawn.y, 0, 0
  p.facing, p.scaleX, p.scaleY = 1, 0.6, 1.5 -- pop back in with a stretch
  puff(p.x + p.w / 2, p.y + p.h, 12, math.pi * 2)
end

local function collectCoins(g)
  local p = g.player
  for i = #g.coins, 1, -1 do
    local c = g.coins[i]
    if aabb.overlaps(p, { x = c.x - c.r, y = c.y - c.r, w = 2 * c.r, h = 2 * c.r }) then
      table.remove(g.coins, i)
      g.score = g.score + 1
      particles.burst(sparks, c.x, c.y, g.fx.coinBurst, {
        speedMin = 30,
        speedMax = 140,
        lifeMin = 0.3,
        lifeMax = 0.7,
        size = 4,
        drag = 3,
        color = { 1, 0.95, 0.5, 1 },
        color2 = { 1, 0.6, 0.1 },
        shape = "twinkle",
      })
      popup(c.x, c.y - 8, "+1", { 1, 0.9, 0.3, 1 })
      -- Rising pitch as you collect more: a cheap but effective reward.
      sfx.play("coin", 1 + 0.03 * g.score)
    end
  end
end

local function hitEnemies(g, dt)
  local p = g.player
  for i = #g.enemies, 1, -1 do
    local e = g.enemies[i]
    if aabb.overlaps(p, e) then
      -- Falling, and the feet were above the enemy's top last frame: a stomp.
      local prevBottom = p.y + p.h - p.vy * dt
      if p.vy > 0 and prevBottom <= e.y + 6 then
        table.remove(g.enemies, i)
        p.vy = -p.jump * g.fx.stompBounce
        p.rising = false
        player.stretch(p)
        particles.burst(dust, e.x + e.w / 2, e.y + e.h / 2, g.fx.stompBurst, {
          speedMin = 40,
          speedMax = 160,
          lifeMin = 0.3,
          lifeMax = 0.7,
          size = 3,
          drag = 2,
          gravity = 400,
          spin = 8,
          color = { 0.9, 0.3, 0.35, 1 },
          shape = "square",
        })
        popup(e.x + e.w / 2, e.y - 6, "STOMP", { 1, 1, 1, 1 })
        shake(g, 0.35)
        sfx.play("stomp")
      else
        die(g)
        return
      end
    end
  end
end

local function celebrate(g, dt)
  g.celebration = g.celebration + dt
  g.nextFirework = g.nextFirework - dt
  if g.nextFirework <= 0 and g.celebration < CELEBRATION_LENGTH then
    g.nextFirework = g.fx.fireworkEvery
    local hue = random(1, #FIREWORK_COLORS)
    particles.burst(
      sparks,
      g.flag.x + random(-200, 120),
      50 + random() * 120,
      g.fx.fireworkSparks,
      {
        speedMin = 30,
        speedMax = 150,
        lifeMin = 0.7,
        lifeMax = 1.4,
        size = 1.8,
        drag = 1.5,
        gravity = 70,
        color = { 1, 1, 1, 1 },
        color2 = FIREWORK_COLORS[hue],
      }
    )
    sfx.play("pop", 0.8 + random() * 0.5)
  end
  -- A hop every so often: the player is happy too.
  local p = g.player
  if p.onGround and random() < dt * 2 then
    player.pressJump(p)
  end
end

local function updateEffects(g, dt)
  particles.update(dust, dt)
  particles.update(sparks, dt)
  for i = #popups, 1, -1 do
    local pop = popups[i]
    pop.age, pop.y = pop.age + dt, pop.y - 25 * dt
    if pop.age > POPUP_LIFE then
      table.remove(popups, i)
    end
  end
  g.fx.shake = math.max(0, g.fx.shake - g.fx.shakeDecay * dt)

  -- Coins twinkle now and then, so they catch the eye from across the screen.
  for _, c in ipairs(g.coins) do
    if random() < g.fx.coinSparkle * dt then
      particles.add(sparks, {
        x = c.x + (random() - 0.5) * c.r * 3,
        y = c.y + (random() - 0.5) * c.r * 3,
        life = 0.5,
        size = 3,
        color = { 1, 1, 0.8, 1 },
        shape = "twinkle",
      })
    end
  end
end

local HARD_LANDING = 200 -- landings faster than this kick up dust
local FULL_DUST_LANDING = 450 -- landing speed that kicks up all of dustCount
local RUN_DUST_SPEED = 120 -- running faster than this leaves a dust trail

-- Dust and sounds for what the player did this frame.
local function playerEffects(g, jumped, landed, dt)
  local p = g.player
  local feetX, feetY = p.x + p.w / 2, p.y + p.h
  if jumped then
    puff(feetX, feetY, 4)
    sfx.play("jump", 1, 0.04)
  end
  if landed and landed > HARD_LANDING then
    puff(feetX, feetY, math.floor(g.fx.dustCount * math.min(1, landed / FULL_DUST_LANDING)))
    sfx.play("land", 1, 0.1)
  end
  if p.onGround and math.abs(p.vx) > RUN_DUST_SPEED and random() < dt * 12 then
    puff(feetX - p.facing * 4, feetY, 1, 0.8)
  end
end

local function reachFlag(g)
  g.state = "won"
  particles.burst(sparks, g.flag.x, g.flag.y, g.fx.confetti, {
    angle = -math.pi / 2,
    spread = 2.2,
    speedMin = 120,
    speedMax = 320,
    lifeMin = 1.5,
    lifeMax = 3,
    size = 4,
    drag = 1.8,
    gravity = 160,
    spin = 10,
    color = { 1, 0.85, 0.4, 1 },
    color2 = { 1, 0.4, 0.7 },
    shape = "square",
  })
  shake(g, 0.4)
  sfx.play("win")
end

-- Moves the player and applies the level's rules to it. Returns "won" on the
-- frame it reaches the flag.
local function updatePlayer(g, dt)
  local p = g.player
  local jumped, landed = player.update(p, dt, g.platforms, g.state == "play")
  playerEffects(g, jumped, landed, dt)
  if p.y > M.LEVEL_HEIGHT + FALL_MARGIN then
    die(g)
  elseif g.state == "play" then
    collectCoins(g)
    hitEnemies(g, dt)
  end
  if g.state == "play" and aabb.overlaps(p, g.flag) then
    reachFlag(g)
    return "won"
  end
end

-- Returns "won" on the frame the player reaches the flag.
function M.update(g, dt)
  local result
  g.clock = g.clock + dt
  if g.state == "play" then
    g.time = g.time + dt
  end

  if g.respawnIn > 0 then
    g.respawnIn = math.max(0, g.respawnIn - dt)
    if g.respawnIn == 0 then
      respawn(g)
    end
  else
    result = updatePlayer(g, dt)
  end

  enemies.update(g.enemies, dt)
  if g.state == "won" then
    celebrate(g, dt)
  end
  updateEffects(g, dt)
  camera.follow(g.camera, g.player, dt, M.LEVEL_WIDTH, M.LEVEL_HEIGHT)
  return result
end

local function drawPlatforms(g)
  local gr = love.graphics
  for _, plat in ipairs(g.platforms) do
    gr.setColor(0.36, 0.25, 0.3, 1)
    gr.rectangle("fill", plat.x, plat.y, plat.w, plat.h)
    -- Pebbles at fixed spots along the platform, so they scroll with it.
    gr.setColor(0.28, 0.19, 0.25, 1)
    for x = plat.x + 7, plat.x + plat.w - 6, 23 do
      local depth = ((x * 7) % 13) / 13
      if plat.h > 16 then
        gr.rectangle("fill", x, plat.y + 9 + depth * (plat.h - 16), 4, 3)
      end
    end
    gr.setColor(0.45, 0.8, 0.45, 1)
    gr.rectangle("fill", plat.x, plat.y, plat.w, 4)
    gr.setColor(0.65, 0.95, 0.55, 1)
    gr.rectangle("fill", plat.x, plat.y, plat.w, 1.5)
  end
end

local function drawCoins(g)
  local gr = love.graphics
  for i, c in ipairs(g.coins) do
    -- Bob and spin are visual only, so the coin's x, y stay put for picking.
    local y = c.y + math.sin(g.clock * 3 + i) * 2.5
    local spin = math.abs(math.cos(g.clock * 2.5 + i * 0.7))
    gr.setBlendMode("add")
    gr.setColor(1, 0.8, 0.2, 0.18)
    gr.circle("fill", c.x, y, c.r * 2, 20)
    gr.setBlendMode("alpha")
    gr.setColor(0.85, 0.55, 0.1, 1)
    gr.ellipse("fill", c.x, y, c.r * math.max(0.15, spin), c.r, 20)
    gr.setColor(1, 0.88, 0.25, 1)
    gr.ellipse("fill", c.x, y, c.r * math.max(0.1, spin) * 0.7, c.r * 0.7, 20)
  end
end

local function drawFlag(g)
  local gr = love.graphics
  local f = g.flag
  gr.setColor(0.9, 0.9, 0.95, 1)
  gr.rectangle("fill", f.x + f.w / 2 - 1.5, f.y, 3, f.h)
  gr.circle("fill", f.x + f.w / 2, f.y, 3, 12)
  -- The cloth waves as strips of convex quads; it rises up the pole once reached.
  local raise = g.state == "won" and math.min(1, g.celebration * 1.5) or 0
  local top = f.y + 4 + (1 - raise) * 26
  local wave = g.state == "won" and 8 or 3
  gr.setColor(g.state == "won" and { 0.4, 1, 0.55, 1 } or { 0.9, 0.35, 0.4, 1 })
  local x0 = f.x + f.w / 2 + 1
  for i = 0, 5 do
    local xa, xb = x0 + i * 5, x0 + (i + 1) * 5
    local ya = math.sin(g.clock * wave - i * 0.8) * i * 0.6
    local yb = math.sin(g.clock * wave - (i + 1) * 0.8) * (i + 1) * 0.6
    local ha, hb = 16 - i * 1.6, 16 - (i + 1) * 1.6
    gr.polygon("fill", xa, top + ya, xb, top + yb, xb, top + yb + hb, xa, top + ya + ha)
  end
end

local function drawPopups()
  local gr = love.graphics
  for _, pop in ipairs(popups) do
    local c = pop.color
    gr.setColor(c[1], c[2], c[3], 1 - (pop.age / POPUP_LIFE) ^ 2)
    text.print(pop.text, pop.x - 40, pop.y, 9, "center", 80)
  end
end

-- Screen-space backdrop, then the world through the camera, with shake.
function M.draw(g)
  local gr = love.graphics
  local cam = g.camera
  view.drawVirtual(function()
    backdrop.draw(g.backdrop, cam.x, g.clock)
  end)
  view.drawWorld(function()
    local t = g.fx.shake
    if t > 0 then
      local amount = g.fx.shakeStrength * t * t
      gr.translate(
        (love.math.noise(g.clock * 30, 1) * 2 - 1) * amount,
        (love.math.noise(1, g.clock * 30) * 2 - 1) * amount
      )
    end
    drawPlatforms(g)
    drawFlag(g)
    drawCoins(g)
    for _, e in ipairs(g.enemies) do
      enemies.draw(e)
    end
    particles.draw(dust)
    if g.respawnIn == 0 then
      player.draw(g.player, g.clock)
    end
    gr.setBlendMode("add")
    particles.draw(sparks)
    gr.setBlendMode("alpha")
    drawPopups()
  end)
end

return M
