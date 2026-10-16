local serialize = require("loupe.core.serialize")

local function roundTrip(v)
  local load = loadstring or load
  return assert(load("return " .. serialize.value(v)))()
end

describe("core.serialize", function()
  it("writes scalars as Lua literals", function()
    assert.equal("42", serialize.value(42))
    assert.equal("-3", serialize.value(-3))
    assert.equal("true", serialize.value(true))
    assert.equal("nil", serialize.value(nil))
    assert.equal('"hi"', serialize.value("hi"))
  end)

  -- %d goes through a C long, which is 32 bits on 64-bit Windows.
  it("writes integers past 2^31 exactly", function()
    assert.equal("1099511627776", serialize.value(2 ^ 40))
    assert.equal("-1099511627776", serialize.value(-(2 ^ 40)))
    assert.equal("9007199254740991", serialize.value(2 ^ 53 - 1))
    assert.equal("4294967296", serialize.value(2 ^ 32))
  end)

  it("keeps full precision for fractions", function()
    assert.equal(0.1, roundTrip(0.1))
    assert.equal(1 / 3, roundTrip(1 / 3))
    assert.equal(1e300, roundTrip(1e300))
  end)

  -- Saved files are read by people: no "0.050000000000000003" for a clean 0.05.
  it("writes the shortest fraction that reads back equal", function()
    assert.equal("0.05", serialize.value(0.05))
    assert.equal("-0.25", serialize.value(-0.25))
    assert.equal("0.7999999999999999", serialize.value(0.7 + 0.1)) -- needs 16 digits
    assert.equal("0.30000000000000004", serialize.value(0.1 + 0.2)) -- needs 17
    assert.equal(0.1 + 0.2, roundTrip(0.1 + 0.2))
    assert.equal(1 / 3, roundTrip(1 / 3))
    assert.equal(2 / 3, roundTrip(2 / 3))
  end)

  it("writes infinities and NaN as expressions", function()
    assert.equal(math.huge, roundTrip(math.huge))
    assert.equal(-math.huge, roundTrip(-math.huge))
    local nan = roundTrip(0 / 0)
    assert.is_true(nan ~= nan)
  end)

  it("escapes strings safely", function()
    local s = 'quote " backslash \\ newline \n tab \t nul \0 end'
    assert.equal(s, roundTrip(s))
  end)

  it("writes tables with array items first and sorted keys", function()
    assert.equal("{}", serialize.value({}))
    assert.equal('{ 1, 2, b = true, z = "x" }', serialize.value({ 1, 2, z = "x", b = true }))
  end)

  it("brackets keys that aren't identifiers", function()
    assert.equal(
      '{ [10] = 1, ["end"] = 3, ["two words"] = 2 }',
      serialize.value({
        [10] = 1,
        ["two words"] = 2,
        ["end"] = 3,
      })
    )
  end)

  it("keeps keys for array entries after a hole", function()
    -- `#` on a table with holes is unspecified. On LuaJIT (LÖVE's runtime)
    -- this one reports 4 while ipairs stops after [1].
    local v = { 1, 2, 3, 4 }
    v[2] = nil
    assert.same(v, roundTrip(v))
    assert.equal("{ 1, [3] = 3, [4] = 4 }", serialize.value(v))
  end)

  it("round-trips nested tables", function()
    local v = { name = "ship", color = { 1, 0.5, 0, 1 }, keys = { "a", 2 } }
    assert.same(v, roundTrip(v))
  end)

  it("refuses cycles and values it can't write", function()
    local t = {}
    t.self = t
    assert.has_error(function()
      serialize.value(t)
    end)
    assert.has_error(function()
      serialize.value(print)
    end)
  end)
end)
