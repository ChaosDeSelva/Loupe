# loupe: instructions for AI contributors

loupe is a drop-in live inspector/editor for LÖVE 11.5 games. It is also a public case study in
AI-written code meeting a strict quality bar, so **how** code gets written matters as much as
what it does. Read `docs/AI.md` for the process.

## Architecture rules (enforced by review; some by CI)
- `loupe/` is the only shipped folder. **Zero dependencies.** Never vendor libraries into it.
- `loupe/core/` is pure Lua: no `love` references at all (CI greps for it). Anything that needs
  LÖVE goes in `loupe/init.lua` or `loupe/ui/render_love.lua`.
- The UI is immediate-mode and emits a list of draw commands. **Only `ui/render_love.lua`
  calls `love.graphics`.**
- Never write state onto the `love` table or create globals. Host games already use `love.*`
  for their own fields.
- Do nothing when `love.graphics` is nil (headless runs).
- Never rewrite a host game's source files. Persist edits to `loupe_overrides.lua`.
- Code must run on Lua 5.1 as well as LuaJIT (CI runs both). No `goto`, no bit ops without
  a fallback, no 5.2+ APIs.

## Style
- StyLua formats (2 spaces, 100 cols, double quotes). luacheck must report zero warnings.
- Module pattern: `local M = {}` … `return M`. Locals over globals; no classes unless state
  truly needs a metatable.
- Comments explain *why*, not *what*. Match the density of surrounding code.
- Names: `camelCase` functions and fields, `UPPER_CASE` constants, `snake_case` file names.

## Tests
- TDD for `core/` and `ui/`: write the failing spec first, then the code.
- Specs live in `spec/`, mirroring `loupe/` paths (`spec/core/clock_spec.lua`).
- Use `spec/support/love_stub.lua` for anything that touches `love`; assert on recorded calls.
- Coverage gates: `core/` ≥ 90%, `ui/` ≥ 80%.

## Before saying anything is done
Run `./tools/check.sh` (StyLua, luacheck, core purity grep, busted + coverage) and smoke-run
the touched examples with `love examples/<game> --smoke 120`. Run only one LÖVE process at a time.

## Process
- One milestone at a time (see `docs/roadmap.md`). Stop after each milestone for human review.
- Each milestone ends with `docs/ai-log/M<n>.md`: what was built, what the gates or reviews
  caught, what the human corrected. Be honest; the log is the evidence.
- Record non-obvious design decisions as ADRs in `docs/decisions/`.
