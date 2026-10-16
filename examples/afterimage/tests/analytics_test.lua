-- The analytics contract (schema_version 1), without LÖVE: every event, its
-- exact property keys, rs_kind, the place rule, pause-free timers, the
-- modified flag, automation labels, the exit mailbox and the collection gate.
local analytics = require("src.analytics")
local sim = require("src.sim")
local play = require("tests.pilot")
local json = require("lib.ravensight.json")

local COMMON = { "schema_version", "build", "platform", "distribution", "qa_source", "synthetic" }
COMMON[#COMMON + 1] = "rs_kind"
local RUN = { "run_id", "mode", "modified" }
-- The contract, written out by hand: a change to src/analytics.lua that adds,
-- drops or renames a key has to change this table too.
local EXPECTED = {
  session_started = { kind = "none", keys = { "art_style", "reduced_motion" } },
  run_started = { kind = "none", run = true, keys = {} },
  sector_started = {
    kind = "level_start",
    run = true,
    keys = { "level", "sector", "cycle", "hull", "run_time_s" },
  },
  pickup_collected = {
    kind = "none",
    run = true,
    keys = { "sector", "salvage", "turbo", "prism", "hull_patch", "total" },
  },
  sector_completed = {
    kind = "level_complete",
    run = true,
    keys = {
      "level",
      "sector",
      "sector_time_s",
      "run_time_s",
      "kills",
      "hits_taken",
      "hull",
      "salvage",
      "rank",
      "boss_defeated",
    },
  },
  upgrade_purchased = {
    kind = "none",
    run = true,
    keys = { "sector", "upgrade", "upgrade_rank", "cost", "salvage_left" },
  },
  player_died = {
    kind = "death",
    run = true,
    keys = { "level", "sector", "sector_time_s", "run_time_s", "kills", "hits_taken", "rank" },
  },
  run_completed = {
    kind = "none",
    run = true,
    keys = { "sectors_cleared", "run_time_s", "kills", "rank", "salvage" },
  },
  run_abandoned = {
    kind = "none",
    run = true,
    keys = { "sector", "sector_time_s", "run_time_s", "sectors_cleared", "screen" },
  },
  art_style_changed = { kind = "none", keys = { "art_style", "via" } },
  inspector_opened = { kind = "none", keys = { "screen", "opens" } },
  session_ended = {
    kind = "none",
    keys = {
      "wall_time_s",
      "runs_started",
      "runs_completed",
      "sectors_completed",
      "inspector_opens",
    },
  },
}

local function sorted(set)
  local out = {}
  for key in pairs(set) do
    out[#out + 1] = key
  end
  table.sort(out)
  return table.concat(out, ",")
end

local function expectedKeys(name)
  local spec = EXPECTED[name]
  local set = {}
  for _, list in ipairs({ COMMON, spec.run and RUN or {}, spec.keys }) do
    for _, key in ipairs(list) do
      set[key] = true
    end
  end
  return set
end

-- The contract table in the module matches the one written here.
local names = {}
for name in pairs(analytics.EVENTS) do
  names[#names + 1] = name
end
assert(#names == 12, "twelve events in schema 1, found " .. #names)
for name in pairs(EXPECTED) do
  assert(analytics.EVENTS[name], "missing event " .. name)
  assert(analytics.EVENTS[name].kind == EXPECTED[name].kind, name .. " rs_kind")
  assert(sorted(analytics.allowedKeys(name)) == sorted(expectedKeys(name)), name .. " allowlist")
end

-- A fake SDK, clock and Loupe counter.
local function harness(options)
  options = options or {}
  local h = { sent = {}, enabled = options.enabled ~= false, revision = 0, now = 100 }
  h.mailboxText = false
  local seed = 7
  h.a = analytics.new({
    sdk = {
      track = function(name, data)
        h.sent[#h.sent + 1] = { name = name, data = data }
      end,
      enabled = function()
        return h.enabled
      end,
    },
    editRevision = function()
      return h.revision
    end,
    random = function(a, b)
      seed = (seed * 48271) % 2147483647
      return a + seed % (b - a + 1)
    end,
    clock = function()
      return h.now
    end,
    build = "1.2.0",
    platform = "linux",
    distribution = options.distribution or "native-release",
    qaSource = options.qaSource or "none",
    mailbox = options.mailbox and function(text)
      h.mailboxText = text
    end or nil,
    encode = json.encode,
  })
  return h
end

local function check(event)
  local spec = EXPECTED[event.name]
  assert(spec, "unexpected event " .. event.name)
  local d = event.data
  assert(sorted(d) == sorted(expectedKeys(event.name)), event.name .. " keys: " .. sorted(d))
  assert(d.rs_kind == spec.kind, event.name .. " rs_kind")
  assert(d.schema_version == 1, "schema_version")
  for key, value in pairs(d) do
    local t = type(value)
    assert(t == "string" or t == "number" or t == "boolean", event.name .. "." .. key .. " flat")
  end
  -- `level` is a place and nothing else.
  if d.level ~= nil then
    assert(type(d.level) == "string" and d.level:match("^sector_%d+$"), "level is the place")
  end
end

local function count(h, name)
  local n = 0
  for _, e in ipairs(h.sent) do
    if e.name == name then
      n = n + 1
    end
  end
  return n
end

-- 1. Collection gate: with the SDK not collecting (keyless, the server's kill
-- switch, a refused key, or the SDK's own opt-out file), nothing is tracked.
do
  local h = harness({ enabled = false })
  local g = sim.new(42)
  h.a:sessionStarted({ art = "vector" })
  h.a:runStarted(g)
  play(g)
  h.a:observe(g)
  h.a:quit("flight")
  assert(#h.sent == 0, "nothing leaves while the SDK is not collecting")
end

-- 1b. One session_started per launch, however often it is asked.
do
  local h = harness()
  h.a:sessionStarted({ art = "vector" })
  h.a:sessionStarted({ art = "vector" })
  assert(#h.sent == 1 and h.sent[1].name == "session_started", "one session start per launch")
  check(h.sent[1])
end

-- 2. A full story run by the reference pilot, with upgrades between sectors.
local story
do
  local h = harness()
  story = h
  h.a:sessionStarted({ art = "illustrated", reduced_motion = false })
  -- A seed the reference pilot wins with this shopping list (the balance pass
  -- made sector 3 of seed 42 a loss).
  local g = sim.new(6)
  h.a:runStarted(g)
  for sector = 1, 3 do
    play(g)
    h.a:update(g.time, true, false)
    h.a:update(30, false, false) -- paused or on a menu: not counted
    h.a:observe(g)
    h.a:observe(g) -- a sector resolves once
    assert(g.state ~= "lost", "the reference pilot wins seed 6")
    if sector < 3 then
      h.a:update(4, false, true) -- docked: run time only
      for _, kind in ipairs({ "power", "drive", "repair" }) do
        local cost = sim.cost(g, kind)
        if sim.buy(g, kind) then
          h.a:upgradePurchased(g, kind, cost)
        end
      end
      g = sim.advance(g)
      h.a:sectorStarted(g)
    end
  end
  assert(g.state == "victory", "story resolves")
  h.a:artStyleChanged(false, "key")
  h.a:inspector(true, "victory")
  h.a:inspector(true, "victory")
  h.a:inspector(false, "victory")
  h.now = 400
  h.a:quit("victory")

  for _, e in ipairs(h.sent) do
    check(e)
  end
  assert(h.sent[1].name == "session_started" and h.sent[2].name == "run_started", "order")
  assert(count(h, "sector_started") == 3 and count(h, "sector_completed") == 3, "three sectors")
  assert(count(h, "pickup_collected") == 3, "pickups aggregated: one event per sector")
  assert(count(h, "run_completed") == 1 and count(h, "run_abandoned") == 0, "a finished run")
  assert(count(h, "inspector_opened") == 1, "an open fires once, not every frame")
  assert(count(h, "session_ended") == 1, "session end")
  assert(count(h, "upgrade_purchased") >= 1, "upgrades")
  assert(#h.sent >= 18 and #h.sent <= 28, "a story run is about 20 to 25 events, got " .. #h.sent)
  print("story run events: " .. #h.sent)
  local runId
  for _, e in ipairs(h.sent) do
    local d = e.data
    if d.run_id then
      runId = runId or d.run_id
      assert(d.run_id == runId and #runId == 12, "one run id for the run")
      assert(d.mode == "story" and d.modified == false, "story, unmodified")
    end
    assert(d.qa_source == "none" and d.synthetic == false, "a player, not automation")
    assert(d.distribution == "native-release" and d.platform == "linux" and d.build == "1.2.0")
    if e.name == "sector_started" then
      assert(d.level == "sector_" .. d.sector, "sector_started names its place")
    end
    if e.name == "sector_completed" then
      assert(d.level == "sector_" .. d.sector and d.rank >= 1, "rank is separate from level")
      assert(d.sector_time_s > 0 and d.sector_time_s <= 100, "pause-free sector time")
    end
    if e.name == "upgrade_purchased" then
      assert(d.upgrade ~= "repair", "a repair is not an upgrade")
    end
    if e.name == "session_ended" then
      assert(d.wall_time_s == 300, "wall time comes from the clock")
      assert(d.runs_started == 1 and d.runs_completed == 1 and d.sectors_completed == 3)
      assert(d.inspector_opens == 1)
    end
  end
  -- The run clock counts flight and dock, never the 30 s "paused" spans.
  local last, flown = nil, 0
  for _, e in ipairs(h.sent) do
    if e.name == "run_completed" then
      last = e
    elseif e.name == "sector_completed" then
      flown = flown + e.data.sector_time_s
    end
  end
  assert(math.abs(last.data.run_time_s - (flown + 8)) < 0.5, "run time excludes pauses")
end

-- 3. Every event in the contract was produced by some path in this file.
do
  local h = harness({ qaSource = "smoke" })
  local g = sim.new(4)
  h.a:runStarted(g)
  sim.hurt(g, 15)
  g.player.invulnerable = 0
  sim.hurt(g, 40)
  h.a:update(2, true, false)
  h.a:observe(g)
  local died
  for _, e in ipairs(h.sent) do
    check(e)
    assert(e.data.qa_source == "smoke" and e.data.synthetic == true, "automation is synthetic")
    if e.name == "player_died" then
      died = e.data
    end
  end
  assert(died and died.hits_taken == 2 and died.level == "sector_1", "death at its place")
  h.a:quit("lost")
  assert(count(h, "run_abandoned") == 0, "a run that ended in death is not abandoned")
  local seen = {}
  for _, e in ipairs(story.sent) do
    seen[e.name] = true
  end
  for _, e in ipairs(h.sent) do
    seen[e.name] = true
  end
  -- run_abandoned is covered below.
  seen.run_abandoned = true
  for name in pairs(EXPECTED) do
    assert(seen[name], name .. " is exercised")
  end
end

-- 4. Leaving mid-run, a restart, and Loupe's modified flag.
do
  local h = harness()
  local g = sim.new(9, nil, 1, true)
  h.a:runStarted(g)
  h.a:update(3, true, false)
  h.revision = 2
  h.a:runStarted(sim.new(10))
  h.a:update(1.25, true, false)
  h.a:quit("paused")
  local abandoned = {}
  for _, e in ipairs(h.sent) do
    check(e)
    if e.name == "run_abandoned" then
      abandoned[#abandoned + 1] = e.data
    end
  end
  assert(#abandoned == 2, "restart and quit both abandon")
  assert(abandoned[1].screen == "restart" and abandoned[1].mode == "endless")
  assert(abandoned[1].modified == true, "modified once Loupe changed state")
  assert(abandoned[2].screen == "paused" and abandoned[2].sector_time_s == 1.3)
  assert(abandoned[1].run_id ~= abandoned[2].run_id, "a new run, a new id")
  assert(h.sent[#h.sent].name == "session_ended", "the session ends last")
end

-- 5. The web exit mailbox: kept current, cleared on quit and when collection stops.
do
  local h = harness({ mailbox = true, distribution = "web-pages" })
  h.a:sessionStarted({ art = "vector" })
  local list = json.decode(h.mailboxText)
  assert(#list == 1 and list[1].event == "session_ended", "no run, only the session end")
  h.a:runStarted(sim.new(3))
  list = json.decode(h.mailboxText)
  assert(#list == 2 and list[1].event == "run_abandoned" and list[2].event == "session_ended")
  assert(list[1].data.screen == "closed" and list[1].data.distribution == "web-pages")
  local ids = {}
  for _, entry in ipairs(list) do
    -- The bridge sends mailbox entries straight to the page's SDK, so the
    -- adapter supplies the rs_event_id the Lua SDK would have added.
    local id = entry.data.rs_event_id
    assert(type(id) == "string" and #id <= 64 and id:match("^[A-Za-z0-9_-]+$"), "id shape")
    ids[entry.event] = id
    entry.data.rs_event_id = nil
    check({ name = entry.event, data = entry.data })
  end
  assert(ids.run_abandoned ~= ids.session_ended, "one id per entry")
  h.a:update(6, true, false)
  local again = json.decode(h.mailboxText)
  assert(again[1].data.rs_event_id == ids.run_abandoned, "an entry keeps its id across rewrites")
  assert(again[2].data.rs_event_id == ids.session_ended)
  h.mailboxText = "stale"
  h.a:update(4.9, true, false)
  assert(h.mailboxText == "stale", "not rewritten every frame")
  h.a:update(0.2, true, false)
  assert(h.mailboxText ~= "stale", "refreshed with current times")
  h.enabled = false
  h.a:refreshMailbox()
  assert(h.mailboxText == nil, "a stop in collection removes the mailbox")
  h.enabled = true
  h.a:refreshMailbox()
  h.a:quit("flight")
  assert(h.mailboxText == nil, "a clean quit removes the mailbox")
end

-- 5b. Always on: every run is reported while the SDK collects, and a stop
-- in collection mid-run (the server's kill switch) stops sending at once.
do
  local h = harness({ mailbox = true })
  h.a:sessionStarted({ art = "vector" })
  local g = sim.new(42)
  h.a:runStarted(g)
  play(g)
  h.a:update(30, true, false)
  h.a:observe(g)
  local list = json.decode(h.mailboxText)
  assert(#list == 2 and list[1].event == "run_abandoned", "the run in progress is in the mailbox")
  assert(count(h, "run_started") == 1 and count(h, "sector_completed") == 1, "the run is reported")
  local sent = #h.sent
  h.enabled = false
  local cost = sim.cost(g, "power")
  if sim.buy(g, "power") then
    h.a:upgradePurchased(g, "power", cost)
  end
  h.a:quit("dock")
  assert(#h.sent == sent, "nothing is sent once the SDK stops collecting")
  for _, e in ipairs(h.sent) do
    check(e)
  end
end

-- 6. Automation labels, platform names and the injected config.
assert(analytics.qaSource({}, os.getenv) == "none" or os.getenv("RAVENSIGHT_PLAYTEST_TOKEN"))
assert(analytics.qaSource({ "--smoke", "120" }) == "smoke")
assert(analytics.qaSource({ "--playtest" }) == "playtest")
assert(analytics.qaSource({ "--title-capture", "x.png" }) == "capture")
assert(analytics.qaSource({ "--mcp" }) == "mcp")
assert(analytics.qaSource({ "--boss" }) == "debug")
assert(analytics.qaSource({ "--ravensight-playtest-token=abc" }) == "ravensight_playtest")
assert(analytics.qaSource({ "--ravensight-playtest-token=" }) == "none", "an empty token is none")
assert(analytics.qaSource({}, function()
  return "tok"
end) == "ravensight_playtest")
assert(analytics.platformName("OS X") == "macos" and analytics.platformName("Web") == "web")
assert(analytics.platformName("Free BSD") == "freebsd")
assert(analytics.usesMailbox("Web") == true, "the web build keeps the exit mailbox")
for _, os in ipairs({ "OS X", "Windows", "Linux", "Android", "iOS" }) do
  assert(analytics.usesMailbox(os) == false, "a native build never writes /tmp: " .. os)
end

local function loader(source)
  return function()
    if source == nil then
      return nil
    end
    return assert((loadstring or load)(source))
  end
end
assert(analytics.loadConfig(loader(nil)) == nil, "no config, no analytics")
assert(analytics.loadConfig(loader("error('x')")) == nil, "a broken config is ignored")
assert(analytics.loadConfig(loader("return 3")) == nil, "a config is a table")
assert(analytics.loadConfig(function()
  error("unreadable")
end) == nil)
local config = analytics.loadConfig(
  loader('return { ingestKey = "k", distribution = "web-itch", web = true, extra = 1 }')
)
assert(config.ingestKey == "k" and config.distribution == "web-itch" and config.web == true)
assert(config.extra == nil and config.apiUrl == nil, "only known fields are read")
config = analytics.loadConfig(loader("return {}"))
assert(config.ingestKey == "" and config.distribution == "unknown" and config.web == false)

-- 7. An unknown key is a programming error, caught here rather than shipped.
do
  local h = harness()
  local ok = pcall(function()
    h.a:send("session_started", { level = 3 })
  end)
  assert(not ok, "keys outside the allowlist are refused")
end

print("PASS: analytics contract, 12 events, collection gate, timers, modified, mailbox, config")
