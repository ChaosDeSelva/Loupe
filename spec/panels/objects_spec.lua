local driver = require("spec.support.ui_driver")
local objects = require("loupe.panels.objects")

local at = driver.at

describe("panels.objects", function()
  local ctx, roots, selection, picked
  local RECT = { x = 0, y = 40, w = 300, h = 400 }

  local function step(fields)
    local cmds = driver.frame(ctx, fields, function(c)
      picked = objects.build(c, roots, selection, RECT)
    end)
    return cmds
  end

  before_each(function()
    ctx = driver.new()
    selection, picked = nil, nil
    roots = {}
  end)

  it("explains how to watch something when nothing is watched", function()
    local cmds = step({})
    assert.truthy(driver.findText(cmds, "Nothing watched"))
    assert.equal("mono", driver.findText(cmds, "loupe.watch").font)
  end)

  it("is a docked section with an OBJECTS header and a root count", function()
    roots = { { name = "a", value = {} }, { name = "b", value = {} } }
    local cmds = step({})
    assert.truthy(driver.findExact(cmds, "OBJECTS"))
    assert.truthy(driver.findExact(cmds, "2"))
    local r = ctx:rectOf("loupe.objects")
    assert.same({ 0, 40, 300, 400 }, { r.x, r.y, r.w, r.h })
  end)

  describe("with a watched game", function()
    local game
    before_each(function()
      game = { score = 3, ship = { x = 1 }, rocks = { { r = 1 }, { r = 2 } } }
      roots = { { name = "game", value = game } }
      step({})
    end)

    it("shows roots open, listing child tables with field counts but not plain values", function()
      local cmds = step({})
      assert.truthy(driver.findExact(cmds, "game"))
      assert.truthy(driver.findExact(cmds, "rocks"))
      assert.truthy(driver.findExact(cmds, "ship"))
      assert.is_nil(driver.findText(cmds, "score"))
      -- Counts sit on the same row as their label: game has 3 fields, rocks 2.
      local rocks = driver.findExact(cmds, "rocks")
      local count
      for _, cmd in ipairs(cmds) do
        if cmd[1] == "text" and cmd[2] == "2" and cmd[4] == rocks[4] then
          count = cmd
        end
      end
      assert.truthy(count)
      assert.is_true(count[3] > rocks[3])
      assert.truthy(driver.findExact(cmds, "3"))
    end)

    it("picks a table when its label is clicked", function()
      step(driver.click(at(ctx, "game/ship")))
      assert.equal(game.ship, picked.value)
      assert.equal("game.ship", picked.path)
      assert.equal("game", picked.root)
      assert.same({ "ship" }, picked.keys)
    end)

    it("expands with the chevron, building paths for array entries", function()
      step(driver.click(at(ctx, "game/rocks", 4)))
      step(driver.click(at(ctx, "game/rocks/[1]")))
      assert.equal(game.rocks[1], picked.value)
      assert.equal("game.rocks[1]", picked.path)
      assert.same({ "rocks", 1 }, picked.keys)
    end)

    local function chevrons(cmds)
      return driver.count(cmds, "line")
    end

    it("draws a chevron only on tables that have child tables", function()
      -- game and rocks have child tables; ship doesn't.
      assert.equal(2, chevrons(step({})))
      game.ship.gun = {}
      assert.equal(3, chevrons(step({})))
    end)

    it("treats a table whose only table is a color as a leaf", function()
      game.sprite = { tint = { 1, 0, 0 } }
      assert.equal(2, chevrons(step({})))
      assert.truthy(driver.findExact(step({}), "sprite"))
    end)

    it("picks a leaf when its chevron zone is clicked", function()
      step(driver.click(at(ctx, "game/ship", 4)))
      assert.equal(game.ship, picked.value)
    end)

    it("highlights the current selection with a pill", function()
      assert.is_nil(driver.findColor(step({}), "rect", ctx.theme.colors.selection))
      selection = { value = game.ship, path = "game.ship" }
      local pill = driver.findColor(step({}), "rect", ctx.theme.colors.selection)
      assert.truthy(pill)
      assert.equal(driver.rect(ctx, "game/ship").y, pill[3])
    end)
  end)

  it("marks cycles instead of expanding them forever", function()
    local t = {}
    t.self = t
    roots = { { name = "t", value = t } }
    local cmds = step({})
    assert.truthy(driver.findText(cmds, "self  (cycle)"))
  end)

  it("shows getter errors and non-table roots", function()
    roots = {
      { name = "broken", error = "boom" },
      { name = "n", value = 42 },
    }
    local cmds = step({})
    assert.equal(ctx.theme.colors.warning, driver.findText(cmds, "broken: boom")[5])
    assert.truthy(driver.findText(cmds, "n = 42"))
  end)

  it("caps very long tables", function()
    local many = {}
    for i = 1, objects.MAX_CHILDREN + 5 do
      many[i] = {}
    end
    roots = { { name = "many", value = many } }
    -- The note is the last row: scroll down to it (rows out of view aren't drawn).
    for _ = 1, 200 do
      step({ x = 50, y = 100, wheel = -1 })
    end
    assert.truthy(driver.findText(step({}), "5 more"))
  end)
end)
