local hook = require("loupe.core.hook")

describe("core.hook", function()
  local host, calls

  -- A wrapper that records what it saw, then calls through.
  local function tracing(name)
    return function(original, ...)
      calls[#calls + 1] = { name, original ~= nil, ... }
      if original then
        return original(...)
      end
    end
  end

  before_each(function()
    calls = {}
    host = {
      update = function(dt)
        calls[#calls + 1] = { "game.update", dt }
      end,
      custom = "game data",
    }
  end)

  it("routes calls through the wrapper to the original", function()
    hook.install(host, { update = tracing("wrap.update") })
    host.update(0.5)
    assert.same({ { "wrap.update", true, 0.5 }, { "game.update", 0.5 } }, calls)
  end)

  it("still installs a wrapper when the game never defined that callback", function()
    hook.install(host, { keypressed = tracing("wrap.keypressed") })
    assert.is_function(host.keypressed)
    host.keypressed("f1")
    assert.same({ { "wrap.keypressed", false, "f1" } }, calls)
  end)

  it("keeps wrapping when the game reassigns a callback later", function()
    hook.install(host, { update = tracing("wrap.update") })
    host.update = function(dt)
      calls[#calls + 1] = { "scene.update", dt }
    end
    host.update(1)
    assert.same({ { "wrap.update", true, 1 }, { "scene.update", 1 } }, calls)
  end)

  it("lets the game clear a callback", function()
    hook.install(host, { update = tracing("wrap.update") })
    host.update = nil
    host.update(1)
    assert.same({ { "wrap.update", false, 1 } }, calls)
  end)

  it("leaves unrelated fields alone, including new ones", function()
    hook.install(host, { update = tracing("wrap.update") })
    assert.equal("game data", host.custom)
    host.extra = 42
    assert.equal(42, rawget(host, "extra"))
  end)

  it("exposes the current original", function()
    local handle = hook.install(host, { update = tracing("wrap.update") })
    local replacement = function() end
    host.update = replacement
    assert.equal(replacement, handle.original("update"))
  end)

  -- hump.gamestate.registerEvents() and similar libraries run after attach
  -- (from love.load) and chain to whatever love.update was: the wrapper.
  describe("games that chain to the callback they replace", function()
    local function chain(name)
      local old = host.update
      host.update = function(dt)
        old(dt)
        calls[#calls + 1] = { name, dt }
      end
    end

    it("runs a chain set up after install once per call, through the wrapper once", function()
      hook.install(host, { update = tracing("wrap.update") })
      chain("gamestate")
      host.update(1)
      host.update(1) -- and again: the first call left no state behind
      local once = { { "wrap.update", true, 1 }, { "game.update", 1 }, { "gamestate", 1 } }
      assert.same({ once[1], once[2], once[3], once[1], once[2], once[3] }, calls)
    end)

    it("handles chains of chains", function()
      hook.install(host, { update = tracing("wrap.update") })
      chain("inner")
      chain("outer")
      host.update(2)
      assert.same({
        { "wrap.update", true, 2 },
        { "game.update", 2 },
        { "inner", 2 },
        { "outer", 2 },
      }, calls)
    end)

    it("handles a chain set up before install", function()
      chain("gamestate")
      hook.install(host, { update = tracing("wrap.update") })
      host.update(3)
      assert.same({ { "wrap.update", true, 3 }, { "game.update", 3 }, { "gamestate", 3 } }, calls)
    end)

    it("ends a chain quietly when nothing was there before", function()
      host.update = nil
      hook.install(host, { update = tracing("wrap.update") })
      chain("gamestate")
      host.update(4)
      assert.same({ { "wrap.update", true, 4 }, { "gamestate", 4 } }, calls)
    end)

    it("keeps a chain working, without loupe, after remove", function()
      local handle = hook.install(host, { update = tracing("wrap.update") })
      chain("inner")
      chain("outer")
      handle.remove()
      host.update(5)
      assert.same({ { "game.update", 5 }, { "inner", 5 }, { "outer", 5 } }, calls)
    end)

    it("ignores the game assigning the wrapper to itself", function()
      hook.install(host, { update = tracing("wrap.update") })
      host.update = host.update
      host.update(6)
      assert.same({ { "wrap.update", true, 6 }, { "game.update", 6 } }, calls)
    end)

    it("still lets a plain scene switch replace the callback", function()
      hook.install(host, { update = tracing("wrap.update") })
      chain("gamestate")
      host.update = function(dt)
        calls[#calls + 1] = { "menu", dt }
      end
      host.update(7)
      assert.same({ { "wrap.update", true, 7 }, { "menu", 7 } }, calls)
    end)
  end)

  describe("remove", function()
    it("restores the originals and the plain table", function()
      local before = host.update
      local handle = hook.install(host, { update = tracing("w"), draw = tracing("w") })
      handle.remove()
      assert.equal(before, rawget(host, "update"))
      assert.is_nil(rawget(host, "draw"))
      assert.is_nil(getmetatable(host))
    end)

    it("restores callbacks the game assigned while wrapped", function()
      local handle = hook.install(host, { update = tracing("w") })
      local replacement = function() end
      host.update = replacement
      handle.remove()
      assert.equal(replacement, rawget(host, "update"))
    end)

    it("is safe to call twice", function()
      local original = host.update
      local handle = hook.install(host, { update = tracing("w") })
      handle.remove()
      assert.has_no.errors(handle.remove)
      assert.is_nil(getmetatable(host))
      assert.equal(original, rawget(host, "update"))
    end)
  end)

  it("refuses a table that already has a metatable", function()
    local original = host.update
    setmetatable(host, {})
    assert.has_error(function()
      hook.install(host, { update = tracing("w") })
    end, "loupe: the callback table already has a metatable")
    assert.equal(original, rawget(host, "update")) -- left untouched
  end)
end)
