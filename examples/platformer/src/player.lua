-- The player: run, jump, collide, and look alive doing it.
local aabb = require("src.aabb")

local M = {}

function M.new(x, y)
  return {
    x = x,
    y = y,
    w = 14,
    h = 20,
    vx = 0,
    vy = 0,
    -- Movement tunables. Drag them in loupe while playing.
    speed = 150, -- top run speed
    accel = 1500, -- speeding up on the ground
    airAccel = 950, -- less control in the air
    friction = 1800, -- slowing down with no input on the ground
    jump = 400, -- launch speed: peaks around 85px, enough for every ledge
    gravity = 900,
    fallGravity = 1.5, -- gravity multiplier while falling: floaty up, snappy down
    maxFall = 560,
    jumpCut = 0.45, -- releasing jump early multiplies upward speed by this
    coyoteTime = 0.1, -- you can still jump this long after running off a ledge
    jumpBuffer = 0.12, -- a jump pressed this early before landing still happens
    squash = 0.35, -- squash-and-stretch strength; 0 turns it off
    color = { 0.95, 0.75, 0.3, 1 },
    -- State.
    onGround = false,
    facing = 1,
    coyote = 0,
    buffered = 0,
    rising = false,
    scaleX = 1,
    scaleY = 1,
    stride = 0,
  }
end

-- The tall, thin stretch of leaving the ground (a jump or a stomp bounce).
function M.stretch(p)
  p.scaleX, p.scaleY = 1 - p.squash * 0.6, 1 + p.squash
end

-- Called on the key press, not polled: buffering needs the moment of the press.
function M.pressJump(p)
  p.buffered = p.jumpBuffer
end

local function approach(value, target, step)
  if value < target then
    return math.min(target, value + step)
  end
  return math.max(target, value - step)
end

local function moveAndCollide(p, platforms, dt)
  -- Resolve each axis separately so the player slides along walls.
  p.x = p.x + p.vx * dt
  for _, plat in ipairs(platforms) do
    if aabb.overlaps(p, plat) then
      p.x = p.vx > 0 and plat.x - p.w or plat.x + plat.w
      p.vx = 0
    end
  end

  p.y = p.y + p.vy * dt
  p.onGround = false
  for _, plat in ipairs(platforms) do
    if aabb.overlaps(p, plat) then
      if p.vy > 0 then
        p.y, p.onGround = plat.y - p.h, true
      else
        p.y = plat.y + plat.h
      end
      p.vy = 0
    end
  end
end

-- -1, 0 or 1: the direction the run keys ask for.
local function inputDirection(controls)
  local kb = love.keyboard
  local dir = 0
  if controls then
    if kb.isDown("left", "a") then
      dir = dir - 1
    end
    if kb.isDown("right", "d") then
      dir = dir + 1
    end
  end
  return dir
end

local AIR_COAST = 0.4 -- with no input in the air, slow down at this share of airAccel

local function run(p, dir, dt)
  if dir ~= 0 then
    p.facing = dir
  end
  local rate
  if dir ~= 0 then
    rate = p.onGround and p.accel or p.airAccel
  else
    rate = p.onGround and p.friction or p.airAccel * AIR_COAST
  end
  p.vx = approach(p.vx, dir * p.speed, rate * dt)
end

-- Jumps when a buffered press meets coyote time. Returns true if it jumped.
local function tryJump(p, dt)
  -- Coyote time: being on the ground recharges a short grace window.
  p.coyote = p.onGround and p.coyoteTime or math.max(0, p.coyote - dt)
  p.buffered = math.max(0, p.buffered - dt)
  if not (p.buffered > 0 and p.coyote > 0) then
    return false
  end
  p.vy = -p.jump
  p.buffered, p.coyote = 0, 0
  p.onGround, p.rising = false, true
  M.stretch(p)
  return true
end

