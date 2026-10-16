local love_stub = require("spec.support.love_stub")

describe("loupe", function()
  before_each(function()
    package.loaded["loupe"] = nil
  end)

  it("exposes a semantic version string", function()
    local loupe = require("loupe")
    assert.is_string(loupe._VERSION)
    assert.matches("^%d+%.%d+%.%d+$", loupe._VERSION)
  end)

  it("loads without a love global (headless or plain Lua)", function()
    love_stub.uninstall()
    assert.has_no.errors(function()
      require("loupe")
    end)
  end)
end)

describe("love_stub", function()
  after_each(function()
    love_stub.uninstall()
  end)

  it("records graphics calls in order", function()
    local fake = love_stub.install()
    love.graphics.setColor(1, 0, 0, 1)
    love.graphics.rectangle("fill", 1, 2, 3, 4)
    assert.same({
      { "setColor", 1, 0, 0, 1 },
      { "rectangle", "fill", 1, 2, 3, 4 },
    }, fake.calls)
  end)

  it("can install without graphics to mimic headless runs", function()
    love_stub.install({ graphics = false })
    assert.is_nil(love.graphics)
  end)

  it("restores the previous love global on uninstall", function()
    local before = rawget(_G, "love")
    love_stub.install()
    love_stub.uninstall()
    assert.equal(before, rawget(_G, "love"))
  end)
end)
