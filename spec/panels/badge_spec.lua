local badge = require("loupe.panels.badge")
local clockModule = require("loupe.core.clock")
local driver = require("spec.support.ui_driver")
local themes = require("loupe.ui.theme")

describe("panels.badge", function()
  local theme, clock

  local function measure(text)
    return #text * 7
  end

  local function build(screenW, alert, t)
    return badge.build(clock, screenW, alert, t or theme, measure, 14)
  end

  local function texts(cmds)
    local out = {}
    for _, cmd in ipairs(cmds) do
      if cmd[1] == "text" then
        out[#out + 1] = cmd
      end
    end
    return out
  end

  before_each(function()
    theme = themes.build()
    clock = clockModule.new()
  end)

  it("shows the time state and speed in a pill at the top right", function()
    clock:togglePause()
    clock:slower()
    local cmds = build(800)
    local state = driver.findExact(cmds, "PAUSED")
    assert.truthy(state)
    assert.equal(theme.colors.warning, state[5])
    assert.truthy(driver.findExact(cmds, "x0.5"))
    local pill = driver.findColor(cmds, "rect", theme.colors.surfaceRaised)
    assert.equal(800 - theme.space.md, pill[2] + pill[4])
    assert.equal(pill[5] / 2, pill.radius)
  end)

  it("uses the theme it's given, not the shared module", function()
    local custom = themes.build({ colors = { warning = { 1, 0, 1, 1 } } })
    clock:togglePause()
    local state = driver.findExact(build(800, nil, custom), "PAUSED")
    assert.same({ 1, 0, 1, 1 }, state[5])
    assert.are_not.same({ 1, 0, 1, 1 }, themes.colors.warning)
  end)

  it("wraps a long alert onto lines that fit, losing no words", function()
    local alert = "reload failed: src.ship: src/ship.lua:12: unexpected symbol near 'end' "
      .. "while loading the module after it changed on disk"
    local cmds = build(400, alert)
    local cards = 0
    for _, cmd in ipairs(cmds) do
      if cmd[1] == "rect" and cmd[6] == theme.colors.surfaceRaised then
        cards = cards + 1
      end
    end
    local lines, words = {}, {}
    for _, cmd in ipairs(texts(cmds)) do
      if cmd[4] > theme.space.md + 30 then -- below the pill
        lines[#lines + 1] = cmd
        assert.is_true(cmd[3] >= 0 and cmd[3] + measure(cmd[2]) <= 400 - theme.space.md, cmd[2])
        for word in cmd[2]:gmatch("%S+") do
          words[#words + 1] = word
        end
      end
    end
    assert.is_true(#lines > 2)
    local expected = {}
    for word in alert:gmatch("%S+") do
      expected[#expected + 1] = word
    end
    assert.same(expected, words)
    assert.equal(2, cards) -- the pill and the alert card
  end)

  it("breaks a single word too long for any line", function()
    local cmds = build(200, ("x"):rep(80))
    local total = 0
    for _, cmd in ipairs(texts(cmds)) do
      if cmd[2]:find("^x+$") then
        total = total + #cmd[2]
        assert.is_true(cmd[3] + measure(cmd[2]) <= 200, cmd[2])
      end
    end
    assert.equal(80, total)
  end)
end)
