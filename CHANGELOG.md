# 1.2.0 — local preview

- Optional MCP authoring server and opt-in live bridge.
- Shared inspector undo/save history for AI edits; screenshots and paused polling.
- `loupe.editRevision()`: a counter that is 0 until Loupe changes game state (edit, undo, redo, MCP set, or saved overrides applied at attach), so a host can flag modified runs.
- Local playable Afterimage showcase with Endless mode and original music.
- Afterimage: opt-in gameplay analytics through vendored ravensight-love 0.3.0 (schema_version 1,
  twelve events, ANALYTICS switch on the title and pause screens, off by default), saved
  settings (`settings.txt`), and `src/version.lua`. No key in the repository: release tools inject
  a public key from `RAVENSIGHT_PUBLIC_KEY`; forks and local builds send nothing. See ADR 0011.
- Release tooling: `tools/build_itch.py`; `tools/build.sh` writes the analytics config only with
  `AFTERIMAGE_RELEASE=1`; `build_web.py --distribution web-pages|web-itch`; `game_build` never
  packages `analytics.config.lua`.
- Gates: `tools/audit_release.py` flags Ravensight keys and gains `--artifact` (keys only in the
  two expected places, none in the source zip); `tools/smoke_web.mjs` checks consent in a real
  browser in the Pages workflow; analytics and settings tests run in `tools/check.sh`.

# Changelog

