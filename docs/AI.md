# How AI is used in this project

loupe is written primarily by an AI coding agent (Claude Code), with a human maintainer who
plans, reviews, tests in real games, and approves every merge. The goal is to show, in the
open, what it takes for AI-written code to be **clean, tested, and maintainable**: not just
working.

## The bar is the same for every line
AI-written code gets no special treatment. Every change must pass:

| Gate | Tool | Where |
|---|---|---|
| Formatting | StyLua | `tools/check.sh` |
| Lint, zero warnings | luacheck | `tools/check.sh` |
| Architecture: `core/` never touches `love` | grep | `tools/check.sh` |
| Unit tests | busted on LuaJIT and PUC Lua 5.1.5 (both verified locally) | `tools/check.sh` |
| Linux | the CI workflow's steps in `ubuntu:24.04`, incl. LÖVE 11.5 under Xvfb | `tools/ci-docker.sh` |
| Coverage: `core/` ≥ 90%, `ui/` ≥ 80% | luacov + `tools/coverage_gate.lua` | `tools/check.sh` |
| Runs in real LÖVE | `love examples/* --smoke`, plus scripted screenshot runs | local, by the lead agent |
| Human review | maintainer | each milestone |

The original milestones were verified locally. GitHub Actions now defines the same quality
gates, example smoke tests, and packaged-build checks for pushes and pull requests.
`tools/check.sh` remains the local entry point; historical logs describe the setup at that time.

## Workflow per milestone
1. **Plan.** The milestone's scope comes from `docs/roadmap.md`; the PR description restates it.
2. **Test first.** Specs for `core/` and `ui/` are written before the code.
3. **Implement** until `./tools/check.sh` is green.
4. **Self-review** with a local AI code review pass; fix findings.
5. **Review.** The maintainer reviews and tries it in the examples. (With a remote, CI and the AI
   reviewer workflow would also run here.)
6. **Log.** `docs/ai-log/M<n>.md` records what was built, what the gates and reviews caught,
   and what the human had to correct.

## What we don't hide
- Mistakes the AI made, including ones caught only by the human, go in the ai-log.
- Design decisions and their reasons are recorded as ADRs in `docs/decisions/`.
- The agent's standing instructions are public: see `CLAUDE.md`.

These logs feed `docs/case-study.md`, a write-up of what worked and what didn't.

From M6 on, work ran in parallel: separate AI agents built hot reload, the 1.0 polish pass and
the docs in their own git worktrees, and the lead agent merged, integrated and verified them.
