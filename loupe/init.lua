-- loupe: a drop-in live inspector and editor for LÖVE games.
--
--   local loupe = require("loupe")
--   loupe.attach()   -- at the end of main.lua, after your love.* callbacks
local badge = require("loupe.panels.badge")
local remote = require("loupe.core.remote")
local clock = require("loupe.core.clock")
local edits = require("loupe.core.edits")
local geometry = require("loupe.core.geometry")
local hook = require("loupe.core.hook")
local inspector = require("loupe.panels.inspector")
local objects = require("loupe.panels.objects")
local overrides = require("loupe.core.overrides")
local panelLayout = require("loupe.panels.layout")
local picker = require("loupe.core.picker")
local reflect = require("loupe.core.reflect")
local registry = require("loupe.core.registry")
local reload = require("loupe.reload")
local render = require("loupe.ui.render_love")
local storage = require("loupe.storage")
local themes = require("loupe.ui.theme")
local toolbar = require("loupe.panels.toolbar")
local ui = require("loupe.ui")

local loupe = {
  _VERSION = "1.2.0",
}

local DEFAULT_KEYS = {
  toggle = "f1",
  pause = "p",
  step = ".",
  slower = "[",
  faster = "]",
  resetSpeed = "1",
}

-- Lives outside `state` so watch() works before attach() and in headless runs.
local watched = registry.new()

-- nil while detached.
local state

local function plural(n, one, many)
  return ("%d %s"):format(n, n == 1 and one or many)
end

local function setMessage(text, warning)
  state.message, state.messageIsWarning = text, warning == true
end

local function undo()
  state.edits:undo()
end

local function redo()
  state.edits:redo()
end

