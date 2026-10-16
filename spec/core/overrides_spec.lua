local overrides = require("loupe.core.overrides")

describe("core.overrides", function()
  describe("store", function()
    local store
    before_each(function()
      store = overrides.new()
    end)

    it("remembers the latest value per field", function()
      store:record("game", { "ship", "thrust" }, 220, 250)
      store:record("game", { "ship", "thrust" }, 250, 286)
      assert.same({ { root = "game", keys = { "ship", "thrust" }, value = 286 } }, store:entries())
    end)

    it("forgets a field set back to its original value", function()
      store:record("game", { "ship", "thrust" }, 220, 250)
      store:record("game", { "ship", "thrust" }, 250, 220)
      assert.same({}, store:entries())
    end)

    it("keeps loaded entries even though their originals are unknown", function()
      store:load({ { root = "game", keys = { "score" }, value = 9 } })
      store:record("game", { "score" }, 9, 10)
      store:record("game", { "score" }, 10, 9)
      assert.equal(9, store:entries()[1].value)
    end)

    it("lists entries in a stable order", function()
      store:record("b", { "x" }, 0, 1)
      store:record("a", { "y" }, 0, 1)
      store:record("a", { "x" }, 0, 1)
      store:record("a", { "list", 2 }, 0, 1)
      local order = {}
      for i, e in ipairs(store:entries()) do
        order[i] = e.root .. ":" .. table.concat(e.keys, ".")
      end
      assert.same({ "a:list.2", "a:x", "a:y", "b:x" }, order)
    end)

    it("tells entries apart by key type", function()
      store:record("a", { 1 }, 0, 1)
      store:record("a", { "1" }, 0, 2)
      assert.equal(2, #store:entries())
    end)
  end)

  describe("persistable", function()
    it("accepts key lists of strings and finite numbers", function()
      assert.is_true(overrides.persistable({ "rocks", 3, "x" }))
      assert.is_true(overrides.persistable({ 1.5 }))
    end)

    it("refuses keys that can't be written to the file or read back", function()
      assert.is_false(overrides.persistable({ "a", print }))
      assert.is_false(overrides.persistable({ {} }))
      assert.is_false(overrides.persistable({ io.stdout })) -- userdata
      assert.is_false(overrides.persistable({ true }))
      assert.is_false(overrides.persistable({ math.huge }))
      assert.is_false(overrides.persistable({}))
      assert.is_false(overrides.persistable(nil))
    end)
  end)

  describe("unpersistable keys", function()
    local store
    before_each(function()
      store = overrides.new()
    end)

    it("aren't recorded, and don't throw", function()
      local ok = store:record("game", { "byKey", {}, "x" }, 1, 2)
      assert.is_false(ok)
      assert.same({}, store:entries())
    end)

    it("include booleans, which the file can't load back", function()
      assert.is_false(store:record("game", { "flags", true }, 1, 2))
      assert.same({}, store:entries())
    end)

    it("leave normal records alone", function()
      assert.is_true(store:record("game", { "x" }, 1, 2))
      assert.equal(1, #store:entries())
    end)
  end)

  it("builds a readable path from a root and keys", function()
    assert.equal('game.rocks[3]["two words"]', overrides.path("game", { "rocks", 3, "two words" }))
  end)

  describe("file format", function()
    local entries = {
      { root = "game", keys = { "ship", "thrust" }, value = 286 },
      { root = "game", keys = { "rocks", 3, "label" }, value = 'big "one"' },
    }

    it("renders readable Lua with a path comment per entry", function()
      local text = overrides.render(entries)
      assert.matches("^%-%- loupe overrides", text)
      assert.truthy(
        text:find('{ "game", { "ship", "thrust" }, 286 }, -- game.ship.thrust', 1, true)
      )
    end)

    it("writes fractions without float noise", function()
      local text = overrides.render({ { root = "game", keys = { "fx", "glow" }, value = 0.05 } })
      assert.truthy(text:find("0.05 }", 1, true), text)
    end)

    it("round-trips through parse", function()
      local load = loadstring or load
      local data = assert(load(overrides.render(entries)))()
      assert.same(entries, overrides.parse(data))
    end)

    it("skips malformed entries", function()
      local parsed = overrides.parse({
        { "game", { "ok" }, 1 },
        { 42, { "x" }, 1 }, -- root isn't a string
        { "game", "x", 1 }, -- keys isn't a table
        { "game", {}, 1 }, -- no keys
        { "game", { {} }, 1 }, -- key isn't a string or number
        { "game", { true }, 1 }, -- boolean key: never written, never read
        { "game", { 1 / 0 }, 1 }, -- infinite key
        { "game", { "t" }, {} }, -- value isn't a scalar
        "junk",
      })
      assert.same({ { root = "game", keys = { "ok" }, value = 1 } }, parsed)
    end)

    it("treats a non-table file as empty", function()
      assert.same({}, overrides.parse("nope"))
    end)
  end)

  describe("apply", function()
    it("writes values into a root table, counting what didn't fit", function()
      local game = { ship = { thrust = 220 }, rocks = { { r = 1 } } }
      local applied, skipped = overrides.apply({
        { root = "game", keys = { "ship", "thrust" }, value = 300 },
        { root = "game", keys = { "rocks", 1, "r" }, value = 5 },
        { root = "game", keys = { "rocks", 9, "r" }, value = 5 }, -- no rocks[9]
        { root = "game", keys = { "ship", "thrust", "deeper" }, value = 1 }, -- thrust isn't a table
        { root = "other", keys = { "x" }, value = 1 }, -- different root: ignored
      }, "game", game)
      assert.equal(300, game.ship.thrust)
      assert.equal(5, game.rocks[1].r)
      assert.same({ 2, 2 }, { applied, skipped })
    end)
  end)
end)
