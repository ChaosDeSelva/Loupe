local hotswap = require("loupe.core.hotswap")

describe("hotswap.patch", function()
  it("refuses anything that isn't two tables, changing nothing", function()
    local old = { a = 1 }
    assert.is_false(hotswap.patch(old, nil))
    assert.is_false(hotswap.patch(old, true))
    assert.is_false(hotswap.patch(nil, { a = 2 }))
    assert.is_false(hotswap.patch("x", { a = 2 }))
    assert.same({ a = 1 }, old)
  end)

  it("replaces functions in place, so captured references see the new code", function()
    local ship = {
      speed = function()
        return 1
      end,
    }
    local captured = ship
    assert.is_true(hotswap.patch(ship, {
      speed = function()
        return 2
      end,
    }))
    assert.equal(captured, ship)
    assert.equal(2, captured.speed())
  end)

  it("adds new keys and removes keys the new version dropped", function()
    local old = { keep = 1, gone = 2 }
    hotswap.patch(old, { keep = 1, added = 3 })
    assert.same({ keep = 1, added = 3 }, old)
  end)

  it("replaces plain values when there's no previous version to compare with", function()
    local old = { THRUST = 200, name = "ship" }
    hotswap.patch(old, { THRUST = 300, name = "ship" })
    assert.same({ THRUST = 300, name = "ship" }, old)
  end)

  it("patches nested tables in place", function()
    local inner = {
      f = function()
        return "old"
      end,
    }
    local old = { states = { idle = inner } }
    local states = old.states
    hotswap.patch(old, {
      states = {
        idle = {
          f = function()
            return "new"
          end,
        },
      },
    })
    assert.equal(states, old.states)
    assert.equal(inner, old.states.idle)
    assert.equal("new", inner.f())
  end)

  it("points self-references at the old table (the Class.__index = Class pattern)", function()
    local Ship = {}
    Ship.__index = Ship
    function Ship.speed()
      return 1
    end
    local instance = setmetatable({}, Ship)

    local New = {}
    New.__index = New
    function New.speed()
      return 2
    end
    hotswap.patch(Ship, New)

    assert.equal(Ship, Ship.__index)
    assert.equal(2, instance.speed())
  end)

  it("maps tables shared between keys to one old table", function()
    local old = { a = { v = 1 } }
    local shared = { v = 2 }
    -- `b` has no old counterpart but is the same table as `a`.
    hotswap.patch(old, { b = shared, a = shared })
    assert.equal(old.a, old.b)
    assert.equal(2, old.a.v)
  end)

  it("survives cycles in both versions", function()
    local old = { child = {} }
    old.child.parent = old
    local new = { child = { x = 1 } }
    new.child.parent = new
    new.loop = new
    assert.is_true(hotswap.patch(old, new))
    assert.equal(old, old.child.parent)
    assert.equal(old, old.loop)
    assert.equal(1, old.child.x)
  end)

  it("remaps references inside tables that only the new version has", function()
    local old = {}
    local new = { states = { idle = {} } }
    new.states.idle.owner = new
    hotswap.patch(old, new)
    assert.equal(new.states, old.states)
    assert.equal(old, old.states.idle.owner)
  end)

  it("leaves tables the two versions share alone", function()
    local config = { debug = true }
    local old = { config = config }
    hotswap.patch(old, { config = config })
    assert.equal(config, old.config)
    assert.same({ debug = true }, config)
  end)

  it("replaces a value whose type changed", function()
    local old = { a = { x = 1 }, b = 2 }
    hotswap.patch(old, { a = 5, b = { y = 1 } })
    assert.same({ a = 5, b = { y = 1 } }, old)
  end)

  describe("with shared tables (other modules)", function()
    local levelOne, levelTwo, shared
    before_each(function()
      levelOne = { name = "one", spawn = 1 }
      levelTwo = { name = "two", spawn = 2 }
      shared = { [levelOne] = true, [levelTwo] = true }
    end)

    it("never patches a shared table, even when the game repointed the key", function()
      local old = { level = levelTwo }
      hotswap.patch(old, { level = levelOne }, nil, shared)
      assert.same({ name = "two", spawn = 2 }, levelTwo)
      assert.same({ name = "one", spawn = 1 }, levelOne)
      assert.equal(levelOne, old.level)
    end)

    it("keeps the game's choice when the file still points at the same table", function()
      local previous = hotswap.snapshot({ level = levelOne }, shared)
      assert.equal(levelOne, previous.level) -- kept by reference, not copied
      local old = { level = levelTwo }
      hotswap.patch(old, { level = levelOne }, previous, shared)
      assert.equal(levelTwo, old.level)
    end)

    it("replaces a shared table with the file's own table without touching it", function()
      local old = { level = levelOne }
      local previous = hotswap.snapshot(old, shared)
      hotswap.patch(old, { level = { name = "inline" } }, previous, shared)
      assert.same({ name = "inline" }, old.level)
      assert.same({ name = "one", spawn = 1 }, levelOne)
    end)

    it("doesn't walk into shared tables inside new ones", function()
      local new = { group = { level = levelOne } }
      levelOne.owner = new -- would be remapped if it were walked
      hotswap.patch({}, new, nil, shared)
      assert.equal(new, levelOne.owner)
    end)

    it("still snapshots the root even if it's shared", function()
      shared[levelOne] = true
      local copy = hotswap.snapshot(levelOne, shared)
      assert.are_not.equal(levelOne, copy)
      assert.same(levelOne, copy)
    end)
  end)

  describe("with the previous version of the file", function()
    it("keeps values the game changed when the file didn't change them", function()
      local previous = { score = 0, THRUST = 200 }
      local old = { score = 42, THRUST = 200 }
      hotswap.patch(old, { score = 0, THRUST = 300 }, previous)
      assert.same({ score = 42, THRUST = 300 }, old)
    end)

    it("keeps keys the game added and removes keys the file dropped", function()
      local previous = { a = 1, b = 2 }
      local old = { a = 1, b = 2, runtime = "kept" }
      hotswap.patch(old, { a = 1 }, previous)
      assert.same({ a = 1, runtime = "kept" }, old)
    end)

    it("applies a value the file newly defines even if the game set the key", function()
      local old = { mode = "game" }
      hotswap.patch(old, { mode = "file" }, {})
      assert.equal("file", old.mode)
    end)

    it("compares nested values against the matching previous table", function()
      local previous = { tuning = { gravity = 10, jump = 5 } }
      local old = { tuning = { gravity = 99, jump = 5 } }
      hotswap.patch(old, { tuning = { gravity = 10, jump = 7 } }, previous)
      assert.same({ gravity = 99, jump = 7 }, old.tuning)
    end)

    it("still replaces functions the game reassigned", function()
      local f = function() end
      local g = function() end
      local h = function() end
      local old = { update = g }
      hotswap.patch(old, { update = h }, { update = f })
      assert.equal(h, old.update)
    end)
  end)
end)