local function save()
  local entries = state.edits.overrides:entries()
  local ok, where = storage.write(overrides.render(entries))
  if ok then
    state.edits:markSaved()
    setMessage("saved " .. plural(#entries, "override", "overrides"))
    print("loupe: saved overrides to " .. where)
  else
    setMessage("save failed: " .. tostring(where), true)
  end
  return ok, where
end

local function loadSavedOverrides()
  local text = storage.read()
  if not text then
    return
  end
  local data, err = storage.parse(text)
  if not data then
    setMessage(("couldn't read %s: %s"):format(storage.FILE, err), true)
    return
  end
  local entries = overrides.parse(data)
  state.edits.overrides:load(entries)
  setMessage("loaded " .. plural(#entries, "saved override", "saved overrides"))
end

-- Writes overrides into each watched root the first time it's seen, and again
-- whenever a getter returns a new table (e.g. the game restarted).
local function applyOverrides()
  local skipped = 0
  for _, root in ipairs(watched:roots()) do
    if type(root.value) == "table" and state.appliedTo[root.name] ~= root.value then
      state.appliedTo[root.name] = root.value
      local entries = state.edits.overrides:entries()
      local _, missed = overrides.apply(entries, root.name, root.value)
      skipped = skipped + missed
    end
  end
  if skipped > 0 then
    local what = skipped == 1 and "saved override no longer matches"
      or "saved overrides no longer match"
    setMessage(("%d %s the game"):format(skipped, what), true)
  end
end

-- Checks for edited modules (ADR 0007). Uses the real dt so it keeps working
-- while the game is paused.
local function hotReload(dt)
  local failed, reloaded = nil, {}
  for _, result in ipairs(state.reloader:update(dt)) do
    if result.ok then
      reloaded[#reloaded + 1] = result.name
      print("loupe: reloaded " .. result.name)
    else
      local text = ("reload failed: %s: %s"):format(result.name, result.err)
      print("loupe: " .. text)
      failed = failed or text
    end
  end
  if failed then
    setMessage(failed, true)
    if not state.open then
      state.alert = failed
    end
  elseif #reloaded == 1 then
    setMessage("reloaded " .. reloaded[1])
  elseif #reloaded > 1 then
    setMessage("reloaded " .. plural(#reloaded, "module", "modules"))
  end
end

local reloadDt = 0
local function hotReloadFrame()
  hotReload(reloadDt)
end

-- A watched root's current value, so undo follows a getter's new table.
local function currentRoot(name)
  for _, root in ipairs(watched:roots()) do
    if root.name == name then
      return root.value
    end
  end
end

-- Copy and paste in loupe's fields use the system clipboard.
local function systemClipboard()
  local sys = love.system
  if not (sys and sys.getClipboardText and sys.setClipboardText) then
    return nil
  end
  return { get = sys.getClipboardText, set = sys.setClipboardText }
end

local function newUi()
  -- lineHeight per font role (body, small, title, mono): the theme has several.
  return ui.new({
    measure = render.measure,
    lineHeight = render.lineHeight,
    clipboard = systemClipboard(),
  })
end

local function traceback(err)
  return debug.traceback(tostring(err), 2)
end

-- The one error boundary. loupe's per-frame work runs user hooks (bounds,
-- toWorld, ...) and game metamethods (strict tables), any of which can throw;
-- a drop-in tool must never take the game down with it. Reports the error
-- once until the overlay is reopened, closes it, and the game carries on.
local function guard(fn)
  local ok, err = xpcall(fn, traceback)
  if ok then
    return true
  end
  if not state.errorReported then
    state.errorReported = true
    print("loupe: " .. err)
  end
  state.open = false
  state.alert = "Loupe hit an error (see console) - F1 to reopen"
  -- The error may have left UI state half-built (a window never ended).
  state.ui, state.inspector, state.picker = newUi(), inspector.new(), picker.new()
  state.scale = nil -- the new context needs the theme and fonts applied again
  return false
end

local function warnUnsaved(root, keys)
  local text = "can't save %s: it's reached through a key that isn't a string or number"
  setMessage(text:format(overrides.path(root, keys)), true)
end

-- Inspector and world edits go through here so they can be undone and saved.
local function editSelection(target, key, value, keys)
  local root = state.selection and state.selection.root
  local meta = { root = root, keys = keys, gesture = state.gesture }
  if not state.edits:set(target, key, value, meta) then
    warnUnsaved(root, keys)
  end
end

local function editPicked(entry, key, value)
  local keys = reflect.childKeys(entry.keys, key)
  local meta = { root = entry.root, keys = keys, gesture = state.gesture }
  if not state.edits:set(entry.value, key, value, meta) then
    warnUnsaved(entry.root, keys)
  end
end

local function typingIntoLoupe()
  return state.open and state.ui:wantsKeyboard()
end

local function pointerOverLoupe(x, y)
  return state.open and state.ui:wantsMouse(x, y)
end

local function shiftDown()
  local kb = love.keyboard
  return kb ~= nil and kb.isDown("lshift", "rshift")
end

-- Returns true when loupe used the key, so the game shouldn't see it.
local function handleKey(key)
  local keys, c = state.keys, state.clock
  if key == keys.toggle then
    state.open = not state.open
    if state.open then
      state.alert = nil -- seen
      state.errorReported = nil
    end
    return true
  end
  if not state.open then
    return false
  end

  -- Checked before a focused field gets the key, so they work while typing.
  -- Saving doesn't commit the field: it saves what's been applied so far.
  local kb = love.keyboard
  local ctrl = kb and kb.isDown("lctrl", "rctrl", "lgui", "rgui")
  if ctrl then
    if key == "y" or (key == "z" and kb.isDown("lshift", "rshift")) then
      redo()
      return true
    elseif key == "z" then
      undo()
      return true
    elseif key == "s" then
      save()
      return true
    end
  end
  -- Ctrl/Cmd+A, C, X and V go to the field with the rest of the typing.
  if typingIntoLoupe() then
    state.input:keypressed(key, { shift = shiftDown(), ctrl = ctrl })
    return true
  end
  if ctrl then
    return false
  end

  if key == keys.pause then
    c:togglePause()
  elseif key == keys.step then
    c:step()
  elseif key == keys.slower then
    c:slower()
  elseif key == keys.faster then
    c:faster()
  elseif key == keys.resetSpeed then
    c:resetScale()
  else
    return false
  end
  return true
end

-- The UI scale: attach({ uiScale = n }), or picked from the window height.
-- LÖVE's units are already DPI-independent (a Retina window reports points,
-- and fonts are rasterized at the DPI scale), so only large pixel-unit
-- windows, such as 4K on Windows or Linux, need a bigger UI.
local function uiScale(screenHeight)
  if state.uiScale then
    return state.uiScale
  end
  return math.max(1, math.floor(screenHeight / 1080 * 4 + 0.5) / 4)
end

local function hasGlyph(font, glyph)
  return font.hasGlyphs ~= nil and font:hasGlyphs(glyph)
end

-- Rebuilds the theme and fonts when the UI scale changes.
local function syncTheme(screenHeight)
  local scale = uiScale(screenHeight)
  if scale == state.scale then
    return
  end
  state.scale = scale
  local theme = themes.build(state.themeOverrides, scale)
  render.configure(theme)
  local c = state.ui
  c:setMetrics(render.measure, render.lineHeight)
  c:setTheme(theme)
  -- LÖVE's default font (used when loupe/fonts is missing) has no "…".
  local font = render.font("body")
  c.ellipsis = hasGlyph(font, "…") and "…" or ".."
  -- Newlines and tabs in strings show as arrows when both the body and the
  -- value font have them, and as "\n" and "\t" otherwise. (The bundled
  -- subsets lack "↵", and the mono one lacks "→".)
  local mono = render.font("mono")
  local function glyph(g)
    return hasGlyph(font, g) and hasGlyph(mono, g) and g or nil
  end
  c.glyphs = { newline = glyph("↵"), tab = glyph("→") }
end

-- Drag handles between the sidebar and the game, and between Objects and
-- Inspector. Positions persist in state.split (see panels/layout.lua).
local function dragSplitters(c, rects)
  local s = rects.sidebarSplitter
  local _, held, x = c:splitter("loupe.split.sidebar", s.x, s.y, s.w, s.h, "x")
  if held then
    state.split.sidebar = panelLayout.sidebarFromDrag(x, c.theme)
  end
  s = rects.sectionSplitter
  local _, heldY, y = c:splitter("loupe.split.sections", s.x, s.y, s.w, s.h, "y")
  if heldY then
    state.split.objects = panelLayout.objectsFromDrag(y, rects)
  end
end

-- A resize cursor over splitters. Only set when it changes.
local function updateCursor(c)
  local mouse = love.mouse
  if not (mouse and mouse.setCursor and mouse.getSystemCursor) then
    return
  end
  local want
  local hot = c and (c.active or c.hot)
  if hot == "loupe.split.sidebar" then
    want = "sizewe"
  elseif hot == "loupe.split.sections" then
    want = "sizens"
  end
  if want ~= state.cursor then
    state.cursor = want
    mouse.setCursor(want and mouse.getSystemCursor(want) or nil)
  end
end

-- Hover, select and drag in the game world. Returns the outline commands.
local function pickInWorld(c, roots)
  local input = c.input
  local free = not c:wantsMouse(input.x, input.y)
  local list = geometry.collect(roots, state.geometry)
  local result = state.picker:frame(input, free, list, state.view, editPicked)
  if result.picked then
    local p = result.picked
    -- root and keys matter: without them, Inspector edits can't be saved.
    state.selection = { value = p.value, path = p.path, root = p.root, keys = p.keys }
  end

  local selectedBox
  if state.selection then
    local x, y, w, h = geometry.bounds(state.selection.value, state.geometry)
    if x then
      local path = c:oneLine(state.selection.path)
      selectedBox = { x = x, y = y, w = w, h = h, path = path }
    end
  end
  local style =
    { colors = c.theme.colors, measure = render.measure, lineHeight = render.lineHeight("small") }
  return picker.highlight(result.hover, selectedBox, state.view, style, state.layout.free)
end

-- A selection is stale once its root no longer leads to it by its keys (a
-- destroyed rock, a restarted game). The inspector says so.
local function markStale(selection, roots)
  if not (selection and selection.root and selection.keys) then
    return
  end
  local rootValue
  for _, root in ipairs(roots) do
    if root.name == selection.root then
      rootValue = root.value
    end
  end
  selection.stale = reflect.resolve(rootValue, selection.keys) ~= selection.value
end

-- Holding Backspace or an arrow key should repeat while editing a loupe field,
-- without changing the game's own key-repeat setting the rest of the time.
local function keyRepeatWhileTyping(typing)
  local kb = love.keyboard
  if not (kb and kb.setKeyRepeat) then
    return
  end
  if typing and state.gameKeyRepeat == nil then
    state.gameKeyRepeat = kb.hasKeyRepeat()
    kb.setKeyRepeat(true)
  elseif not typing and state.gameKeyRepeat ~= nil then
    kb.setKeyRepeat(state.gameKeyRepeat)
    state.gameKeyRepeat = nil
  end
end

local function drawOverlay()
  local width, height = love.graphics.getWidth(), love.graphics.getHeight()
  syncTheme(height)
  local c = state.ui
  if state.open then
    local roots = watched:roots()
    local tools = state.tools
    tools.dirty = state.edits:dirty()
    tools.canUndo = state.edits.history:canUndo()
    tools.canRedo = state.edits.history:canRedo()
    tools.status = state.message
    tools.statusColor = state.messageIsWarning and c.theme.colors.warning or nil
    -- Docked layout, recomputed every frame from the screen (ADR 0008).
    local barHeight = toolbar.height(c, width, state.clock, tools)
    local rects = panelLayout.compute(width, height, c.theme, state.split, barHeight)
    state.layout = rects

    local input = state.input:frame()
    input.shift = shiftDown()
    c:beginFrame(input, width, height)
    -- World outlines go first so loupe's panels draw over them.
    local commands = tools.picking and pickInWorld(c, roots) or {}
    local picked = objects.build(c, roots, state.selection, rects.objects)
    if picked then
      state.selection = picked
    end
    markStale(state.selection, roots)
    state.inspector:build(c, state.selection, rects.inspector, editSelection)
    -- The bar goes last so its "?" popover draws over the sidebar.
    local action = toolbar.build(c, rects.bar, state.clock, state.keys, tools)
    if action == "undo" then
      undo()
    elseif action == "redo" then
      redo()
    elseif action == "save" then
      save()
    end
    dragSplitters(c, rects)
    for _, cmd in ipairs(c:endFrame()) do
      commands[#commands + 1] = cmd
    end
    render.draw(commands)
    updateCursor(c)
    keyRepeatWhileTyping(c:wantsKeyboard())
  else
    updateCursor(nil)
    keyRepeatWhileTyping(false)
    if state.alert or state.clock.paused or state.clock.scale ~= 1 then
      local cmds =
        badge.build(state.clock, width, state.alert, c.theme, render.measure, render.lineHeight)
      render.draw(cmds)
    end
  end
end

local wrappers = {
  update = function(original, dt)
    if state.bridge then
      local ok, err = pcall(state.bridge.poll, state.bridge)
      if not ok then
        setMessage("MCP: " .. tostring(err), true)
      end
    end
    state.swallowText = false -- a press's text arrives before the next update
    if state.reloader then
      reloadDt = dt
      if not guard(hotReloadFrame) then
        state.reloader = nil -- off, rather than failing every half second
      end
    end
    guard(applyOverrides)
    local gameDt = state.clock:advance(dt)
    if gameDt and original then
      return original(gameDt)
    end
  end,

  draw = function(original)
    if original then
      original()
    end
    guard(drawOverlay)
  end,

  -- A press loupe used keeps its release (and, for hotkeys, its text) from
  -- the game too, so the game never sees half a key press. Releases are
  -- matched by key or scancode; the latest press of a key decides.
  keypressed = function(original, key, scancode, ...)
    local typing = typingIntoLoupe()
    local used = handleKey(key)
    state.swallowText = used and not typing
    state.usedKeys[key] = used or nil
    if scancode ~= nil then
      state.usedScancodes[scancode] = used or nil
    end
    if used then
      return
    end
    if original then
      return original(key, scancode, ...)
    end
  end,

  keyreleased = function(original, key, scancode, ...)
    local used = state.usedKeys[key] or (scancode ~= nil and state.usedScancodes[scancode])
    state.usedKeys[key] = nil
    if scancode ~= nil then
      state.usedScancodes[scancode] = nil
    end
    if used then
      return
    end
    if original then
      return original(key, scancode, ...)
    end
  end,

  textinput = function(original, text)
    if typingIntoLoupe() then
      state.input:textinput(text)
      return
    end
    if state.swallowText then
      state.swallowText = false
      return
    end
    if original then
      return original(text)
    end
  end,

  mousemoved = function(original, x, y, ...)
    state.input:mousemoved(x, y)
    if original then
      return original(x, y, ...)
    end
  end,

  mousepressed = function(original, x, y, button, ...)
    if state.open then
      state.gesture = state.gesture + 1
      state.input:mousepressed(x, y, button)
      if state.tools.picking or state.ui:wantsMouse(x, y) then
        state.captured[button] = true
        return
      end
    end
    if original then
      return original(x, y, button, ...)
    end
  end,

  -- Releases always reach the UI so a drag can never get stuck, and a
  -- release that ends a press loupe captured never reaches the game.
  mousereleased = function(original, x, y, button, ...)
    state.input:mousereleased(x, y, button)
    if state.captured[button] then
      state.captured[button] = nil
      return
    end
    if original then
      return original(x, y, button, ...)
    end
  end,

  wheelmoved = function(original, dx, dy, ...)
    if pointerOverLoupe(state.input.x, state.input.y) then
      state.input:wheelmoved(dx, dy)
      return
    end
    if original then
      return original(dx, dy, ...)
    end
  end,
}

local function identity(x, y)
  return x, y
end

-- opts.open: start with the overlay visible.
-- opts.keys: override any of DEFAULT_KEYS (LÖVE key names).
-- opts.stepSize: seconds per single step (default 1/60).
-- opts.pick: start with world picking on (default true). While on and the
--   overlay is open, clicks in the world select/drag objects, not the game.
-- opts.toWorld(sx, sy) / opts.toScreen(wx, wy): your camera/letterbox mapping.
-- opts.bounds(obj) -> x, y, w, h: custom object boxes; return nil to fall back.
-- opts.center: x, y are box centers (default: top-left).
-- opts.pickable(obj): return false to make an object unclickable.
-- opts.hotReload: reload edited Lua modules in place (default: on when the
--   game runs unfused from a folder).
-- opts.reloadIgnore: Lua patterns for module names never to reload.
-- opts.theme: a partial theme merged over loupe.ui.theme (colors, sizes, fonts).
-- opts.uiScale: UI scale (default: 1, or larger for big pixel-unit windows).
function loupe.attach(opts)
  if state then
    return loupe
  end
  -- Headless runs (no window) have nothing to inspect.
  if not (love and love.graphics) then
    return loupe
  end

  opts = opts or {}
  local keys = {}
  for action, default in pairs(DEFAULT_KEYS) do
    keys[action] = opts.keys and opts.keys[action] or default
  end

  state = {
    open = opts.open == true,
    keys = keys,
    clock = clock.new({ stepSize = opts.stepSize }),
    ui = newUi(),
    input = ui.newInput(),
    captured = {}, -- mouse buttons whose press loupe kept from the game
    usedKeys = {}, -- keys whose press loupe used: their release is loupe's too
    usedScancodes = {},
    swallowText = false, -- the next text input belongs to a hotkey loupe used
    inspector = inspector.new(),
    selection = nil, -- { value, path } shown in the inspector
    picker = picker.new(),
    tools = { picking = opts.pick ~= false },
    view = { toWorld = opts.toWorld or identity, toScreen = opts.toScreen or identity },
    geometry = { bounds = opts.bounds, center = opts.center, pickable = opts.pickable },
    edits = edits.new({ resolveRoot = currentRoot }),
    gesture = 0, -- bumps on every press; edits in one gesture undo together
    appliedTo = {}, -- root name -> the table overrides were last applied to
    themeOverrides = opts.theme,
    uiScale = opts.uiScale,
    split = {}, -- splitter positions (panels/layout.lua)
  }
  loadSavedOverrides()
  local hotReloadOn = opts.hotReload
  if hotReloadOn == nil then
    hotReloadOn = storage.sourceFolder() ~= nil
  end
  if hotReloadOn then
    state.reloader = reload.new({ ignore = opts.reloadIgnore })
  end
  -- After this, mouse events keep the position current. Polling the mouse
  -- each frame instead would misplace clicks made while the pointer moves.
  if love.mouse then
    state.input:setPosition(love.mouse.getPosition())
  end
  if opts.mcp then
    local api = remote.new({
      roots = function()
        return watched:roots()
      end,
      edits = state.edits,
      clock = state.clock,
      setOpen = function(value)
        loupe.setOpen(value)
      end,
      save = save,
    })
    state.bridge = require("loupe.bridge").new(api)
  end
  state.hook = hook.install(love, wrappers)
  return loupe
end

-- Shows a table in the Objects window. `target` may be a function returning
-- the table, which keeps working when the game replaces it:
--   loupe.watch(function() return game end, "game")
function loupe.watch(target, name)
  watched:watch(target, name)
  return target
end

function loupe.unwatch(name)
  watched:unwatch(name)
end

function loupe.detach()
  if state then
    if state.bridge then
      state.bridge:close()
    end
    keyRepeatWhileTyping(false)
    state.hook.remove()
    state = nil
  end
end

function loupe.bridgeDirectory()
  return state and state.bridge and state.bridge.directory
end

function loupe.isAttached()
  return state ~= nil
end

function loupe.isOpen()
  return state ~= nil and state.open
end

function loupe.setOpen(open)
  if state then
    state.open = open
  end
end

-- Internal, for loupe's own specs and tools: the UI context (nil while
-- detached). Its rectOf(id) finds where a widget was drawn last frame.
function loupe._debugUi()
  return state and state.ui
end

return loupe
