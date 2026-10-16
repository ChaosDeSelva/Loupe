# 0007: Hot reload patches modules in place and keeps the game's runtime data

- Status: accepted
- Date: 2026-10-09

## Context
Hot reload should let a developer edit `src/ship.lua` and see the change without restarting.
Three forces pull against each other:

- **Identity.** Games capture modules (`local ship = require("src.ship")`) and give instances
  metatables that point at them (`Ship.__index = Ship`). Swapping in the new table would leave
  every existing reference on the old code, so the old table has to be changed in place.
- **Runtime data.** Module tables also hold state the game changed while running (a high score,
  a counter, a value tuned in loupe's Inspector). Blindly copying the file's values back would
  reset them on every save.
- **Safety.** A typo must not crash the game, and patching must never reach into tables that
  belong to another module.

## Decision
- `loupe/reload.lua` polls at most every 0.5 s of real time (so it keeps working while paused).
  It watches loaded modules whose `name/with/dots.lua` or `.../init.lua` exists in the game's
  filesystem and reloads one when its `modtime` increases. Loading and running happen inside
  `pcall`; a failure keeps the old code, is printed, and shows as a warning in the toolbar.
  The new modtime is recorded even on failure, so a broken file is retried when saved again.
- Never reloaded: `loupe` and `loupe.*`, `main`, `conf`, and anything matching
  `attach({ reloadIgnore = { patterns } })`. Modules that aren't tables can't be patched in
  place and are skipped. On by default only when running unfused from a folder
  (`storage.sourceFolder()`); `attach({ hotReload = false })` turns it off.
- `core/hotswap.patch(old, new, previous, shared)` merges in place:
  - **functions** are always replaced;
  - **tables present in both** are patched recursively, keeping the old table's identity;
    references to any new table (including `Class.__index = Class`) are remapped to the old
    table it was paired with; cycles are handled;
  - **other values** are taken from the file only if the file changed them: `previous` is a
    deep snapshot of the version of the module loaded last time (or, for the first reload, of
    the module when loupe started watching it). If the new value equals the previous one, the
    game's current value stays;
  - **removed keys** are removed only if the previous version defined them, so keys the game
    added at runtime survive;
  - **shared tables** (every table in `package.loaded`) are opaque: never patched, walked or
    copied, and compared by identity. `M.level = require("levels.one")` can't overwrite another
    module's contents, even if the game later points `M.level` somewhere else;
  - metatables are left alone.
  Without `previous`, every value is taken from the file (the simple rule).

## Consequences
- Editing a function, a constant like `THRUST = 300`, or a nested tuning table takes effect on
  save, and existing instances pick up new methods.
- Runtime state in module tables survives reloads that don't touch it, and loupe Inspector
  edits survive unless the file changes that same value. If the file changes a value the game
  also changed, the file wins.
- The first baseline is taken when loupe starts watching (at `attach`, or at the first check
  after a lazy `require`). Runtime changes made before then look like file values; this only
  matters if the first reload changes that same value.
- Local variables and upvalues inside the old module (`local speed = 10` at file scope) are not
  patched; old closures keep their old upvalues until replaced. Code that ran once at load
  (registering callbacks, creating objects) runs again on reload. Module files with
  side effects need `reloadIgnore`.
- Values compared by `~=`, so a `0/0` field always counts as changed.
- Polling `getInfo` for each tracked module twice a second is cheap for typical games; a game
  with hundreds of modules may want `reloadIgnore` for vendored libraries.
