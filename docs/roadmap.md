# Roadmap

One milestone at a time. Each ends with green CI, an ai-log entry, and human review in the
example games.

| # | Milestone | Done when |
|---|---|---|
| **M0** | Foundation: tooling, CI, AI review, process docs, `examples/asteroids` | Gates green; asteroids runs |
| M1 | Hook + clock + overlay shell: F1 toggle, pause/step/time scale, headless no-op | Game unaffected while closed; detach restores callbacks |
| M2 | Own immediate-mode UI toolkit + `examples/ui_gallery` | Widgets unit-tested through the command list |
| M3 | Registry + inspector panel: `loupe.watch`, tree, live field editing | Edit `ship.thrust` live in asteroids |
| M4 | In-world selection: bounds chain, camera/letterbox hooks, drag; `examples/platformer` | Picking correct under camera + letterbox |
| M5 | Undo/redo + save to `loupe_overrides.lua` | Edits persist across restarts |
| M6 | Hot reload with in-place function patching | Live code edits without restart; failed reload keeps running |
| M7 | Release 1.0: API docs, README, changelog, rockspec, case study | Gates green; tagged `v1.0.0` locally |
| 1.0 polish | Leaf nodes, text cursor, click-to-cycle, off-screen culling, stale selection, key repeat | Specs green; checked in real LÖVE |
| **1.1** | | |
| 1.1 hardening | Callback chaining, unsavable keys, error boundary, bounded world scan, safer overrides file, getter-root undo, shortcuts while typing, require-path reload | Specs green (377); smoke run in real LÖVE owed |
| 1.1 examples | Fullscreen/HiDPI/resizable; polished asteroids and platformer; new tunables (`fx`, `sound`, ...) | Gates green; looked at in real LÖVE |
| 1.1 UI redesign | Docked full-screen layout, clean dark theme, `uiScale`/theme options | Merged; checked in real LÖVE |
| 1.1 clean-code pass | Review of the merged 1.1 code against the quality bar | Gates green; ai-log entry |
| **1.1.1** UI finish | One-line display of control characters, clean drag values, selection and clipboard, no leaked key releases or hotkey text; docs | Specs green (550); checked in real LÖVE |

Status: **1.1.1 released locally** (2026-10-09): UI finish (one-line strings, clean drags, selection and clipboard, no leaked key releases), shortest-form number saving, plain Lua 5.1 and Linux verified (Docker, real LÖVE 11.5 under Xvfb), fullscreen verified in real LÖVE on macOS, docs complete. The maintainer has not yet confirmed the manual checklists in `docs/manual-test.md`. Kept local: no remote, nothing published.
