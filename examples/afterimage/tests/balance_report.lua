local sim = require("src.sim")
local pilot = require("tests.pilot")
for _, mode in ipairs({ "stationary", "active" }) do
  local passed, bossTime, bossHp = { 0, 0, 0 }, 0, 0
  for seed = 1, 30 do
    local g = sim.new(seed)
    for sector = 1, 3 do
      if mode == "active" then
        pilot(g)
      else
        for _ = 1, 60 * 110 do
          sim.update(g, 1 / 60, {})
          if g.state == "dock" or g.state == "victory" or g.state == "lost" then
            break
          end
        end
      end
      if g.state ~= "dock" and g.state ~= "victory" then
        break
      end
      passed[sector] = passed[sector] + 1
      if sector == 3 then
        bossTime, bossHp = bossTime + g.time, bossHp + g.player.hp
      end
      if sector < 3 then
        while sim.buy(g, "power") do
        end
        sim.buy(g, "repair")
        g = sim.advance(g)
      end
    end
  end
  print(
    string.format(
      "%s / 30 seeds: sector clears %d / %d / %d; boss mean %.1fs, %.1f hull",
      mode,
      passed[1],
      passed[2],
      passed[3],
      bossTime / math.max(1, passed[3]),
      bossHp / math.max(1, passed[3])
    )
  )
end
local reaches = {}
for seed = 1, 20 do
  local g = sim.new(seed, nil, 1, true)
  local last = 0
  for sector = 1, 18 do
    pilot(g)
    if g.state ~= "dock" then
      break
    end
    last = sector
    sim.buy(g, "lasers")
    while sim.buy(g, "power") do
    end
    sim.buy(g, "repair")
    g = sim.advance(g)
  end
  reaches[#reaches + 1] = last
end
table.sort(reaches)
print(
  string.format(
    "Endless active pilot / 20 seeds: cleared sectors min=%d median=%d max=%d",
    reaches[1],
    reaches[10],
    reaches[20]
  )
)