describe("hotswap.snapshot", function()
  it("deep-copies tables, keeping functions and cycles", function()
    local f = function() end
    local t = { a = { b = 1 }, f = f }
    t.a.up = t
    local copy = hotswap.snapshot(t)
    assert.are_not.equal(t, copy)
    assert.are_not.equal(t.a, copy.a)
    assert.equal(1, copy.a.b)
    assert.equal(f, copy.f)
    assert.equal(copy, copy.a.up)
    t.a.b = 2
    assert.equal(1, copy.a.b)
  end)

  it("returns non-tables unchanged", function()
    assert.equal(5, hotswap.snapshot(5))
    assert.is_nil(hotswap.snapshot(nil))
  end)
end)

describe("hotswap.reloadable", function()
  it("lists table modules by name, sorted, skipping loupe, main and conf", function()
    local loaded = {
      ["src.ship"] = {},
      ["src.enemy"] = {},
      loupe = {},
      ["loupe.core.clock"] = {},
      main = true,
      conf = {},
      loupelike = {},
      flag = true,
      fn = function() end,
    }
    assert.same({ "loupelike", "src.enemy", "src.ship" }, hotswap.reloadable(loaded))
  end)

  it("skips names matching any ignore pattern", function()
    local loaded = { ["src.ship"] = {}, ["lib.vendor"] = {}, ["src.save"] = {} }
    assert.same({ "src.ship" }, hotswap.reloadable(loaded, { "^lib%.", "save$" }))
  end)
end)