All notable changes to loupe are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and loupe follows
[Semantic Versioning](https://semver.org/).

## [1.1.1] - 2026-10-09

Finishing the 1.1 UI: one-line text, clean drags, selection and clipboard, no leaked key
releases.

### Added
- **Selection and clipboard in text fields** (and in a number being typed into): Shift with
  Left, Right, Home or End extends the selection; Left and Right collapse it; Ctrl/Cmd+A selects
  all; typing, Backspace and Delete replace it; Ctrl/Cmd+C, X and V copy, cut and paste through
  the system clipboard. UTF-8 safe. Ctrl/Cmd+Z, Y and S are still checked first.
- Toolkit: `ui.new({ clipboard = { get, set } })` (without it a context keeps its own
  clipboard), `input:keypressed(key, mods)` with `mods = { shift, ctrl }` carried on each key
  event, the `selectionText` theme color, `ctx.glyphs` and `ctx:oneLine(str)`, and the pure
  `loupe.ui.escape` module (`hasControl`, `oneLine`, `encode`, `decode`). See docs/api.md.
- `examples/ui_gallery` wires the clipboard and modifiers and has a multi-line `note` field.

### Fixed
- **Strings with newlines, tabs or other control characters show on one row** (`\n`, `\t`,
  `\ddd`) instead of spilling over the rows below, everywhere loupe shows text: labels, values,
  headers, the picker's path pill, and as a backstop in `render_love`. Shortening measures the
  escaped text, so it fits what's drawn. Such a string is edited in its escaped form and decoded
  on commit, so its newlines survive an edit and typing `\n` adds one; strings without control
  characters edit exactly as before.
- **Dragged numbers land on clean values.** A dragged value is rounded to one decimal place
  finer than the step per pixel (0 to 6 places), so 0.2 dragged down by 0.15 is 0.05, not
  0.049999999999999989. Shift's finer step gets one more place. Typed values are never rounded.
- **Key releases and hotkey text no longer leak to the game.** The game doesn't get the
  `keyreleased` of a key loupe used (matched by key or scancode; releases of keys the game got
  still reach it), nor the `textinput` of a hotkey loupe used while not typing (`p` and `]`
  produce text in LÖVE).

- Saved files no longer show float noise: numbers are written in the shortest form that reads
  back exactly (`0.05`, not `0.050000000000000003`; `0.1 + 0.2` still keeps all 17 digits).
- CI's smoke job would have hung on `examples/shared/` (a library with no `main.lua`); it now
  skips folders without one, and every launch runs under a timeout.

### Verified
- **Plain PUC Lua 5.1.5** (built from the official source): the full suite and coverage gate pass.
- **Linux** (`ubuntu:24.04`, arm64 and emulated amd64): `tools/check.sh` passes under LuaJIT and
  Lua 5.1, and all three examples run 120 frames under real LÖVE 11.5 and Xvfb, exiting 0.
  `tools/ci-docker.sh` reproduces the CI workflow locally in Docker.
- CI actions moved to their Node 24 majors (`checkout@v6`, `gh-actions-lua@v13`,
  `gh-actions-luarocks@v6`, `stylua-action@v5`); smoke runs set `ALSOFT_DRIVERS=null` so audio
  initializes headless. The workflow itself still hasn't run on GitHub (the project is local).

### Known limitations
- `love.keyboard.isDown` and `love.mouse.isDown` still report keys and buttons loupe used; only
  callbacks are filtered.
- The bundled font subsets lack "↵" (and the mono subset "→"), so newlines and tabs show as
  `\n` and `\t`. Shown (not edited) text doesn't escape backslashes, so a literal `a\nb` and a
  real newline look the same until edited.
- Text fields have no mouse drag-selection, Shift+click, word jumps or in-field undo.
- Keeping a hotkey's text from the game is a heuristic: the first `textinput` after the press,
  until the next `update`.

## [1.1.0] - 2026-10-09

A redesigned, full-window UI, hardening from the 1.0 code review, and rebuilt example games.

### UI redesign
- **Docked full-window layout.** F1 now opens a full-width top bar and a full-height left sidebar
  (Objects above Inspector) instead of floating windows. Everything is laid out from the window
  size every frame, so resizing and fullscreen never leave a panel off screen (ADR 0008).
- **Draggable splitters** for the sidebar width and the Objects/Inspector split, with a resize
  cursor. Their positions survive window resizes and scale changes.
- **Clean dark theme:** rounded corners, hairline borders, a single blue accent, muted section
  headers, pill selection, rounded inputs and a visible focus ring. New `attach({ theme = ... })`
  merges a partial theme over a copy of the default (the module itself is never mutated).
- **Fonts:** Inter (body, headings) and JetBrains Mono (numbers) are bundled in `loupe/fonts/`
  (about 163 KB, SIL OFL 1.1). Delete the folder to fall back to LÖVE's default font.
- **HiDPI and large screens:** fonts re-rasterize when the DPI scale changes, so text stays crisp
  on Retina. `attach({ uiScale = n })` sets the layout scale; by default it grows on very tall
  windows (2x at 2160 points).
- The top bar holds the time controls, a Pick switch, Undo/Redo/Save, the unsaved indicator and
  status messages; **?** opens the key reference.
- Number fields drag whole numbers in whole steps; hold Shift for fine (10x slower) drags.
- Text fitting is a binary search (it was quadratic on long strings); the scrollbar thumb is
  draggable; floating windows (standalone toolkit) are kept on screen.
- Toolkit additions: `toggle`, `segmented`, `divider`, `spacer`, `alignRight`, `splitter`,
  `rectOf`, docked windows, button options, font roles in draw commands (see docs/api.md).


### Added
- Examples work fullscreen (F11 or Alt+Enter, desktop fullscreen), in resizable windows and on
  HiDPI displays (`highdpi`, `msaa = 4`). M mutes the synthesized sound effects. Neither key
  clashes with loupe's defaults.
- `examples/asteroids` rebuilt: glowing vector look, particle explosions, shock rings, screen
  shake, a parallax starfield and nebula, a title screen, 3 lives with a respawn shield, an extra
  life every 10,000 points, a pause and "WAVE n" banner between waves, game over and a session
  best score. The playfield follows the window size.
- `examples/platformer` rebuilt: parallax sky, sun, clouds and ridges; a smoothed camera that
  leads in the facing direction; acceleration and friction, coyote time, jump buffering,
  variable jump height and squash/stretch; patrolling enemies you can stomp; coins with sparks
  and a rising chime; a waving flag with confetti, fireworks and a "LEVEL COMPLETE" panel.
- New roots and tunables to drag live in the examples:
  - asteroids: `fx` (`glow`, `glowPasses`, `glowSpread`, `lineWidth`, `shakeStrength`,
    `shakeDecay`, `shakeOnRock`, `rockSparks`, `shipSparks`, `thrustRate`, `maxParticles`,
    `flash`, `stars`, `starParallax`, `starDrift`, `twinkle`, `nebula`); `sound` (`volume`,
    `muted`); `bullets.radius` and `bullets.color`; `game.ship.maxSpeed`, `spawnShield` and
    `flameColor`; `game.lives`, `extraLifeEvery`, `respawnDelay` and `waveDelay`; a `color` per
    rock size in `rockSizes`.
  - platformer: `game.player` (`speed`, `accel`, `airAccel`, `friction`, `jump`, `gravity`,
    `fallGravity`, `maxFall`, `jumpCut`, `coyoteTime`, `jumpBuffer`, `squash`, `color`);
    `game.camera` (`smoothing`, `lookAhead`, `leadSpeed`); `game.fx` (`shakeStrength`,
    `shakeDecay`, `dustCount`, `coinBurst`, `coinSparkle`, `stompBurst`, `deathBurst`,
    `fireworkEvery`, `fireworkSparks`, `confetti`, `stompBounce`); `game.backdrop` (`skyTop`,
    `skyBottom`, `sun`, `cloudFactor`, `cloudSpeed`, and `layers[i]` with `factor`, `base`,
    `height`, `wavelength`, `color`); `game.spawn`, a draggable `x, y` marker; `sound`.

### Changed
- An error boundary around loupe's per-frame work (drawing the overlay, applying saved
  overrides, the hot-reload check). An error there, from a user hook such as `bounds` or
  `toWorld`, a strict table's metamethod or loupe itself, no longer crashes the game: loupe
  prints it with a traceback once, closes the overlay, and the corner badge shows "loupe hit an
  error (see console) - F1 to reopen". The game's own callbacks still run. If the hot-reload
  check is what failed, hot reload turns off for the session.
