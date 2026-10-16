-- Original implementation. This module has no dependency on LÖVE.
local M = {}
local physics = require("src.physics")
M.field = { x = 42, y = 130, w = 1000, h = 680 }
local schedule = {
  { 0, 3, 0.25, "drone" },
  { 3, 2, 0.6, "gunner" },
  { 5, 3, 0.25, "drone" },
  { 6, 2, 0.4, "weaver" },
  { 10, 4, 0.2, "drone" },
  { 14, 2, 0.4, "weaver" },
  { 18, 3, 0.4, "gunner" },
  { 20, 3, 0.25, "drone" },
  { 22, 2, 0.4, "weaver" },
}
local function clamp(n, a, b)
  return math.max(a, math.min(b, n))
end
local function distance(a, b)
  local x, y = a.x - b.x, a.y - b.y
  return math.sqrt(x * x + y * y)
end
function M.new(seed, upgrades, sector, endless)
  local g = {
    state = "flight",
    time = 0,
    duration = 30,
    kills = 0,
    spawned = 0,
    shots = 0,
    hits = 0,
    gems = 10,
    xp = 0,
    level = 1,
    enemies = {},
    bullets = {},
    hostile = {},
    pickups = {},
    particles = {},
    effects = {},
    events = {},
    nextSpawn = 1,
    rng = seed or 42,
    shake = 0,
    flash = 0,
    upgrades = upgrades or { power = 0, drive = 0, magnet = 0, lasers = 0 },
    spawnQueue = {},
  }
  g.sector = sector or 1
  g.endless = endless or false
  g.pattern = (g.sector - 1) % 3 + 1
  g.cycle = math.floor((g.sector - 1) / 3)
  g.duration = ({ 30, 38, 90 })[g.pattern] + math.min(20, g.cycle * 2)
  g.banner = ""
  g.bannerTime = 0
  g.turbo = 0
  g.split = 0
  g.transition = 0
  g.pulseCooldown = 0
  g.pulseRing = 0
  g.bossDefeated = false
  local u = g.upgrades
  u.lasers = u.lasers or 0
  g.player = {
    x = 542,
    y = 700,
    r = 16,
    hp = 40,
    maxHp = 40,
    speed = 300 + u.drive * 35,
    damage = 3 + u.power,
    fireRate = 2.8,
    range = 480,
    lasers = 1 + u.lasers,
    magnet = 96 + u.magnet * 40,
    invulnerable = 0,
    cooldown = 0,
    tilt = 0,
  }
  local batches = schedule
  if g.pattern == 2 then
    batches = {
      { 0, 4, 0.3, "weaver" },
      { 4, 3, 0.5, "gunner" },
      { 9, 5, 0.2, "drone" },
      { 14, 4, 0.4, "weaver" },
      { 19, 3, 0.5, "gunner" },
      { 24, 5, 0.25, "weaver" },
      { 30, 4, 0.25, "drone" },
    }
  elseif g.pattern == 3 then
    batches = {
      { 1, 1, 0, "boss" },
      { 8, 3, 0.4, "weaver" },
      { 18, 3, 0.5, "gunner" },
      { 30, 4, 0.3, "drone" },
      { 44, 4, 0.3, "weaver" },
      { 58, 3, 0.5, "gunner" },
    }
  end
  if g.cycle > 0 then
    local expanded = {}
    for _, b in ipairs(batches) do
      expanded[#expanded + 1] = { b[1], b[2], b[3], b[4] }
    end
    for n = 1, math.min(10, g.cycle * 2) do
      expanded[#expanded + 1] = { 3 + n * 2, 1, 0, n % 2 == 0 and "gunner" or "weaver" }
    end
    batches = expanded
  end
  for _, batch in ipairs(batches) do
    for n = 1, batch[2] do
      g.spawnQueue[#g.spawnQueue + 1] = { at = batch[1] + (n - 1) * batch[3], kind = batch[4] }
    end
  end
  table.sort(g.spawnQueue, function(a, b)
    return a.at < b.at
  end)
  return g
end
local function random(g)
  g.rng = (g.rng * 48271) % 2147483647
  return g.rng / 2147483647
end
local function event(g, kind)
  g.events[#g.events + 1] = kind
end
function M.burst(g, x, y, color, count)
  if (count or 18) >= 15 then
    g.effects[#g.effects + 1] = { x = x, y = y, age = 0, size = (count or 18) > 40 and 180 or 75 }
  end
  for _ = 1, count or 18 do
    local a = random(g) * math.pi * 2
    local speed = 35 + random(g) * 150
    g.particles[#g.particles + 1] = {
      x = x,
      y = y,
      vx = math.cos(a) * speed,
      vy = math.sin(a) * speed,
      life = 0.3 + random(g) * 0.5,
      max = 0.8,
      color = color,
    }
  end
end
function M.spawn(g, kind)
  local f = M.field
  local x = f.x + 80 + random(g) * (f.w - 160)
  local e = {
    kind = kind,
    x = x,
    baseX = x,
    y = f.y - 22,
    r = kind == "drone" and 20 or 17,
    hp = kind == "drone" and 11 or 6,
    maxHp = kind == "drone" and 11 or 6,
    speed = kind == "drone" and 45 or 55,
    phase = random(g) * 6.28,
    age = 0,
    flash = 0,
    fire = 0.7 + random(g) * 0.8,
  }
  if kind == "gunner" then
    e.hp = 14
    e.maxHp = 14
    e.speed = 35
    e.r = 22
    e.fire = 1.8
  end
  if kind == "boss" then
    e.hp = 540
    e.maxHp = 540
    e.speed = 60
    e.r = 62
    e.x = f.x + f.w / 2
    e.baseX = e.x
    e.fire = 2
  end
  e.hp = math.floor(e.hp * (1 + g.cycle * 0.7 + g.cycle * g.cycle * 0.18))
  e.maxHp = e.hp
  e.speed = e.speed * math.min(1.7, 1 + g.cycle * 0.08)
  g.enemies[#g.enemies + 1] = e
  g.spawned = g.spawned + 1
end
local function destroy(g, e, reward)
  if e.dead then
    return
  end
  e.dead = true
  if e.kind == "boss" then
    g.bossDefeated = true
  end
  M.burst(g, e.x, e.y, e.kind == "drone" and "orange" or "purple", 22)
  if reward then
    g.kills = g.kills + 1
    g.pickups[#g.pickups + 1] = { x = e.x, y = e.y, r = 7, age = 0, value = 2, kind = "salvage" }
    -- Special equipment is a spaced reward, not a second drop from most kills.
    local kind
    if g.kills % 7 == 0 then
      local rotation = math.floor(g.kills / 7) % 3
      kind = rotation == 1 and "turbo" or (rotation == 2 and "split" or "hull")
    end
    local packs = 0
    for _, pickup in ipairs(g.pickups) do
      if pickup.kind ~= "salvage" then
        packs = packs + 1
      end
    end
    if kind == "hull" and g.player.hp >= g.player.maxHp - 4 then
      kind = nil
    end
    if kind and packs < 2 and g.time >= (g.nextPackAt or 0) then
      g.nextPackAt = g.time + 5
      g.pickups[#g.pickups + 1] = { x = e.x + 23, y = e.y, r = 14, age = 0, value = 0, kind = kind }
    end
    event(g, "kill")
  end
end
function M.hurt(g, amount)
  local p = g.player
  if p.invulnerable > 0 or g.state ~= "flight" then
    return
  end
  p.hp = math.max(0, p.hp - amount)
  p.invulnerable = 1.1
  g.shake = 0.35
  g.flash = 0.24
  M.burst(g, p.x, p.y, "cyan", 15)
  event(g, "hurt")
  if p.hp <= 0 then
    g.state = "lost"
    event(g, "lost")
  end
end
function M.stats(g)
  local p = g.player
  local beams = math.min(5, p.lasers + (g.split > 0 and 1 or 0))
  return {
    damage = p.damage,
    beams = beams,
    speed = p.speed * (g.turbo > 0 and 1.45 or 1),
    magnet = p.magnet,
    dps = p.damage * beams * p.fireRate,
  }
end
function M.cost(g, kind)
  if kind == "repair" then
    return 8
  end
  local rank = g.upgrades[kind] or 0
  return (kind == "lasers" and 16 or 12) + rank * (kind == "lasers" and 8 or 4)
end
function M.buy(g, kind)
  if g.state ~= "dock" then
    return false
  end
  local cost = M.cost(g, kind)
  if g.gems < cost then
    return false
  end
  local p = g.player
  local fields =
    { power = "damage", lasers = "lasers", drive = "speed", magnet = "magnet", repair = "hp" }
  local labels = {
    power = "DAMAGE",
    lasers = "BEAMS",
    drive = "SPEED",
    magnet = "PICKUP RADIUS",
    repair = "HULL",
  }
  local field = fields[kind]
  local before = field and p[field]
  if kind == "repair" then
    if g.player.hp >= g.player.maxHp then
      return false
    end
    g.player.hp = math.min(g.player.maxHp, g.player.hp + 20)
  elseif g.upgrades[kind] ~= nil then
    local cap = kind == "power" and math.huge or (kind == "lasers" and 3 or 6)
    if g.upgrades[kind] >= cap then
      return false
    end
    g.upgrades[kind] = g.upgrades[kind] + 1
    local amounts = { power = 1, lasers = 1, drive = 35, magnet = 40 }
    p[field] = p[field] + amounts[kind]
  else
    return false
  end
  g.purchase = { kind = kind, label = labels[kind], before = before, after = p[field] }
  g.gems = g.gems - cost
  event(g, "buy")
  return true
end
function M.pulse(g)
  if g.state ~= "flight" or g.pulseCooldown > 0 then
    return false
  end
  g.pulseCooldown = 8
  g.pulseRing = 0.6
  g.hostile = {}
  for _, e in ipairs(g.enemies) do
    if distance(e, g.player) < 240 then
      e.hp = e.hp - 10
      e.flash = 0.15
      if e.hp <= 0 then
        destroy(g, e, true)
      end
    end
  end
  event(g, "level")
  return true
end
function M.advance(g)
  assert(g.state == "dock" and (g.sector < 3 or g.endless), "finish the current sector first")
  local n = M.new(g.rng, g.upgrades, g.sector + 1, g.endless)
  n.xp = g.xp
  n.level = g.level
  n.player.damage = n.player.damage + (n.level - 1) * 0.5
  n.gems = g.gems
  n.player.hp = math.min(n.player.maxHp, g.player.hp + 12)
  n.totalKills = (g.totalKills or 0) + g.kills
  return n
end
local function collect(g, v)
  local p = g.player
  if v.kind == "turbo" then
    g.turbo = 7
    g.banner = "TURBO DRIVE / SPEED +45%"
    g.bannerTime = 2
    event(g, "level")
  elseif v.kind == "split" then
    g.split = 9
    g.banner = "PRISM ARRAY / EXTRA LASER"
    g.bannerTime = 2
    event(g, "level")
  elseif v.kind == "hull" then
    p.hp = math.min(p.maxHp, p.hp + 8)
    g.banner = "HULL PATCH / +8"
    g.bannerTime = 2
  else
    g.gems = g.gems + v.value
    g.xp = g.xp + 1
    event(g, "pickup")
    if g.xp >= g.level * 4 then
      g.level = g.level + 1
      p.damage = p.damage + 0.5
      event(g, "level")
    end
  end
end
function M.update(g, dt, input)
  input = input or {}
  dt = math.min(dt, 0.05)
  g.events = {}
  for i = #g.effects, 1, -1 do
    local effect = g.effects[i]
    effect.age = effect.age + dt
    if effect.age >= 16 / 24 then
      table.remove(g.effects, i)
    end
  end
  g.shake = math.max(0, g.shake - dt)
  g.flash = math.max(0, g.flash - dt)
  for i = #g.particles, 1, -1 do
    local p = g.particles[i]
    p.life = p.life - dt
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    if p.life <= 0 then
      table.remove(g.particles, i)
    end
  end
  if g.state == "clearing" then
    g.transition = g.transition + dt
    for _, e in ipairs(g.enemies) do
      e.y = e.y - 280 * dt
    end
    for i = #g.pickups, 1, -1 do
      local v = g.pickups[i]
      local d = distance(v, g.player)
      local step = math.min(d, dt * 700)
      v.x = v.x + (g.player.x - v.x) / math.max(1, d) * step
      v.y = v.y + (g.player.y - v.y) / math.max(1, d) * step
      if d < 25 then
        collect(g, v)
        table.remove(g.pickups, i)
      end
    end
    if g.transition >= 3.2 then
      for _, v in ipairs(g.pickups) do
        collect(g, v)
      end
      g.pickups = {}
      g.enemies = {}
      g.gems = g.gems + 10 + g.cycle * 2
      g.turbo = 0
      g.split = 0
      g.state = g.pattern == 3 and not g.endless and "victory" or "dock"
    end
    return
  end
  if g.state ~= "flight" then
    return
  end
  local p = g.player
  local f = M.field
  g.turbo = math.max(0, g.turbo - dt)
  g.split = math.max(0, g.split - dt)
  g.bannerTime = math.max(0, g.bannerTime - dt)
  g.time = g.time + dt
  g.pulseCooldown = math.max(0, g.pulseCooldown - dt)
  g.pulseRing = math.max(0, g.pulseRing - dt)
  p.invulnerable = math.max(0, p.invulnerable - dt)
  local dx, dy = input.x or 0, input.y or 0
  local length = math.sqrt(dx * dx + dy * dy)
  if length > 1 then
    dx, dy = dx / length, dy / length
  end
  p.x = clamp(p.x + dx * p.speed * (g.turbo > 0 and 1.45 or 1) * dt, f.x + 24, f.x + f.w - 24)
  p.y = clamp(p.y + dy * p.speed * (g.turbo > 0 and 1.45 or 1) * dt, f.y + 30, f.y + f.h - 25)
  p.tilt = p.tilt + (dx * 0.22 - p.tilt) * math.min(1, dt * 9)
  while g.spawnQueue[g.nextSpawn] and g.time >= g.spawnQueue[g.nextSpawn].at do
    M.spawn(g, g.spawnQueue[g.nextSpawn].kind)
    g.nextSpawn = g.nextSpawn + 1
  end
  local target, nearest = nil, p.range
  for _, e in ipairs(g.enemies) do
    e.age = e.age + dt
    e.y = e.y + e.speed * dt
    e.flash = math.max(0, e.flash - dt)
    if e.kind == "boss" then
      e.y = math.min(e.y, f.y + 140)
      e.x = e.baseX + math.sin(e.age * 0.7) * 280
    end
    if not e.dead and e.y > f.y + 30 and e.y < f.y + f.h - 30 then
      e.fire = e.fire - dt
      if e.fire <= 0 then
        local count = e.kind == "boss" and (e.hp < e.maxHp / 2 and 9 or 5)
          or (e.kind == "gunner" and 3 or 1)
        local shotSpeed = 175 + (g.pattern - 1) * 20 + math.min(100, g.cycle * 12)
        local angle = math.atan2(p.y - e.y, p.x - e.x)
        for n = 1, count do
          local a = angle + (n - (count + 1) / 2) * 0.19
          g.hostile[#g.hostile + 1] = {
            x = e.x,
            y = e.y,
            vx = math.cos(a) * shotSpeed,
            vy = math.sin(a) * shotSpeed,
            r = 6,
          }
        end
        local interval = e.kind == "boss" and (e.hp < e.maxHp / 2 and 1.15 or 1.8)
          or (e.kind == "gunner" and 2.2 or (e.kind == "weaver" and 3.4 or 4.2))
        e.fire = interval / math.min(1.8, 1 + (g.pattern - 1) * 0.12 + g.cycle * 0.1)
      end
    end
    if e.kind == "weaver" then
      e.x = clamp(e.baseX + math.sin(e.age * 2 + e.phase) * 110, f.x + 25, f.x + f.w - 25)
    end
    local d = distance(e, p)
    if d < nearest and e.y >= f.y and not e.dead then
      target = e
      nearest = d
    end
    if d < e.r + p.r and not e.dead then
      M.hurt(g, 15)
      if e.kind ~= "boss" then
        destroy(g, e, false)
      end
    end
    if e.y > f.y + f.h + 35 then
      e.dead = true
    end
  end
  p.cooldown = p.cooldown - dt
  if target and p.cooldown <= 0 then
    local d = math.max(1, distance(p, target))
    local vx, vy = (target.x - p.x) / d, (target.y - p.y) / d
    local count = math.min(5, p.lasers + (g.split > 0 and 1 or 0))
    for n = 1, count do
      local angle = math.atan2(vy, vx) + (n - (count + 1) / 2) * 0.065
      g.bullets[#g.bullets + 1] = {
        x = p.x + (n - (count + 1) / 2) * 9,
        y = p.y - 8,
        vx = math.cos(angle) * 425,
        vy = math.sin(angle) * 425,
        travel = 0,
        r = 4,
        damage = p.damage,
      }
    end
    p.cooldown = 1 / math.max(0.1, p.fireRate)
    g.shots = g.shots + 1
    event(g, "shot")
  end
  for i = #g.bullets, 1, -1 do
    local b = g.bullets[i]
    local oldX, oldY = b.x, b.y
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt
    b.travel = b.travel + 425 * dt
    local hit, hitTime
    for _, enemy in ipairs(g.enemies) do
      local t = not enemy.dead
        and physics.sweepCircle(oldX, oldY, b.x, b.y, enemy.x, enemy.y, enemy.r + b.r)
      if t and (not hitTime or t < hitTime) then
        hit, hitTime = enemy, t
      end
    end
    if hit then
      hit.hp = hit.hp - b.damage
      hit.flash = 0.12
      b.dead = true
      g.hits = g.hits + 1
      M.burst(g, oldX + (b.x - oldX) * hitTime, oldY + (b.y - oldY) * hitTime, "cyan", 4)
      if hit.hp <= 0 then
        destroy(g, hit, true)
      end
    end
    if b.dead or b.travel > p.range then
      table.remove(g.bullets, i)
    end
  end
  for i = #g.hostile, 1, -1 do
    local b = g.hostile[i]
    local oldX, oldY = b.x, b.y
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt
    if physics.sweepCircle(oldX, oldY, b.x, b.y, p.x, p.y, p.r + b.r) then
      M.hurt(g, 6)
      b.dead = true
    end
    if
      b.dead
      or b.x < f.x - 30
      or b.x > f.x + f.w + 30
      or b.y < f.y - 30
      or b.y > f.y + f.h + 30
    then
      table.remove(g.hostile, i)
    end
  end
  for i = #g.enemies, 1, -1 do
    if g.enemies[i].dead then
      table.remove(g.enemies, i)
    end
  end
  for i = #g.pickups, 1, -1 do
    local v = g.pickups[i]
    v.age = v.age + dt
    local d = distance(v, p)
    if d < p.magnet then
      local step = math.min(d, dt * 360)
      v.x = v.x + (p.x - v.x) / math.max(1, d) * step
      v.y = v.y + (p.y - v.y) / math.max(1, d) * step
    else
      v.y = v.y + 12 * dt
    end
    if distance(v, p) < 22 then
      collect(g, v)
      table.remove(g.pickups, i)
    elseif v.y > f.y + f.h + 20 or (v.kind ~= "salvage" and v.age >= 10) then
      table.remove(g.pickups, i)
    end
  end
  if ((g.pattern < 3 and g.time >= g.duration) or g.bossDefeated) and g.state == "flight" then
    g.time = math.min(g.time, g.duration)
    g.state = "clearing"
    g.transition = 0
    g.bullets = {}
    g.hostile = {}
    event(g, "complete")
    if g.bossDefeated then
      g.shake = 0.6
      M.burst(g, 542, 300, "purple", 90)
    end
  end
  if g.pattern == 3 and g.time >= g.duration and g.state == "flight" then
    M.hurt(g, 6)
  end
end
return M
