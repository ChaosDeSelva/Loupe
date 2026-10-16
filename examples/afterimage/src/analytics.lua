-- Afterimage's gameplay analytics: a small, versioned set of events sent
-- through the Ravensight SDK, and nothing else. Pure Lua: the SDK, the clock,
-- the random source and Loupe's edit counter are passed in, so the contract
-- below is tested without LÖVE (tests/analytics_test.lua).
--
-- Off unless the player turns it on (the SDK runs with consent = "opt_in"),
-- and inert in any build without an injected config: a clone of this
-- repository sends nothing. See README.md, "Analytics".
--
-- Contract, schema_version 1. Every event carries the COMMON keys; the events
-- inside a run also carry the RUN keys. `level` is only ever the place,
-- "sector_N", never the player's rank (that is `rank`). Times ending in `_s`
-- count play time only: a paused game, the Loupe clock stopped, the title and
-- end screens do not count. `wall_time_s` is real time and appears only on
-- session_ended.
--
-- A run is observed only if analytics was on when it started and stayed on.
-- A yes in the middle of a run leaves that run unobserved: its run-scoped
-- events are never sent, and they resume at the next run_started, so no
-- event ever reports play from before the player agreed.
local M = {}

M.SCHEMA_VERSION = 1

local COMMON = {
  "schema_version",
  "build",
  "platform",
  "distribution",
  "qa_source",
  "synthetic",
  "rs_kind",
}
local RUN = { "run_id", "mode", "modified" }

