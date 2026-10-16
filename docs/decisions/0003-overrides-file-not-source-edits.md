# 0003: Persist edits to an overrides file, never to game source

- Status: accepted
- Date: 2026-10-09

## Context
Edits made in the inspector need to survive restarts. Rewriting the host game's Lua source is
fragile (values are often computed, shared, or built in loops) and would make loupe a risk to
the user's code. Also, `love.filesystem` can only write to the save directory, not the game
folder.

## Decision
Edits are saved to `loupe_overrides.lua`, a data file that returns a table keyed by watched-root
name and field path. `loupe.watch` applies matching overrides at startup. When the game runs
unfused from a folder, the file is written next to `main.lua` with `io.open`; otherwise it falls
back to the save directory and prints the path.

### What loading the file guarantees (corrected in 1.1)
The file is Lua, loaded with `loadstring` and run by `storage.parse`. Earlier wording called this
a sandbox that means the file "can only be data". That overstated it. What 1.1 guarantees:
- Precompiled bytecode (text starting with `\27`) is refused. Bytecode isn't verified by the VM
  and can corrupt memory.
- The chunk runs with an empty environment, so it can't reach globals (`os`, `io`, `require`,
  the game, `love`).
- It runs under an instruction limit (`storage.MAX_INSTRUCTIONS`, 1e6) via a count hook, with
  LuaJIT's compiler turned off for the chunk (compiled code never calls hooks). An endless loop
  becomes a load error. Any debug hook set before is put back afterwards.

What it doesn't guarantee: string methods are still reachable through the string metatable
(`("x"):rep(1e9)` can exhaust memory), and memory use isn't limited. The file lives in the
game's own folder or save directory, so whoever can write it can usually edit the game's code
anyway; the checks are there to stop accidents and keep the game running, not to contain a
hostile file.

Saving writes a temp file next to the target and renames it over the old file, so a failed
write never leaves a truncated overrides file.

Only fields reached through string or finite-number keys are saved. Edits through other keys
(functions, tables, userdata, booleans) still apply and undo, but loupe says it can't save them.

## Consequences
- Host source is never touched; deleting the file reverts all tweaks.
- Users copy values into their source manually when they want them permanent (the file is
  readable Lua to make this easy).
- Paths into arrays (`rocks[3]`) aren't stable across runs, so overrides are best for tuning
  values on named objects. We'll document this in M5.
