# 0011: Analytics in a public game, with no key in the source

- Status: accepted
- Date: 2026-10-15

## Context
Afterimage is distributed as public source, a native `.love` download, a GitHub Pages web build
and an itch.io HTML5 zip. Its developer wants a small, versioned set of gameplay events from the
official builds. Anything shipped is public: a key inside a build can be read, and a key in the
repository would follow every fork, so forks would report into the original account. Players
must decide before anything is sent. Loupe's own library (`loupe/`) must stay dependency-free.

## Decision
- Analytics lives only in the example game: `examples/afterimage/src/analytics.lua` (pure Lua,
  tested without LÖVE) over the vendored ravensight-love SDK in `examples/afterimage/lib/`.
  `loupe/` gains nothing but the existing `loupe.editRevision()`, read for the `modified` flag.
- The SDK starts only when `analytics.config.lua` exists. That file is gitignored and written
  only by the release tools from the `RAVENSIGHT_PUBLIC_KEY` environment variable (a repository
  secret in CI). The tools accept only a public `gt_pub_` key; a source zip never gets one.
- Consent was opt-in on every build (superseded on 2026-10-15, see below): the SDK ran with
  `consent = "opt_in"` and the player's ANALYTICS switch was the only way on.
- The web game is keyless; the page holds the key. Without a key the page installs the bridge
  as a sink, so the game behaves the same and sends nothing.
- The event contract is versioned (`schema_version` 1) and asserted key by key in
  `tests/analytics_test.lua`; automation flags label events `synthetic`.
- `tools/audit_release.py --artifact` and `tools/smoke_web.mjs` gate the Pages deploy.

## Decision, 2026-10-15: always on in official builds
At the owner's request the ANALYTICS switch is removed. Official builds (the ones the release
tools give a key) always send the twelve events, and the title screen discloses it in one line:
"Sends anonymous play stats, sectors, upgrades and deaths, to the developer." The SDK runs with
`consent = "opt_out"` and the game never calls `setTrackingEnabled`, so collection still stops on
the server's kill switch, a refused key, or the SDK's own opt-out file. The web page starts its
SDK when the player presses Play instead of waiting for a yes, and still honours the game's
`enabled false` line. Keyless forks and development builds are unchanged: no config, no
disclosure, nothing sent. Every run is reported while the SDK collects, so the unobserved-run rule
is gone. `settings.txt` never held the choice and is unchanged.

## Consequences
- A clone, a fork and every development build send nothing, with no code path to disable.
- The shipped key is public by design. What bounds misuse is the platform side: the key's event
  allowlist, rate limits, optional monthly ceiling, pause and revocation. No build can prove
  which site or fork sent an event.
- Releasing with analytics needs the secret; without it the build is simply keyless.
- The vendored SDK must be re-copied from an upstream tag to change; `lib/ravensight/VERSION`
  names the source.
