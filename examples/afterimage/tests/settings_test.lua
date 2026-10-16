-- settings.txt: parsed never executed, defaults for anything bad, written only on change.
local settings = require("src.settings")

local d = settings.defaults()
assert(d.art == "illustrated" and d.reduced_motion == false and d.muted == false)
assert(d.music == 0.85 and d.effects == 0.85, "defaults match src/audio.lua")

local parsed =
  settings.parse("art=vector\nmuted=true\nmusic=0.4\r\neffects=1\nreduced_motion=true\n")
assert(parsed.art == "vector" and parsed.muted == true and parsed.reduced_motion == true)
assert(parsed.music == 0.4 and parsed.effects == 1)

local bad = settings.parse(
  "art=os.exit()\nmuted=yes\nmusic=2\neffects=nan\nunknown=1\n= \ngarbage\nmusic=-0.1"
)
assert(bad.art == "illustrated" and bad.muted == false, "bad values keep defaults")
assert(bad.music == 0.85 and bad.effects == 0.85 and bad.unknown == nil)
assert(settings.parse(nil).art == "illustrated" and settings.parse(42).music == 0.85)

-- Round trip, fixed order, two decimals for volumes.
local text = settings.serialize({
  art = "vector",
  reduced_motion = true,
  muted = false,
  music = 0.30000000000000004,
  effects = 0.7,
})
assert(text == "art=vector\nreduced_motion=true\nmuted=false\nmusic=0.30\neffects=0.70\n", text)
local again = settings.parse(text)
assert(again.music == 0.3 and again.effects == 0.7 and again.art == "vector")
assert(settings.serialize({}) == settings.serialize(settings.defaults()), "missing -> defaults")

-- The store: reads once, writes only when the text changes, survives a failing file system.
local files, writes = {}, 0
local fs = {
  read = function(name)
    return files[name]
  end,
  write = function(name, body)
    writes = writes + 1
    files[name] = body
  end,
}
local store = settings.new(fs)
local values = store.load()
assert(values.art == "illustrated" and writes == 0, "a first launch writes nothing")
assert(store.save(values) == true and writes == 1 and files["settings.txt"])
assert(store.save(values) == false and writes == 1, "unchanged settings are not rewritten")
values.muted = true
assert(store.save(values) == true and writes == 2)
local second = settings.new(fs)
local reopened = second.load()
assert(reopened.muted == true, "settings survive a restart")
assert(second.save(reopened) == false and writes == 2, "a loaded file counts as saved")

local broken = settings.new({
  read = function()
    error("no save directory")
  end,
  write = function()
    error("read-only")
  end,
})
assert(broken.load().art == "illustrated", "an unreadable file falls back to defaults")
assert(broken.save(settings.defaults()) == false, "a failed write is reported, not raised")

print("PASS: settings parse, defaults, round trip, write on change, failure tolerance")
