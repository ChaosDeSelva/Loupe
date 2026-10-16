# Contributing to Loupe

Bug reports, small fixes, and example games are welcome. For bugs, include your OS,
LÖVE version, reproduction steps, and a small game that demonstrates the problem.

## Development setup

Install LÖVE 11.5, LuaJIT, StyLua 2.5.2, and LuaRocks configured for Lua 5.1/LuaJIT.
Install `busted`, `luacheck`, and `luacov` into that LuaRocks environment. Make its `bin`
directory available on PATH. A Lua 5.4/5.5 installation is not the test target.

```sh
./tools/check.sh
./tools/build.sh
love examples/asteroids --smoke 120
love examples/platformer --smoke 120
love examples/ui_gallery --smoke 120
love dist/asteroids.love --smoke 120
love dist/platformer.love --smoke 120
love dist/ui_gallery.love --smoke 120
```

Run LÖVE processes one at a time. For Linux, LuaJIT, and plain Lua 5.1 verification
with a running Docker daemon, use `./tools/ci-docker.sh`.

Keep the shipped `loupe/` folder dependency-free. `loupe/core/` stays pure Lua;
rendering belongs in `loupe/ui/render_love.lua`. Preserve Lua 5.1 compatibility.
Add regression tests for behavior changes. Coverage gates require 90% for core and
80% for UI. See [CLAUDE.md](CLAUDE.md) for detailed architecture and style conventions.

## Repository layout

- `loupe/`: the library users copy into games
- `examples/`: two playable games, a UI gallery, and shared helpers
- `spec/`: automated tests
- `tools/`: quality gates and reproducible example builds
- `docs/`: API, usage, design decisions, and historical development notes
- `site/`: the static GitHub Pages landing page
- `dist/`: generated builds, ignored by Git

Use one source tree; keep generated archives and extracted releases outside the repository.

## Website

The `pages.yml` workflow deploys only `site/` to GitHub Pages on pushes to `main`.
Enable **Settings → Pages → Source → GitHub Actions**. Preview locally with
`python3 -m http.server 8000 --directory site`.

AI-assisted contributions are welcome and held to the same checks. Describe what changed,
why, and what you actually tested in your pull request.
