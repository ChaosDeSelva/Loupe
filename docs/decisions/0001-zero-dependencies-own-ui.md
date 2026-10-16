# 0001: Zero dependencies and our own UI toolkit

- Status: accepted
- Date: 2026-10-09

## Context
loupe is dropped into existing games. Typical hand-rolled LÖVE games vendor no libraries at all.
The UI options were Slab (pure Lua, but a large dependency with its own conventions),
cimgui-love (polished, but needs a native library per platform), or our own.

## Decision
loupe ships as one folder with no dependencies, including its own small immediate-mode UI.

## Consequences
- Installing is "copy the folder": no native binaries, no version conflicts with the host game.
- We take on building and testing a UI toolkit (milestone M2, the largest).
- The toolkit only needs what an inspector needs (windows, trees, labels, buttons, checkboxes,
  drag-numbers, text fields, color swatches), which keeps the scope bounded.
