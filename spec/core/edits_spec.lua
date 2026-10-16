local edits = require("loupe.core.edits")

describe("core.edits", function()
  local e, ship
  before_each(function()
    e = edits.new()
    ship = { thrust = 220, x = 0, y = 0 }
  end)

  local function meta(keys, gesture)
    return { root = "game", keys = keys, gesture = gesture }
  end

  it("sets the value and records it for undo and saving", function()
    e:set(ship, "thrust", 300, meta({ "ship", "thrust" }, 1))
    assert.equal(300, ship.thrust)
    assert.equal(300, e.overrides:entries()[1].value)
    assert.is_true(e:dirty())
  end)

  it("ignores sets that change nothing", function()
    e:set(ship, "thrust", 220, meta({ "ship", "thrust" }, 1))
    assert.is_false(e.history:canUndo())
    assert.is_false(e:dirty())
  end)

  it("undo restores the value and drops the override", function()
    e:set(ship, "thrust", 300, meta({ "ship", "thrust" }, 1))
    e:undo()
    assert.equal(220, ship.thrust)
    assert.same({}, e.overrides:entries())
  end)

  it("redo brings both back", function()
    e:set(ship, "thrust", 300, meta({ "ship", "thrust" }, 1))
    e:undo()
    e:redo()
    assert.equal(300, ship.thrust)
    assert.equal(300, e.overrides:entries()[1].value)
  end)

  it("undoes a whole drag (x and y) in one step", function()
    e:set(ship, "x", 5, meta({ "ship", "x" }, 3))
    e:set(ship, "y", 5, meta({ "ship", "y" }, 3))
    e:set(ship, "x", 9, meta({ "ship", "x" }, 3))
    e:undo()
    assert.same({ 0, 0 }, { ship.x, ship.y })
  end)

  it("still undoes edits it can't save (no root)", function()
    e:set(ship, "thrust", 1, { gesture = 1 })
    assert.same({}, e.overrides:entries())
    e:undo()
    assert.equal(220, ship.thrust)
  end)

  describe("fields reached through keys the file can't hold", function()
    local byKey, handle
    before_each(function()
      handle = function() end
      byKey = { [handle] = ship }
    end)

    it("applies and undoes the edit but doesn't save it, and says so", function()
      local saved = e:set(ship, "thrust", 300, meta({ "byKey", handle, "thrust" }, 1))
      assert.is_false(saved)
      assert.equal(300, byKey[handle].thrust)
      assert.same({}, e.overrides:entries())
      e:undo()
      assert.equal(220, ship.thrust)
      e:redo()
      assert.equal(300, ship.thrust)
      assert.same({}, e.overrides:entries())
    end)

    it("treats boolean keys the same way", function()
      assert.is_false(e:set(ship, "thrust", 1, meta({ true, "thrust" }, 1)))
      assert.same({}, e.overrides:entries())
    end)

    it("reports savable edits as saved", function()
      assert.is_true(e:set(ship, "thrust", 1, meta({ "ship", "thrust" }, 1)))
      assert.is_true(e:set(ship, "x", 1, { gesture = 2 })) -- no root: nothing to report
    end)
  end)

  describe("undo after a getter's root was replaced", function()
    local game, live
    before_each(function()
      game = { ship = { thrust = 220 } }
      live = edits.new({
        resolveRoot = function(name)
          return name == "game" and game or nil
        end,
      })
    end)

    it("undoes and redoes on the root's current table", function()
      live:set(game.ship, "thrust", 300, meta({ "ship", "thrust" }, 1))
      local old = game
      game = { ship = { thrust = 300 } } -- the game restarted, overrides re-applied
      live:undo()
      assert.equal(220, game.ship.thrust)
      assert.equal(300, old.ship.thrust) -- the dead table is left alone
      live:redo()
      assert.equal(300, game.ship.thrust)
    end)

    it("falls back to the old table when the field is gone from the new root", function()
      live:set(game.ship, "thrust", 300, meta({ "ship", "thrust" }, 1))
      local old = game
      game = {}
      assert.has_no.errors(function()
        live:undo()
      end)
      assert.equal(220, old.ship.thrust)
    end)
  end)

  it("tracks unsaved changes", function()
    e:set(ship, "thrust", 300, meta({ "ship", "thrust" }, 1))
    e:markSaved()
    assert.is_false(e:dirty())
    e:undo()
    assert.is_true(e:dirty())
  end)
end)
