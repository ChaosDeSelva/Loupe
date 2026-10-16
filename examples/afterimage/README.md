# AFTERIMAGE · The Glass Reach

A free space shooter and an editable Loupe example. Three short sectors or an Endless flight.

## Run

From the Loupe repository: `love examples/afterimage` (LÖVE 11.5).
From the standalone source download: `love .`.
Build portable examples with `./tools/build.sh afterimage`; open `dist/afterimage.love` with LÖVE.

Your ship auto-targets nearby enemies. Collect salvage, return to the dock, and install upgrades.
Purchases apply immediately, with before/after values and highlighted live stats. Earned levels and
purchases carry between sectors. Endless mode repeats with more enemy health and bounded wave sizes;
a boss returns every third sector. Late-cycle balance remains experimental.

| Control | Action |
| --- | --- |
| WASD / arrows | Move |
| Space | Repulsor pulse; eight-second cooldown |
| Tab | Pause and open art/audio controls |
| V | Switch Illustrated / Vector artwork live |
| B | Choose another backdrop |
| R | Reduce background motion |
| M | Mute/unmute |
| [ / ] | Music volume |
| - / = | Effects volume |
| F11 | Fullscreen (also available on the web launch screen) |
| F1 | Loupe inspector |

Turbo pickups increase speed for seven seconds, prism pickups add a beam for nine seconds,
and hull patches restore eight health. Temporary boosts end at docking. New runs reset progression.

## Change the game with Loupe

Inspect `game.player` for damage/speed/beam count, `art.illustrated` for the live style toggle,
`sound` for the two volume buses, or `backdrops.reducedMotion`. Loupe edits are undoable with
Cmd/Ctrl+Z and saved explicitly. Shop purchases are gameplay actions, not editor history.

For AI editing, configure the repository's `mcp/server.py` with `--project` pointing to this
example and launch with `--mcp`. See [MCP setup](../../docs/mcp.md). The desktop bridge supports
bounded inspection, source edits, building, screenshots and shared undo. It does not generate art
by itself: use your assistant's image tools, then import the resulting assets.

## Import art

Add PNG/JPEG files under `assets/backgrounds/` and restart. Desktop builds also accept a dropped
PNG/JPEG: it is copied into `imported-backgrounds/` inside the LÖVE save directory and shown immediately.
Limits: 8 MB per import, 4096 × 4096 pixels, eight loaded backgrounds. Consecutive sectors avoid the
same background when alternatives exist. Imported files are private local state and are never
included in source releases. Only import files you have permission to distribute.

Browser builds use packaged images; adding an image requires a rebuild. Native file-drop importing
is not promised in browser exports. Images receive a dark scrim for projectile readability.

## Sprite sheets and collisions

`src/sprites.lua` loads uniform grid atlases and supports frame rate, looping, one-shot completion,
rotation and output size. The laser atlas is 2 × 2 (16 fps); explosion atlas is 4 × 4 (24 fps).
Replace the PNG and adjust those grid values in `src/art.lua` for your own sheet.
`sprites.frame` is pure Lua and can be tested without LÖVE.

`src/physics.lua` supplies swept circle collision so fast projectiles cannot skip enemies between
frames. The simulation chooses the earliest impact. This shooter does not use rigid-body physics;
LÖVE's separate `love.physics` module is available for games needing Box2D bodies, joints and gravity.
Loupe can inspect the plain Lua state you expose around those systems.

## Source map

- `src/sim.lua`: deterministic gameplay, progression, pickups, collision integration.
- `src/art.lua`: generated sprites and procedural vector alternatives; identical game rules.
- `src/backdrops.lua`: image catalog, imports, crossfades, parallax and star layers.
- `src/audio.lua`: three music tracks, sound effects and separate volume controls.
- `src/sprites.lua`, `src/physics.lua`: small reusable rendering/collision helpers.
- `main.lua`: input, screen flow, HUD and shop. Rendering does not change the simulation.

Run `luajit tests/sim_test.lua`, `luajit tests/run_test.lua`, and `luajit tests/assets_test.lua`
from this directory. The repository quality gates also run these.

## Web export and music sources

From the repository root:

```sh
npm install --prefix .webtools love.js@11.4.1
python3 tools/build_showcase.py --builder .webtools/node_modules/.bin/love.js
python3 -m http.server 8000 --directory site
```

The Pages workflow runs that same build. Its exporter provides a full-window canvas, device-pixel
resolution up to DPR 2, browser fullscreen and click-to-start audio. The playfield preserves its
aspect ratio, with a decorative backdrop filling remaining screen space. No external footer is shown.
The browser runtime is love.js 11.4.1 in compatibility mode; native target is LÖVE 11.5.

`python3 tools/compose_music.py` regenerates three original stereo WAV tracks. Encode each with
`ffmpeg -i assets/NAME.wav -c:a vorbis -strict experimental -q:a 4 assets/NAME.ogg`.
The score is mastered consistently; music and effects default to 85% and are adjustable while playing.

## Reuse and credits

Code, original compositions and procedural artwork: MIT (LICENSE).
AI-generated logo, backgrounds, sprites, icons and atlases: supplied under the same project license
for any rights we hold; see ASSETS.md for provenance and prompts. No stock assets or reference-game
art, audio or source are included. No claim is made that generated artwork is exclusive.
Loupe: MIT. Inter/JetBrains Mono fonts: SIL OFL (`loupe/fonts/OFL.txt` in packaged downloads;
repository copy at `../../loupe/fonts/OFL.txt`). Web runtime notices accompany the web export.

### Display, sprites, and combat testing

The native game supports F11 desktop fullscreen, F10 window presets (960×600,
1280×800, 1440×900, 1920×1200), and free resizing. The optional `loupe.window`
module exposes `toggleFullscreen()`, `setSize(width,height)` and `cycleSize()` for
other games. The browser wrapper renders at device pixel ratio up to 2; UI fonts
are rasterized for the current scale instead of stretching a small bitmap.

`src/sprites.lua` loads grid sprite sheets with fractional cell boundaries,
looping or one-shot playback, rotation, and scale. Laser, explosion, and default
exhaust animations use it. `art.loadout` layers weapon pods and boosters under a
shared ship transform, allowing beam counts and turbo to combine. Collision is
swept-circle projectile detection in `src/physics.lua`; LÖVE provides full rigid
body physics separately. Loupe is an inspector/toolkit, not a replacement for
LÖVE's renderer or physics engine.

Enemy projectiles are red pointed bolts; friendly fire is cyan. Upgrade-card
icons have fixed padding. Rank increases raise upgrade prices. The story boss
has two firing phases; Endless scales enemy health, shot speed, and firing rate,
with bounded spawn counts and movement speed.

Run `love examples/afterimage --playtest` from the repository for a rendered
three-sector test with audio, particles, the boss, purchases, and both art modes.
It uses an automated pilot without invulnerability. Because difficulty is real,
a pilot death is reported as a failed play-test rather than hidden.
Run `luajit tests/balance_report.lua` inside this example for seeded stationary
and active-pilot benchmarks. These measure regressions, not human enjoyment.

### Reuse through MCP

The local MCP server can create this entire example in an empty project with
`game_scaffold({"template":"afterimage"})`. Read [the authoring workflow](../../docs/mcp.md)
for asset import, live edits, undo, screenshots, and browser-export limits.
The `src/sprites.lua` and `src/physics.lua` compatibility modules now delegate
to `loupe.sprites` and `loupe.collision`, which are included in every scaffold.
