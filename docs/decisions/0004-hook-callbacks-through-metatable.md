# 0004: Wrap love callbacks through a metatable, not by replacing fields

- Status: accepted
- Date: 2026-10-09

## Context
loupe must run around the game's `love.update`, `love.draw` and input callbacks. The obvious
approach (save `love.update`, assign a wrapper) breaks for games that switch scenes by
reassigning callbacks (`love.update = menu.update`): the wrapper is silently dropped and the
overlay disappears.

## Decision
`loupe/core/hook.lua` moves the wrapped callbacks off the `love` table and serves them through a
metatable. `__index` returns loupe's wrapper; `__newindex` stores whatever the game assigns as
the new "original" the wrapper calls. Other fields on `love` are untouched. `detach` removes the
metatable and puts the game's current callbacks back as plain fields.

### Chaining (added in 1.1)
Some code wraps a callback after `attach` runs: `local old = love.update; love.update =
function(dt) old(dt) ... end`. `hump.gamestate.registerEvents()` does exactly this from
`love.load`, which runs after `attach`. `old` is then loupe's wrapper, so the wrapper calls the
new function, which calls the wrapper, and so on until the stack overflows.

The rule: when a function is assigned, `__newindex` remembers what it replaced (`prev[fn]`, the
first time `fn` is assigned). While the wrapper runs a game function, it tracks that function as
the chain's current link. If the wrapper is called again while a link is running, that is the
link calling what it replaced: the wrapper calls `prev[link]` directly (making it the current
link), without running loupe's logic again. Chains of any depth (A wraps B wraps the original)
unwind one link per re-entry. A link whose `prev` was "nothing" ends the chain quietly. Assigning
the wrapper to itself (`love.update = love.update`) is ignored.

After `detach`, the game's current callback is put back as a plain field. Functions in it still
hold the old wrapper; the detached wrapper treats any call as coming from that chain and passes
straight through to `prev`, so the game's chain keeps running exactly once per call.

## Consequences
- Reassigning callbacks at runtime keeps working and stays wrapped.
- loupe installs wrappers for callbacks the game never defined (e.g. `keypressed`), so the F1 key
  works in any game.
- `rawget(love, "update")` returns nil and `pairs(love)` won't list wrapped callbacks while
  attached. No known game relies on either.
- If something else has already set a metatable on `love`, `attach` fails loudly instead of
  guessing how to chain with it.
- Chaining works (see above), with two limits: a function's `prev` is fixed at its first
  assignment, and if a game callback throws through the wrapper, the "current link" marker isn't
  reset. LÖVE stops the game on such errors, so this only matters to a custom `love.run` that
  catches them; loupe doesn't `pcall` the game's callbacks because that would spoil the
  traceback the game's author sees.
