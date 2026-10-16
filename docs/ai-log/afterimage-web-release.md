# Afterimage web release checks

The review notification named a consent timing gap and incomplete artifact scanning; the other three findings were not supplied. The changes address the confirmed areas without claiming to reproduce unseen findings.

Browser SDK construction now waits for the game’s explicit readiness line after loading the saved choice. Opt-out is final for that page lifetime. Regression coverage checks zero requests before launch and after reload with a saved opt-out, plus keyed and keyless builds. An initial test incorrectly assumed the save directory existed; creating it before seeding the persisted choice fixed the test.

Archive auditing now fails closed on malformed, oversized and excessively nested archives, rejects unsafe paths and symlinks, applies credential rules to all members, and permits public keys only in the expected configuration assignments outside source archives.

The web canvas cap increased from 2560×1440 to 3840×2160. Slow frames must persist before a 10 percent reduction, with cooldown and warmup. Captures at 1920×1080 CSS pixels and 2× density verified both render sizes; randomized backgrounds differ between captures. The launcher now has a focused Play button and hidden status text.

Validation: 569 core specs, coverage and lint gates, game/analytics/settings tests, 11 MCP tests, seven archive regressions, three bootstrap regressions, native 120-frame smoke, keyed browser smoke including persisted opt-out, keyless browser smoke, source and built-artifact scans. Production ingestion, refused-event names and the eventual itch origin require dashboard verification separately.
