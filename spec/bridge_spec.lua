local bridge = require("loupe.bridge")
describe("local MCP transport", function()
  local savedLove, files, renamer, api, instance
  local id = string.rep("a", 32)
  local function hex(value)
    return (value:gsub(".", function(c)
      return ("%02x"):format(c:byte())
    end))
  end
  local function request(action, root, path, kind, value, expiry, session)
    files["loupe-mcp/" .. id .. ".request"] = table.concat({
      session or files["loupe-mcp/session"],
      tostring(expiry or os.time() + 8),
      action,
      hex(root or ""),
      path or "",
      kind or "nil",
      hex(value or ""),
    }, "\n")
    instance:poll()
    return files["loupe-mcp/" .. id .. ".response"]
  end
  before_each(function()
    files = {}
    savedLove = rawget(_G, "love")
    love = {
      timer = {
        getTime = function()
          return 1.25
        end,
      },
      filesystem = {
        createDirectory = function()
          return true
        end,
        write = function(path, data)
          files[path] = data
          return true
        end,
        read = function(path)
          return files[path]
        end,
        remove = function(path)
          files[path] = nil
          return true
        end,
        getSaveDirectory = function()
          return "/save"
        end,
        getInfo = function(path)
          return files[path] and { size = #files[path] }
        end,
        getDirectoryItems = function()
          local out = {}
          for path in pairs(files) do
            out[#out + 1] = path:match("[^/]+$")
          end
          return out
        end,
      },
      graphics = {
        captureScreenshot = function(fn)
          fn({
            encode = function()
              return "PNG"
            end,
          })
        end,
      },
    }
    rawset(_G, "love", love)
    renamer = stub(os, "rename", function(from, to)
      files[to:sub(7)] = files[from:sub(7)]
      files[from:sub(7)] = nil
      return true
    end)
    api = {
      call = function(_, action, root, keys, value)
        return { action = action, root = root, key = keys[1], value = value }
      end,
    }
    instance = bridge.new(api)
  end)
  after_each(function()
    renamer:revert()
    rawset(_G, "love", savedLove)
  end)
  it("decodes scalar requests without executing code", function()
    local out = request("set", "game", "s" .. hex("speed"), "number", "390")
    assert.matches('"value":390', out, 1, true)
    assert.matches('"key":"speed"', out, 1, true)
    assert.is_nil(files["loupe-mcp/" .. id .. ".request"])
    out = request("set", "game", "n" .. hex("1"), "boolean", "true")
    assert.matches('"value":true', out, 1, true)
    out = request("set", "game", "", "string", 'a"\n\\b')
    assert.matches('a\\"\\u000a\\\\b', out, 1, true)
  end)
  it("rejects stale, expired and malformed requests", function()
    assert.matches('"ok":false', request("status", nil, nil, nil, nil, nil, "old"), 1, true)
    assert.matches('"ok":false', request("status", nil, nil, nil, nil, os.time() - 1), 1, true)
    assert.matches('"ok":false', request("set", "game", "szz"), 1, true)
  end)
  it("captures screenshots and closes only its own session", function()
    assert.matches(id .. ".png", request("screenshot"), 1, true)
    assert.equal("PNG", files["loupe-mcp/" .. id .. ".png"])
    files["loupe-mcp/session"] = "replacement"
    instance:close()
    assert.equal("replacement", files["loupe-mcp/session"])
    instance = bridge.new(api)
    instance:close()
    assert.is_nil(files["loupe-mcp/session"])
  end)
end)
