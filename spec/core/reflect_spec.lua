local reflect = require("loupe.core.reflect")

describe("core.reflect", function()
  describe("kind", function()
    it("classifies plain values", function()
      assert.equal("number", reflect.kind(1.5))
      assert.equal("boolean", reflect.kind(false))
      assert.equal("string", reflect.kind("x"))
      assert.equal("table", reflect.kind({ a = 1 }))
      assert.equal("function", reflect.kind(print))
      assert.equal("nil", reflect.kind(nil))
    end)

    it("recognizes {r, g, b} and {r, g, b, a} colors in 0..1", function()
      assert.equal("color", reflect.kind({ 1, 0.5, 0 }))
      assert.equal("color", reflect.kind({ 0.9, 0.95, 1, 1 }))
    end)

    it("doesn't mistake other number lists for colors", function()
      assert.equal("table", reflect.kind({ 1, 2, 3 })) -- out of range
      assert.equal("table", reflect.kind({ 0.5, 0.5 })) -- too short
      assert.equal("table", reflect.kind({ 0.1, 0.2, 0.3, 0.4, 0.5 })) -- too long
      assert.equal("table", reflect.kind({ 1, 1, 1, name = "white" })) -- extra keys
      assert.equal("table", reflect.kind({ 1, "1", 1 })) -- not all numbers
      assert.equal("table", reflect.kind({ [2] = 1, [3] = 1, [4] = 1 })) -- not 1..n
    end)
  end)

  describe("fields", function()
    it("lists the array part first, in order, then other keys sorted", function()
      local fields = reflect.fields({ "a", "b", zeta = 1, alpha = 2, [10] = "sparse" })
      local labels = {}
      for i, f in ipairs(fields) do
        labels[i] = f.label
      end
      assert.same({ "[1]", "[2]", "[10]", "alpha", "zeta" }, labels)
    end)

    it("carries key, value and kind", function()
      local f = reflect.fields({ speed = 3 })[1]
      assert.same({ key = "speed", value = 3, kind = "number", label = "speed" }, f)
    end)

    it("handles keys that aren't strings or numbers", function()
      local key = {}
      local fields = reflect.fields({ [key] = 1, [true] = 2 })
      assert.equal(2, #fields)
    end)

    it("survives keys whose __tostring throws or returns a non-string", function()
      local function key(tostringResult)
        return setmetatable({}, {
          __tostring = function()
            if tostringResult == nil then
              error("tostring broke")
            end
            return tostringResult
          end,
        })
      end
      local t = { [key()] = 1, [key()] = 2, [key({})] = 3, [key("named")] = 4 }
      local fields = reflect.fields(t)
      assert.equal(4, #fields)
      local labels = {}
      for _, f in ipairs(fields) do
        labels[#labels + 1] = f.label
      end
      table.sort(labels)
      assert.same({ "[named]", "[table]", "[table]", "[table]" }, labels)
    end)
  end)

  describe("labels and paths", function()
    it("labels keys the way you'd write them", function()
      assert.equal("speed", reflect.keyLabel("speed"))
      assert.equal("[3]", reflect.keyLabel(3))
      assert.equal('["two words"]', reflect.keyLabel("two words"))
      assert.equal("[true]", reflect.keyLabel(true))
    end)

    it("builds child key lists without changing the parent's", function()
      local parent = { "rocks" }
      assert.same({ "rocks", 3 }, reflect.childKeys(parent, 3))
      assert.same({ "rocks" }, parent)
    end)

    it("resolves key lists back to values", function()
      local game = { rocks = { { r = 5 } } }
      assert.equal(game.rocks[1], reflect.resolve(game, { "rocks", 1 }))
      assert.equal(game, reflect.resolve(game, {}))
      assert.is_nil(reflect.resolve(game, { "rocks", 9 }))
      assert.is_nil(reflect.resolve(game, { "rocks", 1, "r", "deeper" }))
    end)

    it("builds Lua-style paths", function()
      assert.equal("game.rocks", reflect.childPath("game", "rocks"))
      assert.equal("game.rocks[3]", reflect.childPath("game.rocks", 3))
      assert.equal('game["two words"]', reflect.childPath("game", "two words"))
    end)

    it("builds a whole path from a root name and keys", function()
      assert.equal("game", reflect.path("game", {}))
      assert.equal('game.rocks[3]["two words"]', reflect.path("game", { "rocks", 3, "two words" }))
    end)

    it("resolves the table holding a key list's last field", function()
      local game = { rocks = { { r = 5 } } }
      assert.equal(game.rocks[1], reflect.resolveParent(game, { "rocks", 1, "r" }))
      assert.equal(game, reflect.resolveParent(game, { "score" }))
      assert.is_nil(reflect.resolveParent(game, { "rocks", 9, "r" }))
      assert.is_nil(reflect.resolveParent(game, { "rocks", 1, "r", "deeper", "x" }))
    end)
  end)

  describe("summary", function()
    it("describes tables by size", function()
      assert.equal("{3}", reflect.summary({ 1, 2, x = 3 }))
      assert.equal("{}", reflect.summary({}))
    end)

    it("describes other values briefly", function()
      assert.equal("function", reflect.summary(print))
      assert.equal("nil", reflect.summary(nil))
      assert.equal("1.5", reflect.summary(1.5))
    end)

    it("names userdata by its type() method when it has one", function()
      if not newproxy then
        return -- Lua 5.2+ has no newproxy; LuaJIT and 5.1 do
      end
      local u = newproxy(true)
      getmetatable(u).__index = {
        type = function()
          return "Image"
        end,
      }
      assert.equal("Image", reflect.summary(u))
      assert.equal("userdata", reflect.summary(newproxy(false)))
    end)
  end)
end)
