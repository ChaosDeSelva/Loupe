# Can AI-written code be clean? A case study

> Built only from `docs/ai-log/*.md`, the ADRs in `docs/decisions/` and the git history. M0–M5
> were written by one agent; M6, the 1.0 polish pass and the docs (M7) were written by three
> agents in parallel and then merged, integrated and verified by the lead agent. Numbers the
> sources don't contain are marked "not recorded".

## Setup

loupe is a drop-in inspector/editor for LÖVE 11.5 games, written in Lua by an AI coding agent
(Claude Code, Opus 5.5) with a human maintainer who scopes milestones, reviews and approves. The
question: can AI-written code meet the bar a careful human reviewer would set, and what does it
take to get there?

The bar (`docs/AI.md`, `CLAUDE.md`), applied to every line regardless of author:

- StyLua formatting; luacheck with **zero** warnings.
- Architecture rules: `loupe/core/` never references `love` (grep gate); only
  `ui/render_love.lua` calls `love.graphics` (ADR 0002); zero dependencies (ADR 0001); no globals,
  nothing written onto `love`; host source never rewritten (ADR 0003).
- Test-first for `core/` and `ui/`, with busted on Lua 5.1 and LuaJIT.
- Coverage gates: `core/` ≥ 90%, `ui/` ≥ 80%.
- A real-LÖVE smoke run of each example (`--smoke N`).
- AI review and human review; a log per milestone recording what was built, what the gates and
  reviews caught, and what the human corrected.

How it actually ran: the project was kept local by maintainer decision, so the GitHub workflows
(gates on two runtimes, xvfb smoke job, Claude review) were written but **never executed**
(M0, M1). `./tools/check.sh` was the gate of record. Real-LÖVE verification was done by the agent
with scratch harnesses outside the repo that scripted input and took screenshots (M1–M5).

## Numbers per milestone

From the logs. "Library" and "specs" are line counts as the logs report them.

| Milestone | Specs | `core/` coverage | `ui/` coverage | Library lines | Spec lines | luacheck |
|---|---|---|---|---|---|---|
| M0 Foundation | 5 | n/a (no `core/` files) | n/a | ~480 Lua lines in the whole repo (library is a version stub) | (included) | 0 warnings |
| M1 Hook, clock, overlay | 40 | 100% | n/a (no `ui/` files yet) | not recorded | not recorded | 0 ("green on the first full run") |
| M2 UI toolkit | 97 | 100% | 99.3% | 1,189 | 1,235 | 0 warnings |
| M3 Registry, inspector | 141 | 98.8% | 99.5% | 1,570 | 1,691 | 0 (after fixing W431) |
| M4 World picking | 171 | 99.3% | 99.5% | 1,812 | 2,007 | 0 across 48 files |
| M5 Undo, overrides | 230 | 99.4% | 99.5% | ~2,400 | ~2,600 | 0 across 58 files |
| M6 Hot reload (branch) | 281 | 99.66% | 99.54% | not recorded | not recorded | 0 across 62 files |
| 1.0 polish (branch) | 272 | 99.46% | 99.60% | ~2,680 | ~3,130 | 0 across 59 files |
| **1.0.0 (merged + integrated)** | **330** | **99.7%** | **99.6%** | **3,068** | **3,872** | **0 across 63 files** |

Spec lines stayed at roughly 1.0–1.1x library lines from M2 onward. Panels (`loupe/panels/`) sit
outside the coverage gate but have their own specs (18 as of M3).

