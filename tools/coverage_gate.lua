-- Fails when coverage under a directory drops below its threshold.
-- Reads the summary table at the end of luacov.report.out.
local THRESHOLDS = {
  { prefix = "loupe/core/", min = 90 },
  { prefix = "loupe/ui/", min = 80 },
}

local report = io.open("luacov.report.out", "r")
if not report then
  io.stderr:write("coverage_gate: luacov.report.out not found; run `busted --coverage && luacov`\n")
  os.exit(1)
end

-- Summary rows look like: "loupe/core/clock.lua   42   3   93.33%"
local totals = {}
for line in report:lines() do
  local file, hits, missed = line:match("^(%S+%.lua)%s+(%d+)%s+(%d+)%s+[%d.]+%%$")
  if file then
    for _, t in ipairs(THRESHOLDS) do
      if file:sub(1, #t.prefix) == t.prefix then
        local sum = totals[t.prefix] or { hits = 0, missed = 0 }
        sum.hits = sum.hits + tonumber(hits)
        sum.missed = sum.missed + tonumber(missed)
        totals[t.prefix] = sum
      end
    end
  end
end
report:close()

local failed = false
for _, t in ipairs(THRESHOLDS) do
  local sum = totals[t.prefix]
  if not sum then
    print(("coverage %-12s  (no files yet)"):format(t.prefix))
  else
    local pct = 100 * sum.hits / math.max(1, sum.hits + sum.missed)
    local ok = pct >= t.min
    print(
      ("coverage %-12s %6.2f%%  (min %d%%) %s"):format(t.prefix, pct, t.min, ok and "ok" or "FAIL")
    )
    failed = failed or not ok
  end
end

os.exit(failed and 1 or 0)
