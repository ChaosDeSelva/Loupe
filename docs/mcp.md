# Build with an AI. Tune with your hands.

Loupe's optional MCP server lets a coding assistant create and package a LÖVE game,
then inspect its running state and make the same undoable edits you can make with F1.
The inspector remains a zero-dependency Lua library. Only the optional MCP host needs Python 3.10+.

## Connect

Copy `loupe/` into your game. Watch your state and enable the bridge explicitly:

```lua
local loupe = require("loupe")
loupe.watch(function() return game end, "game")
loupe.attach({ mcp = true })
```

Call `loupe.bridgeDirectory()` after attaching to get the bridge's absolute path.
It is normally `<LÖVE save directory>/loupe-mcp`. Give each project a distinct
`t.identity` in conf.lua, and run one bridge-enabled instance per identity.

For a newly scaffolded game, read its generated `t.identity` from `conf.lua`.
Typical bridge locations are:

- macOS: `~/Library/Application Support/LOVE/<identity>/loupe-mcp`
- Windows: `%APPDATA%/LOVE/<identity>/loupe-mcp`
- Linux: `$XDG_DATA_HOME/love/<identity>/loupe-mcp` (normally `~/.local/share/love/...`)

Use an absolute expanded path in the MCP configuration. The folder appears after
launching with `--mcp`. You can configure the server without `--bridge-dir` to
scaffold first, then add the generated identity's path and reconnect. For an
existing custom save configuration, `loupe.bridgeDirectory()` is authoritative.

For Codex, add a server to your MCP configuration (replace every path):

```toml
[mcp_servers.loupe]
command = "python3"
args = ["/absolute/path/loupe/mcp/server.py", "--project", "/absolute/path/my-game", "--bridge-dir", "/absolute/path/to/save-directory/loupe-mcp", "--love", "/absolute/path/to/love"]
```

On macOS the LÖVE executable is usually `/Applications/love.app/Contents/MacOS/love`.
Restart the MCP client after changing its configuration. No API key, network listener,
or extra Python package is required. Use an absolute Python executable if your GUI has a different PATH.

## A useful first prompt

> Inspect the game root, pause the game, increase player speed by 15%, capture a screenshot,
> then resume. Let me try it before saving. If I dislike it, undo the change.

To make a new game, create an empty directory and configure `--project` to point at it.
Ask the assistant to call `game_scaffold`, edit the source, launch, inspect, and build.
Scaffolded games enable the bridge when launched with `--mcp`; `game_launch` supplies that flag.

## Tools

| Tool | Purpose |
| --- | --- |
| `project_files`, `project_read` | Explore the configured game project |
| `project_write` | Edit supported text files, with backups in `.loupe-backups` |
| `game_scaffold` | Create a minimal game or complete Afterimage template in an empty project |
| `game_capabilities` | Discover runtime helpers, authoring workflows and limits |
| `project_assets` | List image/audio/font assets and PNG dimensions |
| `asset_import` | Copy from an explicitly configured inbox, without overwriting |
| `game_build` | Produce `dist/game.love` |
| `game_launch`, `game_stop` | Run and stop the server's own game process |
| `loupe_status`, `loupe_inspect` | Read clock state and bounded watched-table snapshots |
| `loupe_set` | Set an existing scalar through Loupe's shared undo history |
| `loupe_control` | Pause, resume, step, open, close, undo, redo, explicitly save |
| `loupe_screenshot` | Return the game window as a PNG |

Live changes appear immediately in the F1 inspector. Source edits require a restart or the
host game's own reload support. Save is explicit and writes Loupe overrides; it does not
rewrite the game's Lua source. Project writes are a separate authoring operation.

## Boundaries and troubleshooting

The bridge is off by default. It accepts bounded data requests over a local filesystem
mailbox with session identifiers and expiry, not Lua expressions or shell commands.
Any process with access to the same user account can access these files; this is not a
security boundary against other local software. Launch only trusted game source.

Paths are confined to the configured project; hidden/config directories and symlinks are
blocked. Builds omit local override files, backups, tests, authoring tools and metadata.
The server never writes logs to stdout because stdout carries MCP messages.

A timeout usually means the game is closed, lacks `mcp=true`, or uses a different save
identity. Restart a crashed game to replace a stale session. A paused Loupe clock still
processes requests. This bridge is for native LÖVE, not the browser build.

Run `python3 -m unittest discover -s mcp -p 'test_*.py'` for the server checks and
`./tools/check.sh` for Lua integration, mailbox, and shared undo tests.

## Build on the Afterimage showcase

Ask `game_capabilities` for the supported workflow. In an **empty** configured
project, call `game_scaffold` with `{"template":"afterimage"}`. This copies the
complete editable game, art, music, asset credits, tests, browser exporter and
Loupe library. Each scaffold gets a unique LÖVE save identity in `conf.lua`;
point `--bridge-dir` at that identity's `loupe-mcp` folder before live editing.
The default `minimal` template is still available.

