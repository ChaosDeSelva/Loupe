# 0011: Opt-in analytics in a public game, with no key in the source

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
- Consent is opt-in on every build: the SDK runs with `consent = "opt_in"` and the player's
  ANALYTICS switch is the only way on. A web page does not construct its SDK before that yes.
- The web game is keyless; the page holds the key. Without a key the page installs the bridge
  as a sink, so the game behaves the same and sends nothing.
- The event contract is versioned (`schema_version` 1) and asserted key by key in
  `tests/analytics_test.lua`; automation flags label events `synthetic`.
- `tools/audit_release.py --artifact` and `tools/smoke_web.mjs` gate the Pages deploy.

## Consequences
- A clone, a fork and every development build send nothing, with no code path to disable.
- The shipped key is public by design. What bounds misuse is the platform side: the key's event
  allowlist, rate limits, optional monthly ceiling, pause and revocation. No build can prove
  which site or fork sent an event.
- Releasing with analytics needs the secret; without it the build is simply keyless.
- The vendored SDK must be re-copied from an upstream tag to change; `lib/ravensight/VERSION`
  names the source.
