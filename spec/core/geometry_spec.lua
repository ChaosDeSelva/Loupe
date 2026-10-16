local geometry = require("loupe.core.geometry")

describe("core.geometry", function()
  describe("bounds", function()
    local function box(obj, opts)
      return { geometry.bounds(obj, opts or {}) }
    end

    it("uses w/h as a top-left box by default", function()
      assert.same({ 10, 20, 30, 40 }, box({ x = 10, y = 20, w = 30, h = 40 }))
      assert.same({ 10, 20, 30, 40 }, box({ x = 10, y = 20, width = 30, height = 40 }))
    end)

    it("can treat x, y as the center of a w/h box", function()
      assert.same({ -5, 0, 30, 40 }, box({ x = 10, y = 20, w = 30, h = 40 }, { center = true }))
    end)

    it("uses a radius around x, y", function()
      assert.same({ 5, 15, 10, 10 }, box({ x = 10, y = 20, r = 5 }))
      assert.same({ 5, 15, 10, 10 }, box({ x = 10, y = 20, radius = 5 }))
    end)

    it("looks through a shared def table", function()
      assert.same({ 5, 15, 10, 10 }, box({ x = 10, y = 20, def = { r = 5 } }))
      assert.same({ 10, 20, 3, 4 }, box({ x = 10, y = 20, def = { w = 3, h = 4 } }))
    end)

    it("falls back to a small marker at x, y", function()
      local s = geometry.POINT_SIZE
      assert.same({ 10 - s / 2, 20 - s / 2, s, s }, box({ x = 10, y = 20 }))
    end)

    it("returns nothing without a numeric position", function()
      assert.same({}, box({ name = "x" }))
      assert.same({}, box({ x = "10", y = 20 }))
    end)

    it("ignores size fields that aren't numbers", function()
      local s = geometry.POINT_SIZE
      assert.same({ 10 - s / 2, 20 - s / 2, s, s }, box({ x = 10, y = 20, w = "wide", h = 4 }))
    end)

    it("asks the user's hook first, falling back when it returns nil", function()
      local opts = {
        bounds = function(obj)
          if obj.pos then
            return obj.pos[1], obj.pos[2], 1, 1
          end
        end,
      }
      assert.same({ 3, 4, 1, 1 }, box({ pos = { 3, 4 } }, opts))
      assert.same({ 10, 20, 30, 40 }, box({ x = 10, y = 20, w = 30, h = 40 }, opts))
    end)
  end)

  describe("collect", function()
    local function paths(list)
      local out = {}
      for _, entry in ipairs(list) do
        out[#out + 1] = entry.path
      end
      table.sort(out)
      return out
    end

    it("finds positioned tables anywhere under the roots, with paths", function()
      local game = {
        player = { x = 1, y = 2, w = 3, h = 4 },
        enemies = { { x = 5, y = 6 }, { x = 7, y = 8 } },
        settings = { volume = 1 },
      }
      local list = geometry.collect({ { name = "game", value = game } }, {})
      assert.same({ "game.enemies[1]", "game.enemies[2]", "game.player" }, paths(list))
      for _, entry in ipairs(list) do
        if entry.value == game.player then
          assert.same({ 1, 2, 3, 4 }, { entry.x, entry.y, entry.w, entry.h })
        end
      end
    end)

    it("records each entry's root name and key list", function()
      local game = { player = { x = 1, y = 2 }, enemies = { { x = 5, y = 6 } } }
      local found = {}
      for _, e in ipairs(geometry.collect({ { name = "game", value = game } }, {})) do
        found[e.path] = { e.root, e.keys }
      end
      assert.same({ "game", { "player" } }, found["game.player"])
      assert.same({ "game", { "enemies", 1 } }, found["game.enemies[1]"])
    end)

    it("includes a positioned root and survives cycles", function()
      local t = { x = 0, y = 0 }
      t.self = t
      local list = geometry.collect({ { name = "t", value = t } }, {})
      assert.same({ "t" }, paths(list))
    end)

    it("skips roots that aren't tables", function()
      local list = geometry.collect({ { name = "n", value = 1 }, { name = "e", error = "x" } }, {})
      assert.same({}, list)
    end)

    it("respects the pickable filter", function()
      local camera = { x = 0, y = 0, w = 100, h = 100 }
      local game = { camera = camera, player = { x = 1, y = 1 } }
      local list = geometry.collect({ { name = "g", value = game } }, {
        pickable = function(obj)
          return obj ~= camera
        end,
      })
      assert.same({ "g.player" }, paths(list))
    end)

    it("stops at the depth limit", function()
      local deep = { x = 0, y = 0 }
      local root = deep
      for _ = 1, geometry.MAX_DEPTH + 2 do
        root = { child = root }
      end
      assert.same({}, geometry.collect({ { name = "r", value = root } }, {}))
    end)

    it("stops at the object cap", function()
      local many = {}
      for i = 1, geometry.MAX_OBJECTS + 10 do
        many[i] = { x = i, y = 0 }
      end
      local list = geometry.collect({ { name = "m", value = many } }, {})
      assert.equal(geometry.MAX_OBJECTS, #list)
    end)

    describe("visit cap", function()
      local saved
      before_each(function()
        saved = geometry.MAX_VISITS
      end)
      after_each(function()
        geometry.MAX_VISITS = saved
      end)

      -- r -> a -> b -> c, where only c has a position: c is the 4th table visited.
      local function chain()
        return { a = { b = { c = { x = 1, y = 1 } } } }
      end

      it("stops walking after MAX_VISITS tables, positioned or not", function()
        geometry.MAX_VISITS = 3
        assert.same({}, geometry.collect({ { name = "r", value = chain() } }, {}))
        geometry.MAX_VISITS = 4
        assert.same({ "r.a.b.c" }, paths(geometry.collect({ { name = "r", value = chain() } }, {})))
      end)

      it("counts across all roots", function()
        geometry.MAX_VISITS = 4
        local roots = { { name = "r", value = chain() }, { name = "s", value = { x = 0, y = 0 } } }
        assert.same({ "r.a.b.c" }, paths(geometry.collect(roots, {})))
      end)

      it("is large enough for real games by default", function()
        assert.is_true(geometry.MAX_VISITS >= 10000)
      end)
    end)

    it("builds an entry's path only when it's asked for", function()
      local game = { ship = { x = 1, y = 2 } }
      local entry = geometry.collect({ { name = "game", value = game } }, {})[1]
      assert.is_nil(rawget(entry, "path"))
      assert.equal("game.ship", entry.path)
      assert.equal("game.ship", rawget(entry, "path")) -- worked out once
    end)

    it("gives every entry its own key list", function()
      local game = { a = { x = 1, y = 1, b = { x = 2, y = 2 } } }
      local found = {}
      for _, e in ipairs(geometry.collect({ { name = "game", value = game } }, {})) do
        found[e.path] = e.keys
      end
      assert.same({ "a" }, found["game.a"])
      assert.same({ "a", "b" }, found["game.a.b"])
      found["game.a"][1] = "changed"
      assert.same({ "a", "b" }, found["game.a.b"])
    end)
  end)

  describe("pick", function()
    local small = { x = 10, y = 10, w = 10, h = 10 }
    local big = { x = 0, y = 0, w = 100, h = 100 }
    local list = geometry.collect({ { name = "g", value = { big = big, small = small } } }, {})

    it("prefers the smallest box under the point", function()
      assert.equal(small, geometry.pick(list, 15, 15).value)
      assert.equal(big, geometry.pick(list, 50, 50).value)
    end)

    it("returns nil when nothing is there", function()
      assert.is_nil(geometry.pick(list, 500, 500))
    end)
  end)

  describe("hits", function()
    local small = { x = 10, y = 10, w = 10, h = 10 }
    local mid = { x = 5, y = 5, w = 30, h = 30 }
    local big = { x = 0, y = 0, w = 100, h = 100 }
    local list = geometry.collect({
      { name = "g", value = { big = big, small = small, mid = mid } },
    }, {})

    local function values(hits)
      local out = {}
      for i, e in ipairs(hits) do
        out[i] = e.value
      end
      return out
    end

    it("lists every box under the point, smallest first", function()
      assert.same({ small, mid, big }, values(geometry.hits(list, 15, 15)))
      assert.same({ mid, big }, values(geometry.hits(list, 30, 30)))
    end)

    it("is empty when nothing is there", function()
      assert.same({}, geometry.hits(list, 500, 500))
    end)

    it("orders boxes of equal size by path, whatever order they were collected in", function()
      local a = { x = 0, y = 0, w = 10, h = 10 }
      local b = { x = 0, y = 0, w = 10, h = 10 }
      local forward = { { value = a, path = "g.a", x = 0, y = 0, w = 10, h = 10 } }
      forward[2] = { value = b, path = "g.b", x = 0, y = 0, w = 10, h = 10 }
      local backward = { forward[2], forward[1] }
      assert.same({ a, b }, values(geometry.hits(forward, 5, 5)))
      assert.same({ a, b }, values(geometry.hits(backward, 5, 5)))
    end)
  end)
end)
