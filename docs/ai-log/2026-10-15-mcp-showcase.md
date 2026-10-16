# MCP and Afterimage showcase — local preview

Added an opt-in local mailbox bridge and a Python stdio MCP server with twelve tools:
project authoring, launch/build, bounded inspection, scalar edits, shared undo/save, and screenshots.
The Lua inspector remains usable with no Python dependency. The bridge polls while paused.

Tests cover the pure remote adapter, malformed/expired/stale mailbox requests, default-off
behavior and paused lifecycle; six Python tests cover protocol, paths, backups and packaging.
A real LÖVE process was driven through stdio to inspect/edit speed, undo/redo, pause/step,
capture a screenshot, resume, read source and build a .love archive.

Integration caught and fixed a hidden-overlay branch that incorrectly closed the bridge.
Browser QA also found redundant transition drawing in update; drawing now stays in draw.
The host's FFmpeg lacks libvorbis; the soundtrack was encoded with its built-in Vorbis encoder.

Afterimage is an original three-sector auto-targeting shooter with an optional Endless mode,
illustrated upgrades, temporary turbo/prism pickups, salvage extraction and original synth music.
The native simulation tests include three complete bot-driven story runs. Browser QA verified
launch, Endless selection and the F1 inspector. Late-cycle difficulty still needs human playtesting.

Everything remains local at the user's request. No GitHub repo, Pages deployment, or itch listing
was published. Historical logs are preserved as evidence of prior work, not new test claims.

## Illustrated showcase and combat correction

Added original generated backgrounds, logo, icons, ships, weapon attachments,
laser/explosion/exhaust sheets, and three original synthesized music tracks.
The example now includes a live vector/illustrated toggle, bounded image imports,
independent audio volume, and a custom high-DPI web player. Native window presets
are an explicit opt-in helper, leaving host window ownership unchanged.

The user found a first-kill crash after an early browser preview. The generated
explosion PNG was 1254 square, not the assumed divisible-by-four size. The loader
assertion failed only when its lazy asset was first used. Corrected the loader
to accept fractional quad boundaries, added tests reading the actual PNG headers,
and preloaded all animation atlases. Added a real rendered combat play-test;
simulation-only tests had not covered graphics initialization.

User feedback also caught oversized shop icons, indistinct enemy shots, flat
thruster shapes, and an easy boss. Cards now have padded icons, hostile bolts are
red, and modular weapon/engine layers combine with animated exhaust. Boss health,
firing patterns, escalating upgrade prices, and Endless scaling were tuned using
30-seed stationary/active-pilot benchmarks. Not every automated pilot wins; tests
now distinguish legitimate defeat from a non-resolving run.

Fullscreen QA found that changing only HTML canvas dimensions left SDL rendering
at the previous size. The web exporter now exposes Emscripten's in-memory FS for
a dimensions mailbox; the game uses `updateMode` from its draw callback so resizing
also works while the inspector pauses simulation. HTML owns fullscreen and its
Escape/F11 exit path; a narrow pinned-runtime patch prevents SDL's resize from
exiting HTML fullscreen. Verified a 6720×2836 backing buffer on a 3360×1418 display
and correct recentering on return to windowed mode. Runtime patches have exact
anchor-count assertions and require review when upgrading love.js.