Git history: the whole of M0–M5 is a **single commit** (`f474ced`, 2026-10-09, "loupe M0-M5:
inspector, world picking, undo and saved overrides", 85 files, 6,914 insertions). All six logs are
dated the same day. Git therefore can't independently confirm the per-milestone sequence or the
test-first claims; those rest on the logs alone.

## Every defect caught, by what caught it

### By a spec (unit or integration test)
- **M2: typing order.** Text and keys within one frame were applied in separate passes, so
  "backspace, backspace, 3" on "10" gave "1" instead of "3". Fixed with one ordered event list.
- **M4: a crashing test hook exposed an API contract.** The picker spec's `bounds` hook indexed
  `o.pos` on every table, including `pos` itself. Real hooks also see every table, so the contract
  "return nil for tables you don't recognize" was written into `geometry.lua`, `init.lua` and
  ADR 0006.
- **M5: status text cut off.** An integration spec showed "1 saved override no longer matches the
  game" truncated to "1 saved over.." on a row shared with three buttons. Status got its own row.
- **M5: two bugs in the AI's own specs**, a leftover `draw` call that wasn't reset and
  `fake.calls = {}` replacing the table the stub records into. (The log doesn't say exactly how
  they surfaced; presumably while running the specs.)

### By a gate
- **M0: StyLua** rejected a 104-column line in `tools/coverage_gate.lua`, over the 100-column limit
  the AI had configured minutes earlier.
- **M3: luacheck W431**, a shadowed local `step` in the tree-node specs; the zero-warning rule
  stopped the run.
- **M5: an edit script's own assertion** stopped a scripted edit partway, because StyLua had
  reformatted the line it matched, before any partial write. (A safeguard in the agent's tooling
  rather than a project gate.)

### By the AI rereading its own work
- **M2: a garbled expression** in the widget fill-color helper
  (`hovered and c.widget == nil and c.widget`), rewritten as a plain if/elseif.
- **M2: a circular require** between `context.lua` and `widgets.lua`, avoided by design (UTF-8
  helper moved to its own module).
- **M2: a status overclaim.** M1's log was first marked "reviewed by maintainer" when the
  maintainer had only said to move on.
- **M3: a false positive in `isColor`**, which accepted `{[2]=1, [3]=1, [4]=1}`. A failing case
  went into the spec first, then the check was tightened.
- **M3: a test that couldn't fail.** It asserted that "r" appeared after expanding a color, but
  the window title "Inspector" already contains an "r".
- **M3: a double scan** in the Objects panel, rewritten to collect child tables once.
- **M4: an assertion that couldn't fail**, `assert.equal(4, list[1].h or 4)`.
- **M4: a `require` inside `picker:frame`**, moved to the top of the file.
- **M5: a data-corruption bug in the serializer.** It used `#v` on tables with holes, where `#` is
  unspecified; on LuaJIT a 4-element table with `[2]` cleared reports 4, so values would have
  loaded back at the wrong indices. The first two test attempts didn't fail because their tables
  happened to report length 1; probing both runtimes found a case that does. Fixed with `ipairs`.
- **M5: a wrong expectation** about sort order (`["two words"]` vs `["end"]`), fixed before
  running.
- **M5: duplication avoided.** A list-append helper about to be copied into three files became
  `reflect.childKeys`.

### By a real-LÖVE run
- **M2: clicks landing in the wrong place.** The overlay polled `love.mouse.getPosition()` each
  frame, replacing the position a click happened at. Every unit test passed because the attach
  spec moved the fake mouse to the click point. Scripted clicks in real LÖVE all missed. Fixed by
  taking position from events only (ADR 0005); the spec no longer moves the fake mouse.

### By the environment
- **M0:** macOS has no `timeout`; the first smoke attempt exited 127. Replaced with the games' own
  `--smoke` flag.

### By the human
- **None recorded.** Every log's "Human corrections" section is still the placeholder
  "_(maintainer fills in after review)_". The maintainer steered scope ("keep this all local",
  "do all the milestones ... 1.0", "use subagents") but hasn't reported a code defect. That is
  either a clean result or a gap in the record; the logs can't say which.

### Tally (M0–M5)

| Caught by | Count |
|---|---|
| Spec | 4 (M5's two spec bugs counted as one item) |
| Gate | 2, plus 1 tooling safeguard |
| AI rereading | 11 |
| Real-LÖVE run | 1 |
| Environment | 1 |
| Human | 0 recorded |

Counts are of items as the logs list them, not weighted by severity. The two most serious defects
(click position, serializer holes) were caught by a real run and by rereading, not by the gates.

## Recurring failure patterns

1. **Assertions that couldn't fail (M3, M4).** Twice the AI wrote a test whose assertion was true
   regardless of the code: a substring already present in the window title, and `x or default`
   comparing against the default. Both were caught on reread, not by any tool. Coverage numbers
   don't detect this: the lines run, the assertion just doesn't test anything.
2. **Tests masking bugs (M2).** The pointer-position spec set up the fake mouse in a way that
   made the bug invisible. 97 green specs and 99.3% `ui/` coverage coexisted with a UI where no
   click landed. Only a real-LÖVE run found it.
3. **Relying on unspecified behavior (M5).** `#` on a table with holes. The bug was real on
   LuaJIT, and the first tests written for it passed by luck of the runtime's length choice.
4. **Status overclaims (M2, about M1).** A log said "reviewed by maintainer" when the maintainer
   had only approved moving on. The logs since then say "manual checklist not yet confirmed".
5. **Test-first not always true.** M2's `input_spec` and `layout_spec` were written alongside
   their modules and never seen failing. In M4, two of four new attach specs passed before the
   change. Both were disclosed in the logs rather than claimed as red-first.
6. **Known limitations carried forward.** The game receiving `keyreleased` for keys loupe
   consumed was noted in M1, again in M2, and is still documented as a gap at 1.0.

## What worked

- **Rereading as a deliberate step** caught the most defects, including the most dangerous
  latent one (serializer). The logs show the habit getting more specific over time: from
  "garbled expression" in M2 to probing both runtimes for `#` behavior in M5.
- **Real-LÖVE runs with scripted input and screenshots** caught the one bug that every unit test
  hid, and gave concrete evidence for each milestone's "done when" condition (thrust 220 → 286 in
  M3; a platform dragged 60 screen px = 40 world units through a 1.5x letterbox in M4; a saved
  override surviving a restart in M5).
- **The draw-command architecture (ADR 0002)** made `ui/` testable without a window; `ui/`
  coverage held at 99%+ from M2 on.
- **Zero-warning lint and formatting gates** were cheap and caught their share (M0, M3).
- **ADRs written when a bug changed the design** (0005 after the click bug; 0006's `bounds`
  contract after the M4 spec error) kept the reasons next to the decisions.
- **Honest logs.** Deviations from test-first, unverified CI and unconfirmed checklists are all
  stated in the logs rather than smoothed over.

## What didn't

- **High coverage was not evidence of correctness.** See patterns 1 and 2.
- **CI never ran.** The workflows (two runtimes, xvfb smoke, AI review) are untested assumptions
  (M0). In particular the plain Lua 5.1 job has never run. Locally, the rocks were installed against
  LuaJIT (M0), so the full suite runs on LuaJIT; M5 mentions probing both runtimes for one
  behavior, but **the full suite has never run on plain PUC Lua 5.1**: only LuaJIT is installed
  on this machine. The code avoids 5.2+ APIs by rule, which is not the same as being tested.
- **The human review loop isn't on the record.** Manual checklists for M0–M5 are unchecked and
  the "Human corrections" sections are empty.
- **Git history is too coarse to audit.** One commit for six milestones.

## M6, 1.0 polish and integration (parallel agents)

Three agents worked at once in separate git worktrees: hot reload (M6), a polish pass over the
known limitations, and the 1.0 docs. They had disjoint file scopes (only the M6 agent could edit
`init.lua`) and a written API contract, so the docs could be written against hot reload before it
existed. All three branches merged without conflicts.

### What the agents caught in their own work
- **M6, a data-corruption risk (rereading).** Recursive patching paired tables by key, so if a
  module pointed `M.level` at another module's table, a reload would have overwritten that other
  module's contents. Fixed by treating every table in `package.loaded` as opaque.
- **M6, stale references inside new tables (spec).** Tables only the new version had kept
  pointing at the discarded new module. The first fix still missed nested tables; a spec caught
  that before commit.
- **M6:** luacheck W212 (unused `self`); one StyLua reflow.
- **Polish, a regression from row culling (integration spec).** The auto-height toolbar culled
  its own status row on its first frame. Fixed by never culling auto-height windows.
- **Polish, a too-loose spec.** A scroll test searched for "row 1", which also matched "row 10"
  through "row 19". It now uses an exact match.

### What the lead caught while merging and integrating
- **The gates broke because of the worktrees (gate).** luacheck and StyLua scanned the agents'
  worktree copies under `.claude/`, where the per-folder lint rules don't apply. The gate failed
  until `.claude/` was excluded.
- **Inspector edits to world-picked objects were never saved (integration spec, written while
  wiring the stale flag).** Since M4, picking in the world copied only `value` and `path` into the
  selection and dropped `root` and `keys`, so those edits were undoable but missing from
  `loupe_overrides.lua`. This shipped through M5 because no test covered "pick in the world, edit
  in the Inspector, save". Fixed, with that test.
- **A test sequencing mistake (lead's own spec).** A press and a move were sent before the frame
  that processes the press, so the press was hit-tested at the moved position. Real mouse input
  always has a frame in between; the spec was fixed, not the code.
- **A vacuous pass, noted rather than counted.** "Restores key repeat if the overlay closes
  mid-edit" passed before the feature existed, because nothing had turned repeat on yet. It only
  became meaningful afterwards.
- **Doc/code mismatches the docs agent found:** the version was still `0.0.0`; the `loupe.ui`
  header example passed `font.getWidth` (a method) as a plain function, which would get the text
  as `self`; and the docs still described CI that has never run and a "v0.1" target. All fixed.

### Verified in real LÖVE by the lead (one process at a time)
- Hot reload: editing `src/ship.lua` in a running copy of asteroids recolored the ship within
  half a second ("reloaded src.ship"). Saving a syntax error kept the game running on the last
  good code and showed "reload failed: src.ship: Syntax error ...".
- Text cursor: Left, Left, `X` turned "Fjord ranger" into "Fjord rangXer".
- Saved overrides survived a process restart (M5). Leaf nodes showed without arrows.
- All three examples pass `--smoke`.

### Did the patterns recur?
- **Assertions that can't fail:** yes, in a milder form. The polish agent's "row 1" match and the
  lead's vacuous key-repeat test. Both were noticed and recorded.
- **Tests masking bugs:** yes. The world-pick save bug sat behind specs that each tested half of
  the path (picking, and saving Inspector edits) but never the two together.
- **Overclaims:** the agents reported vacuous and post-hoc specs explicitly, and the docs agent
  flagged its own unverified claims about hot reload for the lead to check. No overclaim was
  found in the M6, polish or M7 logs.

## 1.1: an independent review, then eight agents

### The review found what 330 green specs didn't
After 1.0 shipped, a fresh reviewer agent read the whole codebase with no session history. It
found two bugs that crash the **host game**, both reproduced with small scripts:
- **Callback chaining.** Code that chains `love.update` after `attach` (exactly what
  `hump.gamestate.registerEvents()` does from `love.load`) made loupe's wrapper and the game call
  each other until the stack overflowed. Every 1.0 spec assigned callbacks; none chained them.
- **Unsaveable keys.** Editing a field reached through a userdata or function key (common with
  physics bodies) threw inside `love.draw` while building the overrides entry.

It also found that nothing protected the game from loupe's own errors (user hooks, strict
tables), that panels kept their first-frame size forever, that per-frame walks were unbounded in
the number of tables visited, and that the overrides "sandbox" accepted bytecode, so ADR 0003's
safety claim was false. None of this was visible to the gates: coverage was over 99%.

**Lesson:** high coverage measured the paths the authors imagined. An independent reader with a
"never crash the host" brief imagined different ones.

### Building in parallel
Eight agents across two rounds, each in its own git worktree with a written file-ownership
boundary: hardening, the UI redesign (the only one allowed to launch LÖVE), examples, a
clean-code pass, and docs, plus the reviewer. Four of the five merges were conflict-free. The
fifth (UI redesign onto hardening) conflicted in one line of `init.lua` and one spec file.

### What only the merge revealed
Each branch was green on its own. Together they had an interaction bug: hardening's error
boundary rebuilt the UI context after an error, but the redesign only reapplied the theme when
the UI scale changed, so a rebuilt UI would have silently lost its theme and fonts. Neither
agent could have seen it; the lead found it reading the conflict. File ownership prevents edit
collisions, not semantic ones.

### Numbers
| | 1.0.0 | 1.1.0 |
|---|---|---|
| Specs | 330 | 495 |
| `core/` coverage | 99.7% | 99.5% |
| `ui/` coverage | 99.6% | 99.6% |
| luacheck | 0 warnings, 63 files | 0 warnings, 84 files |
| Host-crashing bugs known | 0 (believed) | 2 found by review, fixed |

### Patterns that recurred
- **Tests that pin implementation details:** the 1.0 specs clicked literal pixel coordinates,
  which blocked the redesign until they were migrated to finding widgets by id.
- **The lead's own mistakes:** a demo-recording script hung LÖVE on its error screen by
  resizing the window before the game existed, and cost several minutes before the cause was
  found. It's recorded in `docs/ai-log/1.1-integration.md`.

## Not yet confirmed

- The maintainer **has not yet confirmed the manual checklists** in `docs/manual-test.md` for any
  milestone (M1–M5 logs say so explicitly; M0's checklist is likewise unchecked).
- No human corrections have been recorded for M0–M5.
- CI hasn't run on GitHub (the project is local). Its steps were reproduced in Docker for 1.1.1:
  the suite passes on PUC Lua 5.1.5 and on Linux, and the examples run under real LÖVE 11.5 there.
  Running it caught a smoke step that would have hung CI forever.
- Windows is untested.
- Click-to-cycle was shown working in the recorded 1.1 tour; off-screen culling is verified by
  specs only.