local function fall(p, controls, dt)
  -- Variable height: letting go early cuts the climb short.
  local held = controls and love.keyboard.isDown("space", "up", "w")
  if p.rising and p.vy < 0 and not held then
    p.vy = p.vy * p.jumpCut
    p.rising = false
  end
  if p.vy >= 0 then
    p.rising = false
  end
  local gravity = p.gravity * (p.vy > 0 and p.fallGravity or 1)
  p.vy = math.min(p.maxFall, p.vy + gravity * dt)
end

local FULL_SQUASH_LANDING = 500 -- fall speed that gets the full landing squash
local SQUASH_RECOVERY = 14 -- how fast squash eases back, per second

-- Moves the player. Returns the fall speed if it touched down this frame.
local function move(p, platforms, dt)
  local wasOnGround, fallSpeed = p.onGround, p.vy
  moveAndCollide(p, platforms, dt)
  if p.onGround and not wasOnGround then
    local k = p.squash * math.min(1, fallSpeed / FULL_SQUASH_LANDING)
    p.scaleX, p.scaleY = 1 + k, 1 - k * 0.8
    return fallSpeed
  end
  return nil
end

-- Ease the squash back to normal; stride drives the running bob.
local function animate(p, dt)
  local ease = math.min(1, dt * SQUASH_RECOVERY)
  p.scaleX = p.scaleX + (1 - p.scaleX) * ease
  p.scaleY = p.scaleY + (1 - p.scaleY) * ease
  if p.onGround then
    p.stride = p.stride + math.abs(p.vx) * dt
  end
end

-- Returns two values: true if the player jumped this frame, and the landing
-- speed if they touched down this frame (nil otherwise). `controls` is false
-- during the victory lap.
function M.update(p, dt, platforms, controls)
  run(p, inputDirection(controls), dt)
  local jumped = tryJump(p, dt)
  fall(p, controls, dt)
  local landed = move(p, platforms, dt)
  animate(p, dt)
  return jumped, landed
end

function M.draw(p, time)
  local g = love.graphics
  local w, h = p.w, p.h
  local running = p.onGround and math.abs(p.vx) > 20
  local bob = running and math.abs(math.sin(p.stride * 0.18)) * 1.5 or 0

  g.push()
  -- Scale around the feet, so squashing never lifts the player off the ground.
  g.translate(p.x + w / 2, p.y + h)
  g.scale(p.scaleX, p.scaleY)
  g.translate(0, -bob)

  -- Feet, alternating while running.
  local step = running and math.sin(p.stride * 0.18) * 2.5 or 0
  g.setColor(0.25, 0.15, 0.12, 1)
  g.rectangle("fill", -5 + step, -3, 4, 3, 1, 1)
  g.rectangle("fill", 1 - step, -3, 4, 3, 1, 1)

  -- Body with a darker underside and a highlight: reads as round at this size.
  local c = p.color
  g.setColor(c[1] * 0.7, c[2] * 0.7, c[3] * 0.7, c[4] or 1)
  g.rectangle("fill", -w / 2, -h, w, h - 2, 5, 5)
  g.setColor(c)
  g.rectangle("fill", -w / 2, -h, w, h - 5, 5, 5)
  g.setColor(1, 1, 1, 0.35)
  g.rectangle("fill", -w / 2 + 2, -h + 2, 3, 6, 1.5, 1.5)

  -- Eyes look where we're going; a quick blink every few seconds.
  local ex, ey = p.facing * 2.5, -h + 7
  if (time % 3.7) < 0.12 then
    g.setColor(0.1, 0.05, 0.1, 1)
    g.rectangle("fill", ex - 4.5, ey, 3, 1)
    g.rectangle("fill", ex + 1.5, ey, 3, 1)
  else
    g.setColor(1, 1, 1, 1)
    g.circle("fill", ex - 3, ey, 2.3, 10)
    g.circle("fill", ex + 3, ey, 2.3, 10)
    local look = p.vy < -50 and -0.8 or (p.vy > 150 and 0.8 or 0)
    g.setColor(0.1, 0.05, 0.1, 1)
    g.circle("fill", ex - 3 + p.facing * 0.9, ey + look, 1.2, 8)
    g.circle("fill", ex + 3 + p.facing * 0.9, ey + look, 1.2, 8)
  end
  g.pop()
end

return M
