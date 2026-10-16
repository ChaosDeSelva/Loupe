local loveStub = require("spec.support.love_stub")
describe("MCP lifecycle", function()
  local loupe, oldBridge, closed, polled, api, updated
  before_each(function()
    loveStub.install()
    oldBridge = package.loaded["loupe.bridge"]
    closed, polled, updated = 0, 0, 0
    package.loaded["loupe.bridge"] = {
      new = function(remote)
        api = remote
        return {
          directory = "/local/bridge",
          poll = function()
            polled = polled + 1
          end,
          close = function()
            closed = closed + 1
          end,
        }
      end,
    }
    package.loaded["loupe"] = nil
    loupe = require("loupe")
    love.update = function()
      updated = updated + 1
    end
    love.draw = function() end
  end)
  after_each(function()
    loupe.detach()
    package.loaded["loupe.bridge"] = oldBridge
    loveStub.uninstall()
  end)
  it("stays connected with overlay closed and polls while paused", function()
    loupe.attach({ mcp = true, hotReload = false })
    assert.equal("/local/bridge", loupe.bridgeDirectory())
    love.draw()
    assert.equal(0, closed)
    api:call("pause")
    love.update(0.016)
    assert.equal(1, polled)
    assert.equal(0, updated)
    loupe.detach()
    assert.equal(1, closed)
  end)
  it("does not enable MCP by default", function()
    loupe.attach({ hotReload = false })
    love.update(0.016)
    assert.equal(0, polled)
    assert.is_nil(loupe.bridgeDirectory())
  end)
end)