The Afterimage template includes the feedback-driven UI and gameplay: centered
semibold buttons, keyboard navigation, high-DPI/fullscreen layout, illustrated
and vector rendering, animated exhaust/lasers/explosions, paired ship weapon
attachments, music/effects controls, opening enemy fire, bounded special drops,
and Story/Endless progression. These remain ordinary editable Lua code rather
than a fixed editor-only scene format.

Reusable library modules are available in every scaffold:

- `require("loupe.sprites")`: `load(path, columns, rows, fps, loop)`,
  `frame(age, fps, count, loop)`, and centered `draw(sheet, age, x, y, width, height, rotation)`.
  Use looping sheets for thrusters and one-shot sheets for impacts.
- `require("loupe.collision")`: `sweepCircle(x0, y0, x1, y1, cx, cy, radius)`
  returns earliest impact time in `[0,1]`, or nil. Include both objects' radii
  in `radius`. This is a projectile helper; use LÖVE's `love.physics` for rigid bodies.
- `require("loupe.window")`: window mode and fullscreen helpers. Afterimage's
  `updateView` and browser wrapper demonstrate scaling and input coordinate mapping.

### Import original or licensed art/audio

Set `--asset-inbox /absolute/path/to/approved-assets` on the MCP server to enable
imports. Without that explicit setting, `asset_import` is disabled. An AI image
service can generate files externally into that folder; Loupe does not include
image-generation credentials or make requests to a service.

```json
{"name":"asset_import","arguments":{"source":"nebula.png","path":"assets/backgrounds/nebula.png"}}
```

Only relative inbox paths and project `assets/` destinations are accepted.
Symlinks, traversal and hidden paths are rejected. Imports are capped at 32 MiB,
never overwrite a file, and support PNG/JPEG, OGG/WAV, and TTF/OTF. The file is
copied as supplied, not transcoded or certified as safe/licensed; review its
content, metadata and usage rights before publishing. `project_assets` lists
assets and PNG dimensions so an agent can check atlas layouts.

Text editing supports Lua, Markdown, text, JSON, GLSL, HTML, CSS, JavaScript and SVG,
including the browser wrapper. Use `project_read` / `project_write` to reference the imported file and record
its origin/license in `ASSETS.md`. Restart for source and asset changes. Use
`loupe_inspect` / `loupe_set` for existing watched values while the game runs;
undo them with `loupe_control` and explicitly save desired overrides. This is
not arbitrary live Lua execution, and saving an override does not rewrite source.

### Verification and export

1. Read the template's `main.lua`, `src/sim.lua`, `src/art.lua` and `ASSETS.md`.
2. Edit via `project_write`; run the included simulation and asset tests locally.
3. Call `game_build` for `dist/game.love`, then `game_launch` for native preview.
4. Inspect the watched roots, make a reversible tweak, undo it, and capture
   `loupe_screenshot`. Play-test keyboard/mouse input and collisions as well.
5. For browser export, install the pinned love.js builder described in the
   example README, then run `python3 tools/build_web.py dist/game.love dist/web
   --builder /path/to/love.js` from the scaffold. The exporter is Afterimage-specific.

The native MCP bridge is not exposed in the browser. `game_build` does not
install dependencies, publish to GitHub/itch.io, or audit assets for private
content. Site layout, glowing embed borders and screenshot lightboxes belong
to `site/`, not the game runtime. Balance tests are deterministic regression
checks, not evidence that every human player or every endless wave is balanced.

### Where to make each kind of change

| Feedback / feature | Editable source in the Afterimage template | Live feedback |
| --- | --- | --- |
| Enemy firing, red shots, difficulty, drop limits, upgrade stats | `src/sim.lua` and `src/art.lua` | Watch `game`; run `tests/sim_test.lua` and `tests/run_test.lua` |
| Ship attachments, art toggle, exhaust and effect sheets | `src/art.lua`, `src/sprites.lua`, `assets/` | Watch `art`; run `tests/assets_test.lua`; capture both art modes |
| Background choices and image import | `src/backdrops.lua`, `assets/backgrounds/` | Watch `backdrops`; native file drop or MCP asset import |
| Music/effect volume and playback | `src/audio.lua`, `assets/*.ogg` | Watch `sound`; check audibility in a real window |
| Button weight, centering, focus and input mapping | `main.lua`, `src/art.lua` | Native keyboard/mouse test; screenshot at multiple sizes |
| Fullscreen, resize and high-DPI | `conf.lua`, `main.lua`, `loupe/window.lua`, `tools/web/` | Check native and browser separately |
| Embedded Play button and page presentation | Repository `site/` and template `tools/web/` | Rebuild the showcase and inspect the page |

The tools provide the authoring/editing loop; they do not automatically judge
visual quality, musical balance, accessibility, or gameplay difficulty.
