#!/usr/bin/env bash
# Runs the local quality gates. CI also checks other runtimes and real LÖVE builds.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n== %s\n' "$1"; }

step "stylua"
stylua --check .

step "luacheck"
luacheck .

step "core/ must not reference love"
if grep -rnw "love" loupe/core 2>/dev/null; then
  echo "core/ is pure Lua: move love.* access to loupe/init.lua or loupe/ui/render_love.lua" >&2
  exit 1
fi
echo "ok"

step "rockspec lists every module"
# A module missing from the rockspec breaks LuaRocks installs at require time.
spec_file=$(ls loupe-*.rockspec)
on_disk=$(find loupe -name "*.lua" | sed 's#\.lua$##; s#/init$##; s#/#.#g' | sort)
in_spec=$(grep -o '\["loupe[^"]*"\]' "$spec_file" | tr -d '[]"' | sort)
if [ "$on_disk" != "$in_spec" ]; then
  echo "$spec_file is out of date:" >&2
  diff <(echo "$on_disk") <(echo "$in_spec") >&2 || true
  exit 1
fi
echo "ok"

step "busted (with coverage)"
rm -f luacov.stats.out luacov.report.out
busted --coverage
luacov

step "coverage thresholds"
"${LUA:-luajit}" tools/coverage_gate.lua

step "Afterimage simulation, asset helpers, analytics contract and settings"
(cd examples/afterimage \
  && "${LUA:-luajit}" tests/sim_test.lua \
  && "${LUA:-luajit}" tests/run_test.lua \
  && "${LUA:-luajit}" tests/assets_test.lua \
  && "${LUA:-luajit}" tests/analytics_test.lua \
  && "${LUA:-luajit}" tests/settings_test.lua)

step "MCP protocol and authoring boundaries"
"${PYTHON:-python3}" -m unittest discover -s mcp -p 'test_*.py'
