-- The shape of analytics.config.lua, which only the release tools write
-- (examples/afterimage/tools/analytics_config.py, from RAVENSIGHT_PUBLIC_KEY).
-- The game never reads this example. To try analytics locally, copy it to
-- analytics.config.lua (gitignored) with a key for a test environment; runs
-- started by automation flags are then labelled synthetic.
return {
  distribution = "native-release", -- or "web-pages", "web-itch"
  ingestKey = "YOUR_PUBLIC_KEY", -- a gt_pub_ key; never a gt_live_ key
  -- apiUrl = "https://api.ravensight.io",
}
