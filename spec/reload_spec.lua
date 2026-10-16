local love_stub = require("spec.support.love_stub")
local reload = require("loupe.reload")

describe("reload", function()
  local fake, added

  -- Puts a module in package.loaded and its source in the fake filesystem.
  local function module(name, path, source, value)
    added[#added + 1] = name
    fake.files[path] = source
    fake.modtimes[path] = 1
    package.loaded[name] = value
    return value
  end

  local function edit(path, source)
    fake.files[path] = source
    fake.modtimes[path] = fake.modtimes[path] + 1
  end

  before_each(function()
    fake = love_stub.install()
    added = {}
  end)

  after_each(function()
    for _, name in ipairs(added) do
      package.loaded[name] = nil
    end
    love_stub.uninstall()
  end)

  it("patches a changed module in place and reports it", function()
    local ship = module("t_ship", "t_ship.lua", "", {
      speed = function()
        return 1
      end,
    })
    local watcher = reload.new()
    edit("t_ship.lua", "return { speed = function() return 2 end }")
    assert.same({ { name = "t_ship", ok = true } }, watcher:update(0.5))
    assert.equal(ship, package.loaded.t_ship)
    assert.equal(2, ship.speed())
  end)

  it("maps dotted names to folders, including init.lua", function()
    local a = module("t_src.ship", "t_src/ship.lua", "", { v = 1 })
    local b = module("t_src.enemies", "t_src/enemies/init.lua", "", { v = 1 })
    local watcher = reload.new()
    edit("t_src/ship.lua", "return { v = 2 }")
    edit("t_src/enemies/init.lua", "return { v = 3 }")
    local results = watcher:update(1)
    assert.same({
      { name = "t_src.enemies", ok = true },
      { name = "t_src.ship", ok = true },
    }, results)
    assert.same({ 2, 3 }, { a.v, b.v })
  end)

  it("finds modules through the game's require path", function()
    fake.requirePath = "src/?.lua;lib/?/init.lua;?.lua"
    local a = module("t_rp.ship", "src/t_rp/ship.lua", "", { v = 1 })
    local b = module("t_rplib", "lib/t_rplib/init.lua", "", { v = 1 })
    local watcher = reload.new()
    edit("src/t_rp/ship.lua", "return { v = 2 }")
    edit("lib/t_rplib/init.lua", "return { v = 3 }")
    assert.same({
      { name = "t_rp.ship", ok = true },
      { name = "t_rplib", ok = true },
    }, watcher:update(1))
    assert.same({ 2, 3 }, { a.v, b.v })
  end)

  it("still looks in the default places when the require path doesn't have them", function()
    fake.requirePath = "src/?.lua"
    local a = module("t_rpdefault", "t_rpdefault.lua", "", { v = 1 })
    local watcher = reload.new()
    edit("t_rpdefault.lua", "return { v = 2 }")
    assert.same({ { name = "t_rpdefault", ok = true } }, watcher:update(1))
    assert.equal(2, a.v)
  end)

  it("turns an error while patching into a failed reload", function()
    local strict = setmetatable({}, {
      __newindex = function()
        error("module is locked")
      end,
    })
    module("t_locked", "t_locked.lua", "", strict)
    local watcher = reload.new()
    edit("t_locked.lua", "return { added = 1 }")
    local results = watcher:update(1)
    assert.equal(1, #results)
    assert.is_false(results[1].ok)
    assert.truthy(results[1].err:find("module is locked", 1, true))
  end)

  it("passes the module name to the chunk, like require", function()
    local m = module("t_named", "t_named.lua", "", {})
    local watcher = reload.new()
    edit("t_named.lua", "return { name = ... }")
    watcher:update(1)
    assert.equal("t_named", m.name)
  end)

  it("does nothing while files are unchanged", function()
    module("t_same", "t_same.lua", "error('should not run')", {})
    local watcher = reload.new()
    assert.same({}, watcher:update(1))
    assert.same({}, watcher:update(1))
  end)

  it("checks at most every half second", function()
    local m = module("t_slow", "t_slow.lua", "", { v = 1 })
    local watcher = reload.new()
    edit("t_slow.lua", "return { v = 2 }")
    assert.same({}, watcher:update(0.2))
    assert.same({}, watcher:update(0.2))
    assert.equal(1, m.v)
    assert.same({ { name = "t_slow", ok = true } }, watcher:update(0.2))
    edit("t_slow.lua", "return { v = 3 }")
    assert.same({}, watcher:update(0.2)) -- the timer restarted
    assert.equal(2, m.v)
  end)

  describe("a module that fails", function()
    local ship, watcher
    local function speed()
      return 1
    end

    before_each(function()
      ship = module("t_bad", "t_bad.lua", "", { speed = speed })
      watcher = reload.new()
    end)

    it("keeps the old code on a syntax error", function()
      edit("t_bad.lua", "return { speed = function() return 2 end")
      local results = watcher:update(1)
      assert.equal(1, #results)
      assert.equal("t_bad", results[1].name)
      assert.is_false(results[1].ok)
      assert.truthy(results[1].err:find("Syntax error", 1, true))
      assert.is_nil(results[1].err:find("\n$")) -- trailing newline trimmed
      assert.equal(speed, ship.speed)
    end)

    it("keeps the old code when the chunk throws", function()
      edit("t_bad.lua", "error('boom')")
      local results = watcher:update(1)
      assert.is_false(results[1].ok)
      assert.truthy(results[1].err:find("boom", 1, true))
      assert.equal(speed, ship.speed)
    end)

    it("refuses a module that doesn't return a table", function()
      edit("t_bad.lua", "return 42")
      local results = watcher:update(1)
      assert.same(
        { { name = "t_bad", ok = false, err = "didn't return a table (got number)" } },
        results
      )
      assert.equal(speed, ship.speed)
    end)

    it("reports a file that can't be read", function()
      fake.modtimes["t_bad.lua"] = 2
      fake.love.filesystem.load = function()
        return nil, "Could not open file"
      end
      local results = watcher:update(1)
      assert.same({ { name = "t_bad", ok = false, err = "Could not open file" } }, results)
    end)

    it("doesn't retry until the file changes again, then succeeds", function()
      edit("t_bad.lua", "error('boom')")
      watcher:update(1)
      assert.same({}, watcher:update(1))
      edit("t_bad.lua", "return { speed = function() return 3 end }")
      assert.same({ { name = "t_bad", ok = true } }, watcher:update(1))
      assert.equal(3, ship.speed())
    end)
  end)

  it("keeps values the game changed when the file didn't change them", function()
    local m = module("t_state", "t_state.lua", "", { score = 0, THRUST = 200 })
    local watcher = reload.new()
    m.score = 42
    edit("t_state.lua", "return { score = 0, THRUST = 300 }")
    watcher:update(1)
    assert.same({ score = 42, THRUST = 300 }, m)
    -- The new file is now the baseline for the next reload.
    m.THRUST = 1
    edit("t_state.lua", "return { score = 0, THRUST = 300, extra = true }")
    watcher:update(1)
    assert.same({ score = 42, THRUST = 1, extra = true }, m)
  end)

  it("tracks modules required after it started, from the next check", function()
    local watcher = reload.new()
    local m = module("t_late", "t_late.lua", "", { v = 1 })
    assert.same({}, watcher:update(1))
    edit("t_late.lua", "return { v = 2 }")
    assert.same({ { name = "t_late", ok = true } }, watcher:update(1))
    assert.equal(2, m.v)
  end)

  it("never reloads loupe, main, conf or ignored modules", function()
    module("loupe.t_self", "loupe/t_self.lua", "", { v = 1 })
    module("main", "main.lua", "", { v = 1 })
    module("conf", "conf.lua", "", { v = 1 })
    module("t_vendor.lib", "t_vendor/lib.lua", "", { v = 1 })
    local watcher = reload.new({ ignore = { "^t_vendor%." } })
    for _, path in ipairs({ "loupe/t_self.lua", "main.lua", "conf.lua", "t_vendor/lib.lua" }) do
      edit(path, "return { v = 2 }")
    end
    assert.same({}, watcher:update(1))
  end)

  it("skips modules without a file and files that disappear", function()
    module("t_virtual", "unrelated.lua", "", {})
    module("t_deleted", "t_deleted.lua", "", {})
    local watcher = reload.new()
    fake.files["t_deleted.lua"] = nil
    assert.same({}, watcher:update(1))
  end)

  it("treats a missing modtime as unchanged", function()
    module("t_nomod", "t_nomod.lua", "", { v = 1 })
    fake.modtimes["t_nomod.lua"] = nil
    local watcher = reload.new()
    fake.files["t_nomod.lua"] = "return { v = 2 }"
    assert.same({}, watcher:update(1))
  end)
end)
