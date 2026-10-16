# loupe API reference (1.1.1)

Everything here is the public surface of `require("loupe")` and `require("loupe.ui")`. Anything
else under `loupe/` is internal and may change without notice.

- [Setup](#setup)
- [`loupe.attach(opts)`](#loupeattachopts)
- [Other functions](#other-functions)
- [Watching tables: `watch` and `unwatch`](#watching-tables-watch-and-unwatch)
- [Keys](#keys)
- [Input routing: what the game receives](#input-routing-what-the-game-receives)
- [World picking](#world-picking)
- [Undo, redo and saved overrides](#undo-redo-and-saved-overrides)
- [Hot reload](#hot-reload)
- [When loupe itself hits an error](#when-loupe-itself-hits-an-error)
- [Headless runs](#headless-runs)
- [The UI toolkit: `loupe.ui`](#the-ui-toolkit-loupeui)

## Setup

Copy the `loupe/` folder next to your `main.lua`, then add to the **end** of `main.lua`:

```lua
local loupe = require("loupe")

-- ... your love.load / love.update / love.draw / input callbacks ...

loupe.watch(function() return game end, "game")
loupe.attach()
```

`attach` goes last so it wraps the callbacks you defined above it. Callbacks you assign later
(for example `love.update = menu.update` when switching scenes) stay wrapped too: loupe serves
`love`'s callbacks through a metatable rather than replacing the fields once (ADR 0004).

Code that chains a callback after `attach` also works. `hump.gamestate.registerEvents()` does
this from `love.load`, and so does any hand-written wrapper:

```lua
local old = love.update -- after attach, this is loupe's wrapper
love.update = function(dt)
  old(dt)
  -- ...
end
```

loupe remembers what each assigned function replaced, so the call back through `old` reaches
the previous callback instead of re-entering loupe. Chains of any depth work, and keep working
after `detach`. Two limits: what a function replaced is fixed the first time it's assigned, and
a custom `love.run` that catches an error thrown by a game callback and keeps going may see the
chain misbehave afterwards (ADR 0004).

## `loupe.attach(opts)`

Installs loupe around the game's `love` callbacks and returns the `loupe` module. Calling it again
while attached does nothing. `opts` is optional; every field is optional.

| Option | Type | Default | Meaning |
|---|---|---|---|
| `open` | boolean | `false` | Start with the overlay visible. |
| `theme` | table | `nil` | A partial theme merged over a copy of `loupe.ui.theme` (colors such as `accent`, `surface`, `text`; font roles; spacing). The default theme module is never modified. |
| `uiScale` | number | automatic | Layout scale. By default 1, growing in 0.25 steps on very tall windows (2 at 2160 points). Fonts follow the screen's DPI separately, so text stays crisp. |
| `keys` | table | see [Keys](#keys) | Override any of the default key bindings, by action name. Values are LÖVE key names. Actions you leave out keep their default. |
| `stepSize` | number | `1/60` | Seconds of game time per single step. Steps ignore the speed setting. |
| `pick` | boolean | `true` | Start with world picking on. While picking is on and the overlay is open, every click goes to loupe (see [Input routing](#input-routing-what-the-game-receives)). The toolbar's **Pick** button toggles it at runtime. |
| `toWorld` | `function(sx, sy) -> wx, wy` | identity | Converts a screen point to your world coordinates (undo your camera, scale and letterbox). |
| `toScreen` | `function(wx, wy) -> sx, sy` | identity | The inverse of `toWorld`. Used to draw outlines in the right place. |
| `bounds` | `function(obj) -> x, y, w, h` | none | Custom world-space box for an object. Called for **every** table under the watched roots, so it must return `nil` for tables it doesn't recognize; loupe then falls back to its own rules. |
| `center` | boolean | `false` | `x, y` are the center of `w`/`h` boxes rather than the top-left. Radius-based objects are always centered. |
| `pickable` | `function(obj) -> boolean` | none | Return `false` to make an object unclickable (for example the camera). Its child tables are still searched. |
| `hotReload` | boolean | `true` when the game runs unfused from a folder, `false` when fused or packaged | Re-run changed modules and patch them into the running game. See [Hot reload](#hot-reload). |
| `reloadIgnore` | list of strings | `{}` | Lua patterns matched against module names (`"src.ship"`). Matching modules are never reloaded. |

Example with every picking option, based on `examples/platformer`:

```lua
loupe.attach({
  toWorld = view.toWorld,     -- screen -> world through the letterbox and camera
  toScreen = view.toScreen,   -- world -> screen
  pickable = function(obj)
    return not (game and obj == game.camera)
  end,
})
```

`attach` reads saved overrides (see below) and polls the mouse position once. It fails with an
error if something has already set a metatable on the `love` table, rather than guessing how to
chain with it.

## Other functions

| Function | Returns | Notes |
|---|---|---|
| `loupe.detach()` | nothing | Removes loupe and puts the game's current callbacks back as plain fields on `love`. Does nothing when not attached. |
| `loupe.isAttached()` | boolean | `false` before `attach`, after `detach`, and in headless runs. |
| `loupe.isOpen()` | boolean | Whether the overlay is visible. `false` when not attached. |
| `loupe.setOpen(open)` | nothing | Shows or hides the overlay. Ignored when not attached; call it from `love.load` or later, after `attach` has run. |
| `loupe.watch(target, name)` | `target` | See below. |
| `loupe.unwatch(name)` | nothing | Stops showing the root called `name`. Unknown names are ignored. |
| `loupe._VERSION` | string | `"major.minor.patch"`. |

## Watching tables: `watch` and `unwatch`

```lua
loupe.watch(game, "game")                          -- a table
loupe.watch(function() return game end, "game")   -- a getter (recommended)
loupe.watch(rocks.defs, "rockSizes")
```

- `name` is required and must be a string. It labels the root in the Objects window and keys
  saved overrides, so keep it stable.
- `target` must be a table or a function returning one. A getter is called every frame, so a
  game that replaces its state on restart (`game = newGame()`) stays watched. A getter that
  throws is shown as an error in the Objects window instead of crashing the game's draw.
- Watching a name that's already watched replaces its target.
- `watch` and `unwatch` work before `attach` and in headless runs.

The Objects window lists each root and its child tables (up to 200 children per node, with
cycles marked). Tables with no child tables have no expand arrow; click anywhere on their row to
select them. Selecting one shows it in the Inspector, which edits numbers (drag, or click to
type), booleans, strings, `{r, g, b[, a]}` colors with channels in 0..1, and nested tables
inline (up to 200 fields). Fields are read with `pairs`, so values inherited through `__index`
aren't shown.

If the selected table stops being where it was selected from (a destroyed rock, a restarted
game), the Inspector keeps showing it with a dim "(no longer in the game)" note. Select again to
pick up the current one.

Text fields (strings, and numbers you click to type) support Left/Right, Home/End, Backspace and
Delete at the cursor, a selection (Shift with Left/Right/Home/End, Ctrl/Cmd+A) and the system
clipboard (Ctrl/Cmd+C, X, V), all UTF-8 safe. Enter or clicking elsewhere commits; Escape
cancels. While a loupe field is focused, key repeat is switched on so holding Backspace or an
arrow repeats; your game's key-repeat setting is restored when editing ends. See
[Keys](#keys) for the full list.

Every value is shown on one row. A string with newlines, tabs or other control characters shows
them as `\n`, `\t` and `\ddd` escapes (the bundled fonts have no arrow glyphs for them), so
dialogue or notes never spill over the rows below. Such a string is **edited in its escaped
form**: `"two\nlines"` edits as `two\nlines`, and committing turns `\n` back into a newline. Its
newlines survive an edit that doesn't touch them, and typing `\n` adds one. A string without
control characters edits exactly as typed, so a backslash in it stays a backslash. Pasting text
with control characters switches the edit to the escaped form.

Dragged numbers are rounded to one decimal place finer than the drag's step per pixel (at most 6
places), so dragging 0.2 down to 0.05 gives 0.05, not 0.049999999999999989. Typed numbers are
never rounded. Saved files write each number in the shortest form that reads back exactly, so
the 0.05 is saved as `0.05`.

## Keys

F1 opens loupe as a **docked, full-window layout**: a top bar across the whole width, and a
left sidebar with Objects above Inspector. The game keeps drawing at full size underneath; only
the uncovered area is used for world picking. Drag the sidebar's right edge to resize it, and the
line between Objects and Inspector to change their split. Both survive window resizes and
fullscreen, and the whole layout is recomputed from the window size every frame (ADR 0008).
The **?** button in the top bar shows the key reference.

Default bindings (override any with `attach({ keys = { ... } })`):

| Action | `keys` field | Default | When it works |
|---|---|---|---|
| Show/hide the overlay | `toggle` | `f1` | Always |
| Pause / resume | `pause` | `p` | Overlay open |
| Step one frame (pauses) | `step` | `.` | Overlay open |
| Slower | `slower` | `[` | Overlay open |
| Faster | `faster` | `]` | Overlay open |
| Reset speed to x1 | `resetSpeed` | `1` | Overlay open |

Speeds step through x0.1, x0.25, x0.5, x1, x2, x4. Pausing skips the game's `love.update`
entirely rather than passing `dt = 0`, so games that react to input inside `update` stay still.
When the overlay is hidden but the game is paused or not at x1, a small badge stays on screen.
The badge also shows a hot reload that failed while the overlay was hidden, until you next open
the overlay.

Fixed shortcuts (not configurable), active while the overlay is open, including while you're
typing in a loupe field:

| Shortcut | Action |
|---|---|
| Ctrl+Z (Cmd+Z on macOS) | Undo |
| Ctrl+Shift+Z or Ctrl+Y (Cmd on macOS) | Redo |
| Ctrl+S (Cmd+S on macOS) | Save overrides |

The toolbar also has Undo, Redo and Save buttons. Saving while typing in a field saves what has
already been applied; the field keeps its text until you commit it. Undo while typing undoes the
last edit, not the text you're typing.

While a loupe field is focused (a string, or a number you clicked to type), every other key goes
to the field, after the shortcuts above:

| Key | Action |
|---|---|
| Left / Right | Move one character; with a selection, collapse it to its left or right edge |
| Home / End | Jump to the start or end |
| Shift+Left / Right / Home / End | Extend the selection |
| Backspace / Delete | Delete before or after the cursor, or the selection |
| Ctrl/Cmd+A | Select all |
| Ctrl/Cmd+C, Ctrl/Cmd+X, Ctrl/Cmd+V | Copy, cut, paste (system clipboard) |
| Enter | Commit |
| Escape | Cancel |

Ctrl/Cmd+Z, Y and S are checked first, so in a field they still undo, redo and save rather than
editing the text. Ctrl/Cmd with any other key does nothing in a field. Clicking inside a focused
field moves the cursor; there's no mouse drag-selection, word jumping or in-field undo.

## Input routing: what the game receives

While **attached and closed**, the game receives every event except the toggle key's
`keypressed` and its `keyreleased`.

While **open**:

| Event | Goes to loupe when… | Otherwise the game gets it |
|---|---|---|
| `keypressed` | it's the toggle key; it's Ctrl/Cmd + Z, Y or S (checked first, so they work while typing); a loupe text field is being edited (every other key, including Ctrl/Cmd+A, C, X, V); or it's a time-control key | yes |
| `keyreleased` | its press went to loupe (matched by key or scancode; the latest press of a key decides) | yes |
| `textinput` | a loupe text field is being edited; or it's the text of a time-control key loupe just used (the first `textinput` after that press, until the next `update`) | yes |
| `mousepressed` | Pick is on (every button, anywhere), or the pointer is over a loupe window or a loupe widget is held | yes |
| `mousereleased` | the matching press was kept by loupe | yes |
| `wheelmoved` | the pointer is over a loupe window | yes |
| `mousemoved` | loupe always sees it, and so does the game | always |

So the game never sees half a key press: when loupe uses a press, the matching release is kept
from the game too, and so is the text a hotkey such as `p` or `]` produces in LÖVE. Releases of
keys the game got still reach it.

Ctrl/Cmd combinations other than Z, Y and S reach the game when no loupe field is focused. Only
the primary mouse button drives loupe's widgets; other buttons pressed while Pick is on are
still kept from the game.

Known gaps:
- loupe filters callbacks, not polling. `love.keyboard.isDown` and `love.mouse.isDown` still
  report keys and buttons loupe used, so a game that polls them (for example `isDown("space")`
  in `love.update`) still reacts while you type or click in loupe. Pausing (P) avoids it, since
  a paused game's `love.update` doesn't run.
- Keeping a hotkey's text from the game is a heuristic: it's the first `textinput` after the
  press, until the next `update`.

Turn Pick off (toolbar button or `attach({ pick = false })`) in mouse-driven games when you need
to play while the overlay is open.

## World picking

With the overlay open and Pick on, hovering an object outlines it, clicking selects it (shown
with its path, such as `game.platforms[5]`), and dragging moves it in world units. A press must
move 3 pixels before it becomes a drag.

loupe finds objects by walking every table under the watched roots and giving each one a box,
using the first rule that applies. The walk is bounded every frame: up to 6 levels below a root
(`MAX_DEPTH`), 5,000 objects (`MAX_OBJECTS`), and 20,000 tables visited in total across all
roots, positioned or not (`MAX_VISITS`). These are fields of the internal
`loupe.core.geometry` module; objects past a cap aren't pickable that frame.

1. Your `bounds(obj)` hook, if it returns a box.
2. Numeric `x`, `y` plus `w`/`h` or `width`/`height` (also looked up in `obj.def`): a box,
   top-left anchored unless `center = true`.
3. Numeric `x`, `y` plus `r` or `radius` (also in `obj.def`): a centered box.
4. Numeric `x`, `y` alone: an 8x8 marker.

Tables without numeric `x` and `y` aren't pickable unless `bounds` handles them. When boxes
overlap, the first click selects the smallest one under the pointer. Clicking again at the same
spot (within 3 pixels) selects the next larger one, wrapping around; clicking elsewhere starts
over. After cycling to an object you can press and drag it.

Limitations: boxes are axis-aligned (rotation isn't modeled); `toWorld`/`toScreen` must map
points; an object the game keeps moving fights the drag, so pause first.

## Undo, redo and saved overrides

Every edit made in the Inspector or by dragging in the world can be undone. Changes made during
one mouse gesture (one press to release) undo as a single step, so a world drag restores `x` and
`y` together. Up to 200 steps are kept. Changes the game makes itself aren't tracked.

Any edit shows "unsaved changes" next to the Save button until you save. **Save** (button or Ctrl/Cmd+S) writes
every field that differs from its original value to `loupe_overrides.lua`; a field you set back
to its original value is dropped from the file.

### Which fields can be saved

A field is saved only when every key on the path from its root is a string or a finite number
(`game.ship.thrust`, `game.rocks[3].r`). Tables can also be keyed by functions, tables,
userdata or booleans. Edits through such keys still apply and undo like any other, but they
aren't saved: the toolbar shows "can't save <path>: it's reached through a key that isn't a
string or number". Entries with such keys in a hand-edited file are dropped when it loads.

The file is written atomically: loupe writes `loupe_overrides.lua.tmp` next to the target,
checks the write, then renames it over the old file. If that fails, the toolbar shows
"save failed: <error>" and the old file is left as it was.

### Where the file lives

| How the game runs | Location | Written with |
|---|---|---|
| Unfused, from a folder (`love mygame/`) | `mygame/loupe_overrides.lua`, next to `main.lua` | Lua's `io`, because `love.filesystem` can't write to the game folder |
| Fused, or from a `.love` archive | `loupe_overrides.lua` in the LÖVE save directory | `love.filesystem` |

The full path is printed to the console on every save. Running from a folder means the file can
be committed with the game. See ADR 0003.

### File format

```lua
-- loupe overrides: values tweaked in the inspector, re-applied when the game runs.
-- Remove a line (or this whole file) to drop a tweak. Copy values into your code to keep them.

return {
  { "game", { "ship", "thrust" }, 286 }, -- game.ship.thrust
  { "rockSizes", { "large", "r" }, 48 }, -- rockSizes.large.r
}
```

Each entry is `{ rootName, keys, value }`: the name given to `watch`, the list of keys from that
root down to the field (strings or finite numbers), and the value. Only numbers, strings and booleans
are saved; numbers keep full precision, and `1/0`, `-1/0` and `0/0` round-trip. The trailing
comment is the readable path and is ignored when loading. Entries are sorted, so the file diffs
cleanly.

### Loading

- The file is read once, at `attach`. It's Lua source, run with checks (ADR 0003):
  - Precompiled bytecode (text starting with `\27`) is refused. Bytecode isn't verified by the
    VM and can corrupt memory.
  - The chunk runs with an empty environment, so it can't reach globals (`os`, `io`,
    `require`, the game, `love`).
  - It runs under an instruction limit (`storage.MAX_INSTRUCTIONS`, 1e6) via a count hook, with
    LuaJIT's compiler turned off for the chunk (compiled code never calls hooks). An endless
    loop becomes a load error. Any debug hook set before is put back afterwards.

  What it doesn't guarantee: string methods are still reachable through the string metatable
  (`("x"):rep(1e9)` can exhaust memory), and memory use isn't limited. The file lives in the
  game's own folder or save directory, so whoever can write it can usually edit the game's code
  anyway; the checks are there to stop accidents and keep the game running, not to contain a
  hostile file.
- Malformed entries are dropped.
- If the file doesn't load, the toolbar shows "couldn't read loupe_overrides.lua: …" and the
  game runs normally.
- Overrides are written into each root just before the game's first `love.update`, and again
  whenever a getter returns a new table (for example after a restart). Values the game reads in
  `love.load` therefore see the original values.
- An override is only applied if the field still exists; loupe never creates fields. Skipped ones
  are reported as "N saved overrides no longer match the game".
- After loading, the toolbar shows "loaded N saved overrides".

Paths through array indices (`game.rocks[3]`) apply to whatever is at that index on the next run,
so overrides suit tuning values on named objects and shared definitions best.

## Hot reload

When `hotReload` is on, editing a Lua module of your game while it runs updates the running game
without a restart.

- **What's reloaded:** modules loaded with `require` whose files change. The file is found the
  way `require` finds it in LÖVE: through `love.filesystem.getRequirePath()` (so a game that
  calls `love.filesystem.setRequirePath("src/?.lua;?.lua")` works), then LÖVE's defaults
  `?.lua` and `?/init.lua`. The changed file is run
  again and its new functions and values are patched **into the existing module table in place**,
  so code that already holds a reference to the module (`local ship = require("src.ship")`) sees
  the new code.
- **What's never reloaded:** loupe's own modules, `main` and `conf`, plus any module whose name
  matches one of the `reloadIgnore` patterns.
- **On success** the toolbar shows `reloaded <module>` (or `reloaded N modules`).
- **On failure** (syntax error, an error while the file runs, or an error while patching it in)
  the module keeps its old code,
  the game keeps running, and the toolbar shows `reload failed: <module>: <error>`. If the
  overlay is hidden, the corner badge shows it too. Fix the file and save again.
- Every reload and failure is also printed to the console (`loupe: reloaded src.ship`).
- Files are checked every half second, also while paused. Changes are detected by modification
  time, which has one-second resolution, so two saves of one file within the same second may be
  seen as one.
- **Plain values:** functions are always replaced. A plain value (number, string, boolean) is
  only taken from the new file when the file changed it, so values the game or the Inspector
  changed at runtime survive a save that doesn't touch them (ADR 0007).
- **Default:** on when the game runs unfused from a folder, off when fused or packaged (there are
  no source files to edit). Pass `hotReload = false` to turn it off, or `true` to force it on.

```lua
loupe.attach({
  reloadIgnore = { "^lib%.", "^src%.save_format$" }, -- Lua patterns, matched against module names
})
```

Because a reloaded file runs again, its top-level code runs again too. Use `reloadIgnore` for
modules whose top level has side effects you don't want repeated.

## When loupe itself hits an error

loupe's per-frame work runs your hooks (`bounds`, `toWorld`, `toScreen`, `pickable`) and reads
your tables, so it can run into errors that aren't its own: a hook that throws, a strict table
whose `__index` or `__newindex` errors, a `__tostring` that fails. Drawing the overlay, applying
saved overrides and the hot-reload check each run inside an error boundary. When one fails:

- the error and its traceback are printed to the console as `loupe: <error>`, once (not again
  until you reopen the overlay);
- the overlay closes and the corner badge shows "loupe hit an error (see console) - F1 to
  reopen";
- the game's own `love.update` and `love.draw` still run that frame, and the game carries on;
- loupe's windows are rebuilt, so window positions and open tree nodes reset;
- if the hot-reload check failed, hot reload turns off for the rest of the session.

Press F1 to reopen. If the cause is still there, the overlay closes again. Input callbacks
(`keypressed`, `mousepressed`, ...) only route events and aren't inside the boundary. Errors in
your own callbacks are never caught: they reach LÖVE as usual, with your traceback intact.

## Headless runs

When `love.graphics` is nil (for example a game run with `t.modules.graphics = false`, or a test
runner with a stub `love`), `attach` returns immediately and installs nothing: no callbacks are
wrapped, no overrides are read or applied, nothing is reloaded, and `isAttached()` returns
`false`. `watch`, `unwatch` and `_VERSION` still work. This keeps simulations and tests
reproducible.

## The UI toolkit: `loupe.ui`

loupe's panels are built with a small immediate-mode toolkit that you can use on its own.
`examples/ui_gallery` uses it without the rest of loupe.

The toolkit never draws. Each frame it returns a list of plain draw commands, and
`loupe.ui.render_love` replays them with `love.graphics` (ADR 0002). That keeps everything except
the renderer testable without a window.

| Module | What it is |
|---|---|
| `loupe.ui` | `ui.new(opts)` (a context) and `ui.newInput()` (an event buffer). |
| `loupe.ui.theme` | The default theme, and `theme.build(overrides, scale)`. |
| `loupe.ui.render_love` | The only module that calls `love.graphics`: fonts, measuring, drawing. |
| `loupe.ui.escape` | Pure helpers for control characters in shown and edited text. |

### Wiring it up

This mirrors `examples/ui_gallery/main.lua`, plus the one line Shift fine-dragging needs.

```lua
local render = require("loupe.ui.render_love")
local theme = require("loupe.ui.theme")
local ui = require("loupe.ui")

local ctx, input
local state = { clicks = 0, speed = 220, name = "Fjord ranger", note = "two\nlines" }

function love.load()
  local t = theme.build() -- or theme.build({ colors = { accent = { 1, 0.5, 0.2, 1 } } }, 1.5)
  render.configure(t) -- the renderer loads fonts for the theme's font roles
  ctx = ui.new({
    measure = render.measure, -- measure(text, fontRole)
    lineHeight = render.lineHeight, -- lineHeight(fontRole)
    theme = t,
    clipboard = { get = love.system.getClipboardText, set = love.system.setClipboardText },
  })
  if render.font("body"):hasGlyphs("↵") then
    ctx.glyphs = { newline = "↵" } -- otherwise newlines show as \n
  end
  input = ui.newInput()
  input:setPosition(love.mouse.getPosition()) -- once; events keep it current after this
end

function love.draw()
  local snapshot = input:frame()
  snapshot.shift = love.keyboard.isDown("lshift", "rshift") -- Shift for fine drags
  ctx:beginFrame(snapshot, love.graphics.getWidth(), love.graphics.getHeight())
  ctx:beginWindow("demo", "Demo", { x = 20, y = 20, w = 320, h = 240 })
  if ctx:button("Click me", { primary = true }) then
    state.clicks = state.clicks + 1
  end
  ctx:sameLine()
  ctx:label(("clicked %d times"):format(state.clicks))
  state.speed = ctx:dragNumber("speed", state.speed)
  state.name = ctx:textField("name", state.name)
  state.note = ctx:textField("note", state.note) -- edited as two\nlines, saved with its newline
  ctx:endWindow()
  render.draw(ctx:endFrame())
end

function love.mousemoved(x, y) input:mousemoved(x, y) end
function love.mousepressed(x, y, b) input:mousepressed(x, y, b) end
function love.mousereleased(x, y, b) input:mousereleased(x, y, b) end
function love.wheelmoved(dx, dy) input:wheelmoved(dx, dy) end
function love.textinput(text) input:textinput(text) end

function love.keypressed(key)
  local kb = love.keyboard
  input:keypressed(key, {
    shift = kb.isDown("lshift", "rshift"),
    ctrl = kb.isDown("lctrl", "rctrl", "lgui", "rgui"), -- Ctrl, or Cmd on macOS
  })
end
```

Take the pointer position from events, not by polling `love.mouse.getPosition()` every frame:
clicks arrive between frames, and polling would hit-test them at the wrong place (ADR 0005).
Use `ctx:wantsMouse(x, y)` and `ctx:wantsKeyboard()` to keep events aimed at the UI from your
game. Key repeat is up to you (the gallery turns it on with `love.keyboard.setKeyRepeat(true)`).

### `ui.new(opts)` → context

| Option | Required | Meaning |
|---|---|---|
| `measure(text, fontRole)` | yes | Width of `text` in pixels in a font role (`"body"`, `"strong"`, `"small"`, `"title"`, `"mono"`; `nil` means body). `render.measure` fits. |
| `lineHeight` | no (14) | Font height in pixels: a number used for every role, or `function(fontRole) -> height` (`render.lineHeight` fits). |
| `theme` | no | A full theme, normally from `theme.build(...)`. Default: `theme.build()`. |
| `clipboard` | no | `{ get = function() -> string, set = function(string) }` for copy, cut and paste in fields. Without it, the context keeps a clipboard of its own, shared by its fields but not with the system. |

The row height is the theme's `rowHeight`, or the body font height plus 4 when that's taller.

Fields you can set on a context after creating it:

| Field | Default | Meaning |
|---|---|---|
| `ctx.glyphs` | `{}` | `{ newline = "↵", tab = "→" }`: what `\n` and `\t` look like in shown text. A missing entry writes the escape out (`\n`, `\t`), which every font can draw. Only set glyphs your fonts have (`font:hasGlyphs`). |
| `ctx.ellipsis` | `".."` | Appended to shortened text. loupe sets `"…"` when the body font has it. |

Other context methods: `ctx:setTheme(theme)` swaps the theme at once (for a new UI scale);
`ctx:setMetrics(measure, lineHeight)` swaps the measuring functions; `ctx:oneLine(str)` returns
`str` as one row would show it (see [Text on one row](#text-on-one-row)); `ctx:fitText(str,
maxWidth, fontRole)` shortens to fit, ending in the ellipsis; `ctx:fitTextStart(str, maxWidth,
fontRole)` keeps the end instead (`..rocks[3].hp`).

### Themes: `theme.build(overrides, scale)`

`require("loupe.ui.theme")` is itself the default theme at scale 1. Never pass it directly or
change it: `theme.build(overrides, scale)` returns a new, independent copy with `overrides` (a
partial theme, at scale 1) merged in and every pixel size scaled. Tables merge key by key;
colors and other lists replace whole. `scale` defaults to 1; font sizes scale too, and
`theme.scale` records it. `loupe.attach({ theme = ... })` takes the same overrides.

Sizes (pixels at scale 1): `space = { xs = 2, sm = 4, md = 8, lg = 12, xl = 16 }`, `padding`
10, `spacing` 4, `rowHeight` 24, `controlPadding` 10, `titleHeight` 30, `headerHeight` 30,
`barPadding` 8, `indent` 14, `radius` 6, `radiusSmall` 5, `hairline` 1, `focusRing` 2,
`scrollbarWidth` 4, `splitterGrab` 8, `sidebarDefaultMin` 300, `sidebarDefaultMax` 440,
`sidebarMin` 200, `freeMin` 160, `panelMinHeight` 90. Unitless (never scaled): `labelRatio`
0.4, `sidebarRatio` 0.24, `objectsRatio` 0.42, `scrollRows` 3. The sidebar and panel fields are
used by loupe's docked layout, not by the toolkit itself.

Font roles (`fonts.<role> = { file, size }`, files in `loupe/fonts/`):

| Role | Default | Used for |
|---|---|---|
| `body` | `Inter-Regular.ttf`, 13 | Labels, buttons, fields |
| `strong` | `Inter-SemiBold.ttf`, 13 | Floating window titles |
| `small` | `Inter-Regular.ttf`, 11 | Counts, `true`/`false` next to checkboxes |
| `title` | `Inter-SemiBold.ttf`, 11 | Docked section headers |
| `mono` | `JetBrainsMono-Regular.ttf`, 12 | Numbers, read-only values, color hex |

Color roles (`colors.<role> = { r, g, b, a }` in 0..1):

| Role | Used for |
|---|---|
| `surface` | Docked panels |
| `surfaceRaised` | Floating windows and popovers |
| `titleBar` | Not drawn by loupe 1.1.1; available to custom chrome |
| `field`, `fieldHover` | Value inputs |
| `control`, `controlHover`, `controlActive` | Buttons, segmented controls, a toggle's off track |
| `hover` | Hovered rows |
| `border`, `borderStrong` | Hairlines; hovered fields and swatch outlines |
| `text`, `textMuted`, `textFaint`, `textOnAccent` | Text, labels and headers, hints and disabled text, text on accent fills |
| `accent`, `accentHover` | Primary buttons, a toggle's on track, checked boxes, a focused field's border, the caret, a held splitter |
| `accentSoft` | loupe's world-picking fill (not used by the toolkit's widgets) |
| `selection` | Selected tree rows |
| `selectionText` | Selected text in a field (new in 1.1.1) |
| `focus` | Focus ring, hovered splitters |
| `warning`, `warningSoft`, `danger`, `success` | Status colors for your own widgets; loupe's top bar and badge use `warning`, `warningSoft` and `success` |
| `scrollbar`, `scrollbarHot` | Scrollbar thumb, idle and hovered/held |
| `shadow` | Floating window shadow |

### `ui.newInput()` → input

Buffers LÖVE events between frames so each press, release and keystroke is seen exactly once.

| Method | Feed it from |
|---|---|
| `input:setPosition(x, y)` | once at startup |
| `input:mousemoved(x, y)` | `love.mousemoved` |
| `input:mousepressed(x, y, button)` | `love.mousepressed` (only button 1 drives widgets) |
| `input:mousereleased(x, y, button)` | `love.mousereleased` (only button 1) |
| `input:wheelmoved(dx, dy)` | `love.wheelmoved` (only `dy` is used) |
| `input:textinput(text)` | `love.textinput` |
| `input:keypressed(key, mods)` | `love.keypressed`. `mods = { shift = bool, ctrl = bool }` (optional) are the modifiers held with the key; pass Cmd as `ctrl` on macOS. |
| `input:frame()` → snapshot | once per frame; pass the result to `ctx:beginFrame` |

The snapshot is `{ x, y, down, pressed, released, wheel, typed }`. `typed` holds text and keys
in arrival order, so "backspace, 3" and "3, backspace" differ. Each entry is either
`{ text = "a" }` or `{ key = "left", shift = true, ctrl = true }`, where `shift` and `ctrl` are
`true` or absent. Fields read a key with `ctrl` as a shortcut (A, C, X, V; others are ignored)
and Shift with Left, Right, Home or End as extending the selection.

The snapshot has no `shift` field of its own. Set `snapshot.shift = true` before `beginFrame`
while Shift is held to get fine number drags (loupe does this; see the example above).

### Frames and windows

| Method | Notes |
|---|---|
| `ctx:beginFrame(snapshot, screenW, screenH)` | Start a frame with `input:frame()`. `screenW`/`screenH` are optional; with them, floating windows are kept on screen. |
| `ctx:endFrame()` → commands | Ends the frame and returns the draw commands, back to front. |
| `ctx:beginWindow(id, title, rect)` | See below. Windows can't nest. |
| `ctx:endWindow()` | Closes the current window. |
| `ctx:wantsMouse(x, y)` → boolean | True when a mouse event at that point belongs to the UI: over a window or splitter drawn last frame, or while a widget is held. |
| `ctx:wantsKeyboard()` → boolean | True while a text or number field is being edited. |
| `ctx:rectOf(id)` → `{ x, y, w, h }` or nil | Where the widget, window or splitter with this full id was last frame. A widget's full id is the window id, any pushed ids and open tree nodes, and the label's id part, joined by `/` (in the gallery, `"widgets/clicks"` is the `Reset##clicks` button in the `widgets` window). Useful for tools and tests. |
| `ctx:pushId(name)` / `ctx:popId()` | Scope widget ids, for repeated widgets with the same label. |

`rect` is `{ x, y, w, h }` plus any of these options:

| Option | Meaning |
|---|---|
| (none) | A **floating** window. The rect is used only the first time `id` is seen; after that the window keeps its own (possibly dragged) position and size. It drags by its title bar, comes to the front when clicked, and, given the screen size, is clamped so the title bar stays reachable. |
| `docked = true` | The rect is applied every frame (for layouts that follow the screen). No title drag, never brought to front. Drawn as a flat panel with an uppercase section header. |
| `popover = true` | Like `docked`, but drawn as a raised card with a shadow. |
| `header = false` | No header. Passing `nil` as the title does the same. |
| `headerRight` | Muted text at the right of the header, such as a count. |
| `edges = { top, right, bottom, left }` | Hairlines along those edges of a docked panel. |
| `padding`, `padY` | Inner padding, horizontal and vertical (default: the theme's `padding`; `padY` defaults to `padding`). |
| `spacing` | Gap between rows (default: the theme's `spacing`). |
| `surface` | Background color of a docked panel (default: `colors.surface`). |
| `autoHeight = true` | The window grows to fit its content and never scrolls or clips vertically. A docked auto-height window keeps the height it reached last frame. |

Windows with more content than fits scroll with the wheel (`scrollRows` rows per notch) and
show a thin scrollbar whose thumb can be dragged. A window that isn't built in a frame is
hidden that frame. A field that isn't drawn in a frame loses keyboard focus.

### Layout

Widgets stack top to bottom. `ctx:sameLine()` puts the next widget to the right of the previous
one (it wraps to a new row when it doesn't fit). `ctx:alignRight(width)` puts the next widget,
`width` wide, flush with the right edge of the current row; use `ctx:buttonWidth(label, opts)` or
`ctx:toggleWidth(label)` to know that width ahead of time. `ctx:spacer(width)` leaves empty
room on a row, and `ctx:divider()` draws a thin vertical rule between groups on a row.

### Widgets

Widgets must be called between `beginWindow` and `endWindow`. A label may carry a hidden id
after `##`: `"Reset##clicks"` shows "Reset" but is told apart from other "Reset" buttons by
`clicks`. A label of only `"##id"` shows nothing (icon-only buttons and segments). Every label
and value is shown on one row (see [Text on one row](#text-on-one-row)).

| Widget | Returns | Behavior |
|---|---|---|
| `ctx:label(text, color?, fontRole?)` | nothing | One row of text, shortened with the ellipsis to fit. `color` defaults to `colors.text`. |
| `ctx:pathLabel(text, color?, fontRole?)` | nothing | Like `label`, but keeps the end when shortened (`..rocks[3].hp`). |
| `ctx:valueRow(label, value)` | nothing | A read-only labeled value in the mono font (for things that can't be edited). |
| `ctx:separator()` | nothing | A horizontal hairline. |
| `ctx:divider()` | nothing | A thin vertical rule on the current row. |
| `ctx:spacer(width)` | nothing | Empty room `width` pixels wide. |
| `ctx:button(label, opts?)` | `clicked` | True on the frame the button is released while still under the pointer. See button options below. |
| `ctx:buttonWidth(label, opts?)` | number | The width `button` would take with these options. |
| `ctx:segmented(items, opts?)` | index or nil | A row of joined buttons. `items` are labels (with optional `##id`); `opts.icons` maps index to icon name (shown when the label is empty); `opts.font` is a font role. Returns the index clicked this frame. |
| `ctx:toggle(label, value)` | `value, changed` | A pill switch with its label to the right. |
| `ctx:toggleWidth(label)` | number | The width `toggle` would take. |
| `ctx:checkbox(label, value)` | `value, changed` | Label on the left, a box and a faint `true`/`false` on the right. Click toggles. |
| `ctx:dragNumber(label, value, opts?)` | `value, changed` | See [Number fields](#number-fields). |
| `ctx:textField(label, value)` | `value, changed` | See [Text fields](#text-fields). `changed` is true on the frame an edit is committed with a different value. |
| `ctx:treeNode(label, opts?)` | `open, picked` | A collapsible row. When `open` is true, call `ctx:treePop()` after its children. See tree options below. |
| `ctx:treePop()` | nothing | Ends an open tree node. |
| `ctx:colorSwatch(label, color)` | `clicked` | Shows an `{r, g, b, a}` color with its hex value, plus the alpha as a percentage when below 1. |
| `ctx:splitter(id, x, y, w, h, axis)` | `hovered, held, center` | A drag handle outside any window (call it between `beginFrame` and `endFrame`, outside `beginWindow`). `axis` `"x"` moves left/right, `"y"` up/down. While held, `center` is where the divider's center should go (pointer minus the grab offset); otherwise nil. Splitters take the mouse ahead of the windows under them and draw a slim accent line when hovered or held. |

Button options (`opts`, all optional):

| Option | Meaning |
|---|---|
| `primary` | Accent fill, `textOnAccent` label. |
| `quiet` | No background until hovered. |
| `icon` | A vector icon before the label: `"pause"`, `"play"`, `"step"`, `"minus"`, `"plus"`, `"chevronRight"`, `"chevronDown"` or `"check"`. With an empty label (`"##id"`) the button is square-ish. |
| `disabled` | Faint label, not clickable, never hovered. |
| `selected` | Drawn pressed in. |
| `width` | Fixed width instead of fitting the label. |
| `color` | Label color. |
| `font` | Label font role. |

Tree node options (`opts`, all optional):

| Option | Meaning |
|---|---|
| `open` | Initial state, the first time the node is seen. After that the node remembers its own state. |
| `selectable` | The chevron toggles and the rest of the row picks: `picked` is true that frame. Without it, a click anywhere toggles. |
| `selected` | Drawn with the `selection` pill. |
| `leaf` | Nothing to expand: no chevron, never open, and with `selectable` the whole row picks. |
| `count` | Muted text at the right of the row, such as a child count. |

#### Number fields

`ctx:dragNumber(label, value, opts?)` shows the value in the mono font: whole numbers as
integers, others with up to 3 decimals. Press and drag left or right to change it. The drag
starts after 3 pixels; a click without dragging starts typing instead.

| Option | Meaning |
|---|---|
| `speed` | Change per pixel. Default: `max(0.05, abs(start) * 0.005)`, where `start` is the value when the drag began. |
| `min`, `max` | Clamp dragged and typed values. |
| `integer` | `true`: always whole. `false`: never forced whole. `nil` (default): whole when the drag started from a whole number. |

- **Shift** (`snapshot.shift`) makes the drag 10 times finer. It also lets a value that's whole
  only because it started whole move in fractions; `integer = true` stays whole.
- **Drag rounding:** a dragged value is rounded to one decimal place finer than the step per
  pixel, `ceil(-log10(step)) + 1` places, between 0 and 6. Dragging 0.2 left by 3 pixels at a
  speed of 0.05 gives exactly 0.05, not 0.049999999999999989. Shift's finer step gets one more
  place.
- **Typing:** while typed into, the field works like a text field. Enter or clicking elsewhere
  commits, Escape cancels. A committed value that isn't a number is ignored. Typed values are
  clamped to `min`/`max` but never rounded.

#### Text fields

`ctx:textField(label, value)` shows `value` on one row; click it to edit. Enter (or keypad
Enter) and clicking elsewhere commit; Escape cancels. Clicking inside a focused field moves the
cursor there. The same editing applies to a `dragNumber` being typed into.

| Key | Effect |
|---|---|
| Left / Right | Move one character. With a selection, collapse it to its left or right edge. |
| Home / End | Jump to the start or end. |
| Shift + Left / Right / Home / End | Extend the selection. |
| Backspace / Delete | Delete the character before or after the cursor, or the selection. |
| Ctrl/Cmd+A | Select all. |
| Ctrl/Cmd+C / X / V | Copy, cut, paste (through `opts.clipboard`). Copy and cut need a selection. |
| Typing | Inserts at the cursor, replacing the selection. |

Everything works on UTF-8 character boundaries. The selection is highlighted with
`colors.selectionText`. Long text scrolls to keep the cursor in view.

**Control characters.** A string that holds newlines, tabs or other control characters is
edited in its escaped form: `"a\nb"` shows as the four characters `a`, `\`, `n`, `b` and is
decoded on commit (with `escape.decode`). Its newlines survive an edit that doesn't touch them,
and typing `\n` adds one. A string without control characters edits exactly as typed: a
backslash stays a backslash. Pasting text with control characters switches the edit to the
escaped form, keeping the cursor and selection on the same characters. Copying from an escaped
edit copies the real characters.

### Text on one row

Every text box is one row tall. Labels, values, window headers, counts and every `text` draw
command go through `ctx:oneLine`, which writes `\n` and `\t` with `ctx.glyphs` (or as `\n` and
`\t` when unset) and other control characters as Lua escapes (`\027`). Text is escaped before
it's measured, so shortening fits what's drawn. Shown text doesn't escape backslashes, so a
literal `a\nb` and one with a real newline look the same until edited.

`ctx.glyphs` and `ctx.ellipsis` are plain fields: set them to glyphs your fonts can draw. loupe
uses "↵" and "→" only when both its body and mono fonts have them, which the bundled subsets
don't, so loupe shows `\n` and `\t`.

### `loupe.ui.escape`

Pure functions, usable on their own.

| Function | Returns |
|---|---|
| `escape.hasControl(str)` | Whether `str` has any control character. |
| `escape.oneLine(str, glyphs?)` | `str` for display on one row: `\n` and `\t` become `glyphs.newline`/`glyphs.tab` when given, else the written-out `\n`/`\t`; `\r` becomes `\r`, and other control characters `\ddd`. Lossy; returns `str` unchanged when it has no control characters. |
| `escape.encode(str)` | The editable form: control characters as above and backslashes doubled. |
| `escape.decode(str)` | Reads `\n`, `\r`, `\t`, `\\` and `\ddd` (up to 255). Any other backslash is kept as typed. `decode(encode(s)) == s` for every string. |

### Rendering: `loupe.ui.render_love`

The only module that calls `love.graphics`.

| Function | Notes |
|---|---|
| `render.configure(theme)` | Use the theme's font roles (a `theme.build` result). Call it again when the scale changes; fonts already made for a file and size are reused. Without it, the default theme's roles at scale 1 are used. |
| `render.font(role)` | The LÖVE `Font` for a role (`nil` means body). |
| `render.measure(text, role)` | Width of `text` in that role's font. |
| `render.lineHeight(role)` | Height of that role's font. |
| `render.draw(commands)` | Replays commands in screen space inside `love.graphics.push("all")`: it resets the origin, scissor, canvas and shader, so the game's camera and canvases don't affect the UI. The replay runs in `pcall`, so the matching `pop` always happens; an error (such as an unknown command) is raised again after it. Fonts are re-rasterized when `love.graphics.getDPIScale()` changes, so text stays crisp when the window moves to a screen with another pixel density. |

**Fonts.** Subsets of Inter (Regular, SemiBold) and JetBrains Mono (Regular) ship in
`loupe/fonts/` (SIL OFL 1.1, about 163 KB). They're loaded through `love.filesystem` relative to
loupe's module path, or with `io` when loupe is required through `package.path` from outside the
game folder (as the examples do). If a file is missing or fails to load, LÖVE's default font is
used at the role's size, so deleting the folder is safe. The LuaRocks rockspec doesn't install
the fonts. The subsets have no "↵", and the mono one no "→".

**Draw commands** are plain tables, for writing your own renderer. Positional fields come first;
`radius`, `width` and `font` are optional named fields a simpler renderer may ignore.
Colors are `{ r, g, b, a }` in 0..1 (`a` defaults to 1).

| Command | Draws |
|---|---|
| `{ "rect", x, y, w, h, color, radius = r }` | A filled rectangle, rounded when `radius` is set. |
| `{ "outline", x, y, w, h, color, radius = r, width = px }` | A rectangle outline, `width` (default 1) drawn inside the box. |
| `{ "text", string, x, y, color, font = role }` | One line of text at whole pixels, in a font role (default body). `render_love` passes it through `escape.oneLine` too, as a backstop for text built outside the toolkit. |
| `{ "line", { x1, y1, x2, y2, ... }, color, width = px }` | A polyline. |
| `{ "circle", x, y, radius, color }` | A filled circle. |
| `{ "poly", { x1, y1, x2, y2, ... }, color }` | A filled polygon. |
| `{ "clip", x, y, w, h }` | Clip what follows to that box (scissor). |
| `{ "unclip" }` | Stop clipping. |

Commands may carry other named fields used internally (such as `windowHeight`); ignore them.

### Toolkit limitations

- Text fields have no mouse drag-selection or Shift+click, no word jumps (Ctrl/Alt+Left/Right),
  and no undo of their own. Inside loupe, Ctrl/Cmd+Z while typing undoes loupe's last edit, not
  the field's text.
- Floating windows move but don't resize; docked panels resize through `splitter`.
- The bundled font subsets lack "↵" (and the mono subset lacks "→"), so with them newlines and
  tabs show as `\n` and `\t`.
- Shown (not edited) text doesn't escape backslashes; see [Text on one row](#text-on-one-row).
- Only the primary mouse button drives widgets, and only vertical wheel movement scrolls.