- The world scan is bounded: `geometry.MAX_VISITS` (20,000 tables per frame, across all roots)
  caps how much is walked, alongside the existing depth and object caps. The scan also allocates
  much less per frame.
- Saving overrides is atomic: loupe writes `loupe_overrides.lua.tmp`, checks the write, then
  renames it over the old file, so a failed save never leaves a truncated file. Write failures
  are reported as "save failed: ...".

### Fixed
- Games that chain a love callback after `attach` (`local old = love.update; love.update =
  function(dt) old(dt) ... end`, as `hump.gamestate.registerEvents()` does from `love.load`) no
  longer overflow the stack. Chains of any depth work, also after `detach` (ADR 0004).
- An edit to a field reached through a function, table, userdata or boolean key no longer
  crashes the game. The edit applies and undoes as usual, and loupe says "can't save <path>:
  it's reached through a key that isn't a string or number" instead of saving it.
- Undo and redo follow a getter root that was replaced (for example after a restart): the
  change is applied to the same field under the new table when it exists there.
- Large integers are saved exactly on platforms where a C `long` is 32 bits (64-bit Windows).
- Ctrl/Cmd+S, Ctrl/Cmd+Z and Ctrl/Cmd+Y (and Ctrl/Cmd+Shift+Z) work while a loupe text field is
  focused. Saving doesn't commit the field being typed in.
- Hot reload finds module files through `love.filesystem.getRequirePath()`, so games that call
  `love.filesystem.setRequirePath` (e.g. `"src/?.lua"`) reload too.
- The Objects and Inspector windows survive keys whose `__tostring` throws or returns a
  non-string, and a failed in-place patch during hot reload is reported as "reload failed"
  instead of escaping.
- The platformer's first ledges are reachable: the 1.0 jump peaked at about 58px, below the
  70px ledge.

### Security
- The overrides loader refuses precompiled bytecode (text starting with `\27`) and runs the
  file under an instruction limit (`storage.MAX_INSTRUCTIONS`, 1e6), with LuaJIT's compiler off
  for the chunk, so an endless loop becomes a load error.
