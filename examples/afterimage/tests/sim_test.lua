local sim = require("src.sim")
local g = sim.new(42)
for _ = 1, 1801 do
  sim.update(g, 1 / 60, {})
end
assert(#g.spawnQueue == 24, "opening sector schedules 24 mixed enemies")
for _ = 1, 200 do
  sim.update(g, 1 / 60, {})
end
assert(g.state == "dock" or g.state == "lost", "run resolves")
g = sim.new(42)
g.player.x = 100
g.player.y = 500
sim.spawn(g, "drone")
local e = g.enemies[1]
e.x = 100
e.baseX = 100
e.y = 400
e.speed = 0
for _ = 1, 180 do
  sim.update(g, 1 / 60, {})
end
assert(g.kills == 1, "auto aim destroys target")
assert(g.shots >= 4, "11hp needs four 3-damage shots")
g = sim.new(4)
sim.hurt(g, 15)
sim.hurt(g, 15)
assert(g.player.hp == 25, "invulnerability window")
g.player.invulnerable = 0
sim.hurt(g, 40)
assert(g.state == "lost", "death state")
g = sim.new(1)
g.duration = 0.1
for _ = 1, 210 do
  sim.update(g, 1 / 60, {})
end
assert(g.state == "dock" and g.gems == 20, "completion bonus")
assert(sim.buy(g, "power") and g.upgrades.power == 1 and g.gems == 8, "purchase")
assert(not sim.buy(g, "drive"), "insufficient funds")
local nextGame = sim.new(1, g.upgrades)
assert(nextGame.player.damage == 4, "upgrade survives replay")
g = sim.new(1)
g.player.x = 50
g.player.y = 150
for _ = 1, 100 do
  sim.update(g, 1 / 60, { x = -1, y = -1 })
end
assert(g.player.x >= 66 and g.player.y >= 160, "arena bounds")
print("PASS: wave schedule, combat, damage, completion, shop, replay, bounds")
g = sim.new(1, nil, 2)
g.duration = 0.05
for _ = 1, 210 do
  sim.update(g, 1 / 60, {})
end
assert(g.state == "dock", "second sector completes")
local third = sim.advance(g)
assert(third.sector == 3, "sector progression")
sim.spawn(third, "boss")
local boss = third.enemies[1]
boss.y = 300
boss.speed = 0
boss.hp = 1
third.player.x = boss.x
third.player.y = 410
assert(sim.pulse(third), "pulse ready")
assert(not sim.pulse(third), "pulse cooldown")
sim.update(third, 1 / 60, {})
for _ = 1, 200 do
  sim.update(third, 1 / 60, {})
end
assert(third.state == "victory", "boss death wins final sector")
g = sim.new(1, nil, 3)
sim.spawn(g, "boss")
g.enemies[1].y = 280
for _ = 1, 180 do
  sim.update(g, 1 / 60, {})
end
assert(#g.hostile > 0, "boss emits attack pattern")
print("PASS: sector progression, pulse cooldown, boss attacks, final victory")

g = sim.new(42, nil, 3, true)
g.state = "dock"
local fourth = sim.advance(g)
assert(
  fourth.sector == 4 and fourth.pattern == 1 and fourth.cycle == 1,
  "endless advances past story"
)
sim.spawn(fourth, "drone")
assert(fourth.enemies[1].hp > 11, "enemies scale")
g = sim.new(1)
g.state = "dock"
g.gems = 20
assert(sim.buy(g, "lasers"))
assert(sim.advance(g).player.lasers == 2, "beam upgrade persists")
g = sim.new(1)
g.pickups = { { x = g.player.x, y = g.player.y, kind = "turbo", value = 0, age = 0 } }
sim.update(g, 1 / 60, {})
assert(g.turbo > 0, "turbo pickup activates")
g.pickups = { { x = g.player.x, y = g.player.y, kind = "split", value = 0, age = 0 } }
sim.update(g, 1 / 60, {})
assert(g.split > 0, "extra-laser pickup activates")
g.duration = 0.01
sim.update(g, 1 / 60, {})
assert(g.state == "clearing", "sector ends through a transition")
print("PASS: endless scaling, beam upgrade, temporary pickups, smooth extraction")

g = sim.new(7, nil, 3001, true)
sim.spawn(g, "drone")
assert(
  g.enemies[1].hp > 3000 and g.enemies[1].speed <= 45 * 1.7,
  "late endless health grows while speed stays bounded"
)
assert(#g.spawnQueue <= 34, "late endless spawn count remains bounded")
g.state = "dock"
g.xp = 12
g.level = 3
g.upgrades.power = 9
local continued = sim.advance(g)
assert(
  continued.level == 3 and continued.xp == 12 and continued.player.damage == 13,
  "earned levels and purchased damage persist"
)
print("PASS: late endless bounds and persistent player growth")

g = sim.new(1)
g.state = "dock"
g.gems = 100
assert(sim.buy(g, "lasers") and g.player.lasers == 2, "beam purchase changes live ship immediately")
assert(
  math.abs(sim.stats(g).dps - 16.8) < 0.001,
  "beam upgrade changes displayed potential damage output"
)
assert(sim.buy(g, "power") and g.player.damage == 4, "power purchase applies immediately")
assert(sim.buy(g, "drive") and g.player.speed == 335, "drive purchase applies immediately")
assert(sim.buy(g, "magnet") and g.player.magnet == 136, "magnet purchase applies immediately")
assert(
  g.purchase.before == 96 and g.purchase.after == 136,
  "receipt has actual before/after values"
)
local n = sim.advance(g)
assert(
  n.player.damage == 4 and n.player.lasers == 2 and n.player.speed == 335,
  "departure does not double apply purchases"
)
g.turbo = 5
g.split = 5
assert(
  sim.stats(g).beams == 3 and sim.stats(g).speed == 335 * 1.45,
  "live stats include temporary pickups"
)
print("PASS: immediate upgrade effects, receipts, live stats, and no double application")

g = sim.new(1)
g.state = "clearing"
g.turbo = 7
g.split = 9
for _ = 1, 200 do
  sim.update(g, 1 / 60, {})
end
assert(
  g.state == "dock" and g.turbo == 0 and g.split == 0,
  "dock shows permanent stats without expired sector buffs"
)

-- Every first-sector enemy type must return fire, including the opening wave.
for _, kind in ipairs({ "drone", "weaver", "gunner" }) do
  local combat = sim.new(42)
  combat.spawnQueue = {}
  sim.spawn(combat, kind)
  local enemy = combat.enemies[1]
  enemy.y, enemy.fire = 200, 0
  sim.update(combat, 1 / 60, {})
  assert(#combat.hostile == (kind == "gunner" and 3 or 1), kind .. " must shoot")
end
local opening = sim.new(42)
local firstShot
for _ = 1, 60 * 5 do
  sim.update(opening, 1 / 60, {})
  if #opening.hostile > 0 then
    firstShot = opening.time
    break
  end
end
assert(firstShot and firstShot < 4, "opening wave must return fire within four seconds")
print("PASS: opening wave and all regular enemies return fire")

-- Crowded kills cannot fill the field with special packs; salvage still pays.
local loot = sim.new(42)
loot.spawnQueue = {}
for kill = 1, 42 do
  loot.time = kill
  sim.spawn(loot, "drone")
  local enemy = loot.enemies[#loot.enemies]
  enemy.x, enemy.y, enemy.hp = loot.player.x, loot.player.y - 50, 1
  loot.pulseCooldown = 0
  sim.pulse(loot)
end
local special, salvage = 0, 0
for _, pickup in ipairs(loot.pickups) do
  if pickup.kind == "salvage" then
    salvage = salvage + 1
  else
    special = special + 1
  end
end
assert(special == 2 and salvage == 42, "cap packs without cutting salvage rewards")
loot = sim.new(42)
loot.spawnQueue = {}
loot.pickups = { { x = 100, y = 200, age = 10, kind = "turbo", value = 0 } }
sim.update(loot, 1 / 60, {})
assert(#loot.pickups == 0, "uncollected equipment expires")
print("PASS: special-pack cap, unchanged salvage, and pickup expiration")
