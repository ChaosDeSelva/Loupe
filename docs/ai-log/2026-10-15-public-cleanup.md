# Public-project cleanup — 2026-10-15

## Changes

- Reworked the README around installation and use; moved detailed controls and camera examples into `docs/usage.md`.
- Recovered missing screenshots and tour media from the identical extracted release source.
- Added contributor documentation and a static GitHub Pages site.
- Replaced the machine-specific rockspec source URL with the public repository URL.
- Hardened build staging cleanup and example-name validation; included the MIT license and excluded Finder metadata from archives.
- Added packaged-example smoke tests and build artifacts to CI. Removed the unconfigured paid AI reviewer workflow.
- Prepared a fresh public Git snapshot with the maintainer’s GitHub noreply address. Original local history and duplicate distribution folders are backed up outside the cleaned repository.

## Verification

Local macOS / LuaJIT: 552 tests passed, zero lint warnings; core coverage 99.45%, UI coverage 99.41%.
Formatting, architecture and rockspec module checks passed. All three examples passed 120-frame
smoke runs as source folders, portable `.love` packages, and macOS `.app` executables.
Archives were checked for integrity, required modules/licenses, and absence of Finder metadata.
The site’s slider, reset, and copy-code controls were exercised in a browser.
GitHub CI results are recorded by Actions; local success alone does not imply CI success.

## Limits

Smoke tests verify startup and a short run, not every interactive game flow. App bundles are
unsigned. Historical milestone notes remain historical evidence rather than current setup instructions.