- Corrected wording (ADR 0003): 1.0 described the loader as a sandbox whose file "can only be
  data". It isn't a full sandbox. It runs with an empty environment, so it can't reach globals
  (`os`, `io`, `require`, the game, `love`), but string methods are still reachable through the
  string metatable and memory use isn't limited. The checks stop accidents and keep the game
  running; they don't contain a hostile file.

### Known limitations
- The bundled fonts aren't installed by the LuaRocks rockspec (it installs Lua modules only), so
  a LuaRocks install uses LÖVE's default font. Copying the `loupe/` folder keeps them.
- The error boundary covers draw and update work, not input callbacks. Recovering from an error
  resets window positions and tree open/closed state.
- In the examples, screen shake isn't part of `toWorld`/`toScreen`, so outlines lag by up to
  `shakeStrength` pixels while a shake lasts. Asteroids' best score isn't saved. The examples
  need `examples/shared/` when copied out of the repo.

## [1.0.0] - 2026-10-09

First release. Install by copying `loupe/` next to `main.lua`. See [docs/api.md](docs/api.md).

### Added
- `loupe.attach(opts)`, `detach`, `isAttached`, `isOpen`, `setOpen` and `_VERSION`. Callbacks are
  wrapped through a metatable on `love`, so games that reassign `love.update` and friends at
  runtime stay wrapped (ADR 0004).
- Overlay toolbar with pause, single-step (`stepSize`, default 1/60 s) and speed presets from x0.1
  to x4, plus a badge while hidden and time is altered. Rebindable keys (`keys`); F1 toggles.
- `loupe.watch(target, name)` / `loupe.unwatch(name)` for tables and getter functions; a getter
  that throws is reported instead of crashing the game.
- Objects window (tree of watched roots, cycle-safe) and Inspector (live editing of numbers,
  booleans, strings, `{r, g, b, a}` colors and nested tables).
- World picking: hover, select and drag objects, with `toWorld`/`toScreen` for cameras and
  letterboxing, `bounds`, `center` and `pickable` hooks, the smallest box winning, and a Pick
  toggle (`pick`) (ADR 0006).
- Undo/redo (Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z, Ctrl/Cmd+Y and toolbar buttons); one mouse gesture
  undoes as one step.
- Saved overrides: Ctrl/Cmd+S writes `loupe_overrides.lua` next to `main.lua` when running from a
  folder, or to the save directory otherwise. Re-applied at startup and whenever a getter returns
  a new table. The file is loaded as data only (ADR 0003).
- Hot reload (`hotReload`, `reloadIgnore`): changed modules are re-run and patched into their
  existing module tables in place; a failed reload keeps the old code and shows
  "reload failed: <module>: <error>".
- Input routing: clicks, wheel and typing aimed at loupe stay out of the game; pointer position
  comes from events (ADR 0005). Key repeat is on while a loupe field is focused, then restored.
- Text fields with a UTF-8-safe cursor (Left/Right, Home/End, Backspace, Delete).
- Click again on stacked objects to cycle through them, smallest first.
- Leaf tables in Objects have no expand arrow; a selection that left the game is marked
  "(no longer in the game)".
- The corner badge shows a hot reload that failed while the overlay was hidden.
- Headless runs: `attach` does nothing when `love.graphics` is nil.
- Standalone immediate-mode UI toolkit, `require("loupe.ui")`: windows, labels, buttons,
  checkboxes, drag-numbers, text fields, tree nodes and color swatches, emitting draw commands
  that `loupe.ui.render_love` replays (ADR 0002).
- Examples: `asteroids`, `platformer` (camera and letterbox) and `ui_gallery`.
- LuaRocks rockspec.

### Known limitations
See the "Known limitations" section of each log in [docs/ai-log/](docs/ai-log/) and the gaps
listed in [docs/api.md](docs/api.md), among them: `love.mouse.isDown` still reports buttons loupe
captured (and `love.keyboard.isDown` keys it used); overrides keyed by array index follow the
index, not the object; hot reload doesn't patch file-scope locals or upvalues. (1.0 also leaked
`keyreleased` for keys loupe consumed and had no selection or clipboard in text fields; both
are fixed in 1.1.1.)

<!-- No remote yet (the project is local); add a compare/tag link here when one exists. -->