-- name -> { kind = rs_kind, run = carries RUN keys, keys = its own keys }
M.EVENTS = {
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

-- The full set of keys an event may carry, as a lookup table.
function M.allowedKeys(name)
  local spec = M.EVENTS[name]
  if not spec then
    return nil
  end
  local allowed = {}
  for _, list in ipairs({ COMMON, spec.run and RUN or {}, spec.keys }) do
    for _, key in ipairs(list) do
      allowed[key] = true
    end
  end
  return allowed
end

-- Which automation started this process, from its command line and
-- environment. Anything but "none" is labelled synthetic.
function M.qaSource(args, getenv)
  local flags = {}
  local tokenArg = false
  for _, value in ipairs(args or {}) do
    flags[value] = true
    if type(value) == "string" and value:match("^%-%-ravensight%-playtest%-token=.") then
      tokenArg = true
    end
  end
  local token = getenv and getenv("RAVENSIGHT_PLAYTEST_TOKEN")
  if tokenArg or (token and token ~= "") then
    return "ravensight_playtest"
  elseif flags["--playtest"] then
    return "playtest"
  elseif flags["--smoke"] then
    return "smoke"
  elseif flags["--capture"] or flags["--title-capture"] then
    return "capture"
  elseif flags["--mcp"] then
    return "mcp"
  elseif flags["--flight"] or flags["--boss"] then
    return "debug"
  end
  return "none"
end

-- The LÖVE OS name as a short lowercase label.
function M.platformName(os)
  local known = { ["OS X"] = "macos", Windows = "windows", Linux = "linux", Web = "web" }
  if known[os] then
    return known[os]
  end
  return (tostring(os or "unknown"):lower():gsub("[^a-z0-9]", ""))
end

-- Whether to keep the web exit mailbox: only in a love.js build, where the
-- page's bridge reads it. A native game has love.quit and no bridge, and
-- must not touch /tmp.
function M.usesMailbox(os)
  return os == "Web"
end

-- The ANALYTICS switch shows and flips the player's own choice, read from
-- where the SDK saves it, never whether events are flowing: after the
-- server's kill switch or a refused key the SDK stops sending, but the
-- player's yes still stands and must still be withdrawable.
--   saved()  true when the player's yes is on disk
--   set(on)  the SDK's setTrackingEnabled
function M.consentSwitch(deps)
  local switch = {}
  function switch.isOn()
    return deps.saved() == true
  end
  function switch.toggle()
    local on = not switch.isOn()
    deps.set(on)
    return on
  end
  return switch
end

-- Reads the injected build config: a Lua file returning a table, written only
-- by the release tools. Returns nil when there is none or it is unusable.
-- loader(name) returns a chunk or nil (love.filesystem.load in the game).
function M.loadConfig(loader, name)
  local ok, chunk = pcall(loader, name or "analytics.config.lua")
  if not ok or type(chunk) ~= "function" then
    return nil
  end
  local ran, config = pcall(chunk)
  if not ran or type(config) ~= "table" then
    return nil
  end
  local out = {
    ingestKey = type(config.ingestKey) == "string" and config.ingestKey or "",
    apiUrl = type(config.apiUrl) == "string" and config.apiUrl or nil,
    distribution = type(config.distribution) == "string" and config.distribution or "unknown",
    web = config.web == true,
  }
  return out
end

local function round(n, places)
  local scale = 10 ^ (places or 1)
  return math.floor(n * scale + 0.5) / scale
end

local function hex(random, count)
  local out = {}
  for i = 1, count do
    out[i] = string.format("%x", random(0, 15))
  end
  return table.concat(out)
end

--- deps:
---   sdk            { track(name, data), enabled() }, normally the ravensight module
---   editRevision() Loupe's edit counter (0 until Loupe changes game state)
---   random(a, b)   integer source, for run ids
---   clock()        seconds, for wall_time_s
---   build, platform, distribution, qaSource
---   mailbox(text)  optional, the web exit mailbox writer; text nil removes it
---   encode(value)  JSON encoder, required with mailbox
---   mailboxEvery   seconds of play between mailbox refreshes, default 5
function M.new(deps)
  local self = {
    deps = deps,
    run = nil,
    sessionStart = deps.clock(),
    -- Mailbox entries carry an rs_event_id in the server's shape
    -- (^[A-Za-z0-9_-]{1,64}$): this launch's nonce plus a counter, fixed
    -- per entry, so a resent entry is recognised as the same event.
    nonce = hex(deps.random, 8),
    idCounter = 0,
    opens = 0,
    runsStarted = 0,
    runsCompleted = 0,
    sectorsCompleted = 0,
    sinceMailbox = 0,
    mailboxWritten = false,
  }
  setmetatable(self, { __index = M })
  self.endId = self:nextId()
  return self
end

function M:nextId()
  self.idCounter = self.idCounter + 1
  return "x" .. self.nonce .. "-" .. self.idCounter
end

-- The run in progress, when it is being reported; nil otherwise.
function M:observedRun()
  local run = self.run
  return run and run.observed and run or nil
end

function M:active()
  return self.deps.sdk.enabled() == true
end

function M:common(kind)
  local qa = self.deps.qaSource or "none"
  return {
    schema_version = M.SCHEMA_VERSION,
    build = self.deps.build,
    platform = self.deps.platform,
    distribution = self.deps.distribution,
    qa_source = qa,
    synthetic = qa ~= "none",
    rs_kind = kind,
  }
end

-- The event's full property table, built from the contract. Keys outside
-- the allowlist are a programming error here, so they fail loudly in tests.
function M:payload(name, data)
  local spec = assert(M.EVENTS[name], "unknown analytics event " .. tostring(name))
  local out = self:common(spec.kind)
  if spec.run then
    local run = assert(self.run, name .. " needs an active run")
    out.run_id = run.id
    out.mode = run.mode
    out.modified = self.deps.editRevision() > 0
  end
  local allowed = M.allowedKeys(name)
  for key, value in pairs(data or {}) do
    assert(allowed[key], name .. " does not allow the key " .. key)
    out[key] = value
  end
  return out
end

function M:send(name, data)
  if not self:active() then
    return
  end
  if M.EVENTS[name].run and not self:observedRun() then
    return
  end
  self.deps.sdk.track(name, self:payload(name, data))
end

-- Writes the events the page should send if the tab closes now. Web only.
function M:refreshMailbox()
  local write = self.deps.mailbox
  if not write then
    return
  end
  if not self:active() then
    if self.mailboxWritten then
      write(nil)
      self.mailboxWritten = false
    end
    return
  end
  local list = {}
  local run = self:observedRun()
  if run then
    local data = self:abandonData("closed")
    data.rs_event_id = run.exitId
    list[#list + 1] = { event = "run_abandoned", data = data }
  end
  local ended = self:endData()
  ended.rs_event_id = self.endId
  list[#list + 1] = { event = "session_ended", data = ended }
  write(self.deps.encode(list))
  self.mailboxWritten = true
  self.sinceMailbox = 0
end

--- Call once per frame with the game's dt. `flying` is true while a sector
--- is being played and not paused, `docked` while the dock screen is open.
function M:update(dt, flying, docked)
  local run = self.run
  if run and run.observed and not self:active() then
    run.observed = false -- a gap in consent: the rest of this run is not reported
  end
  if run and (flying or docked) then
    run.time = run.time + dt
    if flying then
      run.sectorTime = run.sectorTime + dt
    end
  end
  if self.deps.mailbox then
    self.sinceMailbox = self.sinceMailbox + dt
    if self.sinceMailbox >= (self.deps.mailboxEvery or 5) then
      self:refreshMailbox()
    end
  end
end

--- Once per launch, at start or at the player's first yes, whichever comes
--- first while collecting.
function M:sessionStarted(settings)
  if self.sessionSent or not self:active() then
    self:refreshMailbox()
    return
  end
  self.sessionSent = true
  self:send("session_started", {
    art_style = settings.art,
    reduced_motion = settings.reduced_motion == true,
  })
  self:refreshMailbox()
end

--- A new run, story or endless; `game` is its first sector.
function M:runStarted(game)
  if self:observedRun() and self:active() then
    self.deps.sdk.track("run_abandoned", self:abandonData("restart"))
  end
  self.run = {
    observed = self:active(),
    exitId = self:nextId(),
    id = hex(self.deps.random, 12),
    mode = game.endless and "endless" or "story",
    time = 0,
    sectorTime = 0,
    cleared = 0,
    game = nil,
  }
  if self.run.observed then
    self.runsStarted = self.runsStarted + 1
  end
  self:send("run_started", {})
  self:sectorStarted(game)
end

function M:sectorStarted(game)
  local run = self.run
  if not run then
    return
  end
  run.game = game
  run.sectorTime = 0
  run.resolved = false
  self:send("sector_started", {
    level = "sector_" .. game.sector,
    sector = game.sector,
    cycle = game.cycle,
    hull = math.ceil(game.player.hp),
    run_time_s = round(run.time),
  })
  self:refreshMailbox()
end

function M:pickups(game)
  local c = game.collected or {}
  local salvage, turbo, prism, patch = c.salvage or 0, c.turbo or 0, c.split or 0, c.hull or 0
  local total = salvage + turbo + prism + patch
  if total > 0 then
    self:send("pickup_collected", {
      sector = game.sector,
      salvage = salvage,
      turbo = turbo,
      prism = prism,
      hull_patch = patch,
      total = total,
    })
  end
end

local function runKills(game)
  return (game.totalKills or 0) + game.kills
end

--- Watches the sector for its end: docked, won or lost. Call after each
--- simulation step. Each sector resolves once.
function M:observe(game)
  local run = self.run
  if not run or run.game ~= game or run.resolved then
    return
  end
  local state = game.state
  if state ~= "dock" and state ~= "victory" and state ~= "lost" then
    return
  end
  run.resolved = true
  self:pickups(game)
  if state == "lost" then
    self:send("player_died", {
      level = "sector_" .. game.sector,
      sector = game.sector,
      sector_time_s = round(run.sectorTime),
      run_time_s = round(run.time),
      kills = game.kills,
      hits_taken = game.hurts or 0,
      rank = game.level,
    })
    self.run = nil
    self:refreshMailbox()
    return
  end
  run.cleared = run.cleared + 1
  if run.observed then
    self.sectorsCompleted = self.sectorsCompleted + 1
  end
  self:send("sector_completed", {
    level = "sector_" .. game.sector,
    sector = game.sector,
    sector_time_s = round(run.sectorTime),
    run_time_s = round(run.time),
    kills = game.kills,
    hits_taken = game.hurts or 0,
    hull = math.ceil(game.player.hp),
    salvage = game.gems,
    rank = game.level,
    boss_defeated = game.bossDefeated == true,
  })
  if state == "victory" then
    if run.observed then
      self.runsCompleted = self.runsCompleted + 1
    end
    self:send("run_completed", {
      sectors_cleared = run.cleared,
      run_time_s = round(run.time),
      kills = runKills(game),
      rank = game.level,
      salvage = game.gems,
    })
    self.run = nil
  end
  self:refreshMailbox()
end

--- After a successful purchase at the dock. Repairs are not upgrades.
function M:upgradePurchased(game, kind, cost)
  if not self.run or kind == "repair" then
    return
  end
  self:send("upgrade_purchased", {
    sector = game.sector,
    upgrade = kind,
    upgrade_rank = game.upgrades[kind],
    cost = cost,
    salvage_left = game.gems,
  })
end

--- The player switched the art style; `via` is "key" or "button".
function M:artStyleChanged(illustrated, via)
  self:send(
    "art_style_changed",
    { art_style = illustrated and "illustrated" or "vector", via = via }
  )
end

--- Call each frame with whether the Loupe inspector is open; the event fires
--- when it opens.
function M:inspector(open, screen)
  if open and not self.inspectorWasOpen then
    self.opens = self.opens + 1
    self:send("inspector_opened", { screen = screen, opens = self.opens })
  end
  self.inspectorWasOpen = open
end

function M:abandonData(screen)
  local run = self.run
  local game = run.game
  return self:payload("run_abandoned", {
    sector = game and game.sector or 0,
    sector_time_s = round(run.sectorTime),
    run_time_s = round(run.time),
    sectors_cleared = run.cleared,
    screen = screen,
  })
end

function M:endData()
  return self:payload("session_ended", {
    wall_time_s = round(self.deps.clock() - self.sessionStart),
    runs_started = self.runsStarted,
    runs_completed = self.runsCompleted,
    sectors_completed = self.sectorsCompleted,
    inspector_opens = self.opens,
  })
end

--- From love.quit: an unfinished run is abandoned, then the session ends.
--- `screen` names where the player left from ("flight", "paused", "dock").
function M:quit(screen)
  if self:active() then
    if self:observedRun() then
      self.deps.sdk.track("run_abandoned", self:abandonData(screen))
    end
    self.deps.sdk.track("session_ended", self:endData())
  end
  self.run = nil
  if self.mailboxWritten and self.deps.mailbox then
    self.deps.mailbox(nil)
    self.mailboxWritten = false
  end
end

return M
