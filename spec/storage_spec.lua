local love_stub = require("spec.support.love_stub")
local storage = require("loupe.storage")

local function tempFolder()
  local path = os.tmpname()
  os.remove(path)
  assert(os.execute(('mkdir "%s"'):format(path)))
  return path
end

local function touch(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text or "")
  f:close()
end

describe("storage", function()
  local fake
  before_each(function()
    fake = love_stub.install()
  end)
  after_each(function()
    love_stub.uninstall()
  end)

  describe("running from a folder", function()
    local folder
    before_each(function()
      folder = tempFolder()
      touch(folder .. "/main.lua")
      fake.source = folder
    end)
    after_each(function()
      os.remove(folder .. "/main.lua")
      os.remove(folder .. "/" .. storage.FILE)
      os.remove(folder)
    end)

    it("writes next to main.lua and reads it back", function()
      local ok, where = storage.write("return {}")
      assert.is_true(ok)
      assert.equal(folder .. "/" .. storage.FILE, where)
      assert.equal("return {}", storage.read())
      assert.same({}, fake.files) -- not the save directory
    end)

    it("replaces an existing file, leaving no temp file behind", function()
      touch(folder .. "/" .. storage.FILE, "old")
      assert.is_true((storage.write("new")))
      assert.equal("new", storage.read())
      assert.is_nil(io.open(folder .. "/" .. storage.FILE .. ".tmp", "r"))
    end)

    it("reports a folder it can't write to, keeping the old file", function()
      touch(folder .. "/" .. storage.FILE, "old")
      assert(os.execute(('chmod 555 "%s"'):format(folder)))
      -- root ignores the mode (e.g. in a docker container), so there's nothing to test.
      local probe = io.open(folder .. "/probe", "w")
      if probe then
        probe:close()
        os.remove(folder .. "/probe")
        os.execute(('chmod 755 "%s"'):format(folder))
        pending("this user can write to a read-only folder (root?)")
        return
      end
      local ok, err = storage.write("new")
      os.execute(('chmod 755 "%s"'):format(folder))
      assert.is_false(ok)
      assert.is_string(err)
      assert.equal("old", storage.read())
    end)

    it("reads nothing when there's no file yet", function()
      assert.is_nil(storage.read())
    end)

    it("reports the folder, or nil once fused", function()
      assert.equal(folder, storage.sourceFolder())
      fake.fused = true
      assert.is_nil(storage.sourceFolder())
    end)
  end)

  describe("fused or packaged", function()
    it("uses the save directory", function()
      fake.fused = true
      local ok, where = storage.write("return {}")
      assert.is_true(ok)
      assert.equal("/save/" .. storage.FILE, where)
      assert.equal("return {}", fake.files[storage.FILE])
      assert.equal("return {}", storage.read())
    end)

    it("falls back to the save directory when the source isn't a folder", function()
      fake.source = "/games/thing.love"
      storage.write("x")
      assert.equal("x", fake.files[storage.FILE])
    end)
  end)

  describe("parse", function()
    it("loads the returned table", function()
      assert.same({ { "game", { "x" }, 1 } }, storage.parse('return { { "game", { "x" }, 1 } }'))
    end)

    it("runs the file with no globals, so it can only be data", function()
      local data, err = storage.parse("return os.getenv('HOME')")
      assert.is_nil(data)
      assert.matches("os", err)
    end)

    it("refuses precompiled bytecode", function()
      local bytecode = string.dump(function()
        return {}
      end)
      local data, err = storage.parse(bytecode)
      assert.is_nil(data)
      assert.matches("bytecode", err)
    end)

    it("stops a file that never finishes", function()
      local data, err = storage.parse("while true do end")
      assert.is_nil(data)
      assert.matches("too long", err)
    end)

    it("puts back whatever debug hook was set before", function()
      local function hook() end
      local before = { debug.gethook() }
      debug.sethook(hook, "", 1e9)
      storage.parse("return {}")
      storage.parse("while true do end")
      local after = { debug.gethook() }
      debug.sethook(before[1], before[2], before[3])
      assert.equal(hook, after[1])
      assert.equal(1e9, after[3])
    end)

    it("reports syntax errors", function()
      local data, err = storage.parse("return {")
      assert.is_nil(data)
      assert.matches("^loupe_overrides%.lua:1:", err)
    end)
  end)
end)
