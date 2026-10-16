local sim = require("src.sim")
local function play(g)
  for _ = 1, 60 * 100 do
    if g.state ~= "flight" and g.state ~= "clearing" then
      return g
    end
    local p = g.player
    local target
    for _, e in ipairs(g.enemies) do
      if e.kind == "boss" or not target then
        target = e
      end
    end
    local tx, ty = 542, 550
    if target then
      tx = target.x
      ty = math.max(340, math.min(690, target.y + 235))
    end
    local dx, dy = (tx - p.x) / 100, (ty - p.y) / 100
    for _, e in ipairs(g.enemies) do
      local x, y = p.x - e.x, p.y - e.y
      local d = x * x + y * y
      if d < 150 * 150 then
        dx = dx + x / math.max(10, math.sqrt(d)) * 3
        dy = dy + y / math.max(10, math.sqrt(d)) * 3
      end
    end
    for _, b in ipairs(g.hostile) do
      local x, y = p.x - b.x, p.y - b.y
      local d = x * x + y * y
      if d < 120 * 120 then
        dx = dx + x / math.max(15, math.sqrt(d)) * 2
      end
    end
    sim.update(g, 1 / 60, { x = math.max(-1, math.min(1, dx)), y = math.max(-1, math.min(1, dy)) })
    if #g.hostile > 6 then
      sim.pulse(g)
    end
  end
  return g
end
return play
