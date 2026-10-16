local registry = require("loupe.core.registry")

describe("core.registry", function()
  local reg
  before_each(function()
    reg = registry.new()
  end)

  it("starts empty", function()
    assert.same({}, reg:roots())
  end)

  it("lists watched tables in the order they were watched", function()
    local a, b = {}, {}
    reg:watch(a, "a")
    reg:watch(b, "b")
    local roots = reg:roots()
    assert.equal(2, #roots)
    assert.same({ "a", "b" }, { roots[1].name, roots[2].name })
    assert.equal(a, roots[1].value)
  end)

  it("resolves getter functions every time, so replaced tables are followed", function()
    local game = { level = 1 }
    reg:watch(function()
      return game
    end, "game")
    assert.equal(1, reg:roots()[1].value.level)
    game = { level = 2 }
    assert.equal(2, reg:roots()[1].value.level)
  end)

  it("reports a getter that errors instead of propagating the error", function()
    reg:watch(function()
      error("boom")
    end, "broken")
    local root = reg:roots()[1]
    assert.is_nil(root.value)
    assert.matches("boom", root.error)
  end)

  it("replaces a root watched again under the same name, keeping its position", function()
    reg:watch({}, "a")
    reg:watch({}, "b")
    local replacement = {}
    reg:watch(replacement, "a")
    local roots = reg:roots()
    assert.equal(2, #roots)
    assert.equal(replacement, roots[1].value)
  end)

  it("unwatches by name", function()
    reg:watch({}, "a")
    reg:watch({}, "b")
    reg:unwatch("a")
    assert.equal("b", reg:roots()[1].name)
    assert.has_no.errors(function()
      reg:unwatch("missing")
    end)
    assert.equal(1, #reg:roots())
  end)

  it("requires a name", function()
    assert.has_error(function()
      reg:watch({})
    end)
  end)

  it("rejects targets that are neither tables nor functions", function()
    assert.has_error(function()
      reg:watch(42, "n")
    end)
  end)
end)
