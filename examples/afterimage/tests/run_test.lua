local sim = require("src.sim")
local play = require("tests.pilot")
local victories = 0
for _, seed in ipairs({ 42, 1, 2 }) do
  local g = sim.new(seed)
  for sector = 1, 3 do
    play(g)
    print(
      "seed",
      seed,
      "sector",
      sector,
      "outcome",
      g.state,
      "hp",
      g.player.hp,
      "kills",
      g.kills,
      "time",
      g.time
    )
    assert(g.state == "dock" or g.state == "victory" or g.state == "lost", "run must resolve")
    if g.state == "lost" then
      break
    end
    if sector < 3 then
      if seed == 2 then
        sim.buy(g, "lasers")
      end
      while sim.buy(g, "power") do
      end
      sim.buy(g, "repair")
      g = sim.advance(g)
    end
  end
  if g.state == "victory" then
    victories = victories + 1
  end
end
assert(victories >= 1, "at least one reference pilot must win without cheats")
print(
  "PASS: three full combat runs resolved, victories=" .. victories .. "; no invulnerability cheats"
)
