#!/usr/bin/env bash
# Builds the examples as standalone games, with loupe inside (F1 works in the build).
#
#   tools/build.sh            # all examples -> dist/
#   tools/build.sh asteroids  # one example
#
# For each example it writes:
#   dist/<name>.love   runs anywhere LÖVE 11.5 is installed: `love <name>.love`
#   dist/<name>.app    macOS only, when /Applications/love.app exists: a double-clickable app
#                      (unsigned; the first launch needs right-click > Open)
#
# A built game is fused, so loupe saves overrides to the save directory and hot reload is off
# (there are no source files to edit). See docs/api.md.
#
# Analytics (Afterimage only): every build drops any analytics.config.lua, so a local
# test key never ships. A release build writes a fresh one from the environment:
#
#   AFTERIMAGE_RELEASE=1 RAVENSIGHT_PUBLIC_KEY=gt_pub_... tools/build.sh afterimage
#
# Without both, the build is keyless and sends nothing. See examples/afterimage/README.md.
set -euo pipefail
cd "$(dirname "$0")/.."

LOVE_APP=${LOVE_APP:-/Applications/love.app}
DIST=dist
names=("$@")
if [ ${#names[@]} -eq 0 ]; then
  for dir in examples/*/; do
    [ -f "$dir/main.lua" ] && names+=("$(basename "$dir")")
  done
fi

stage=""
trap '[ -z "$stage" ] || rm -rf "$stage"' EXIT
mkdir -p "$DIST"
for name in "${names[@]}"; do
  case "$name" in
    *[!a-zA-Z0-9_-]*|"") echo "invalid example name: $name" >&2; exit 1 ;;
  esac
  src="examples/$name"
  [ -f "$src/main.lua" ] || { echo "no example called $name" >&2; exit 1; }
  stage=$(mktemp -d)

  # The game at the root; loupe and the shared helpers at their require paths, because
  # the examples' package.path trick (loading ../../loupe) doesn't apply inside a .love.
  cp -R "$src"/. "$stage"/
  rm -rf "$stage/tests" "$stage/tools" "$stage/dist"
  cp -R loupe "$stage/loupe"
  cp LICENSE "$stage/LICENSE"
  if grep -rq 'examples\.shared' "$src"; then
    mkdir -p "$stage/examples"
    cp -R examples/shared "$stage/examples/shared"
  fi
  find "$stage" \( -name 'loupe_overrides.lua' -o -name 'analytics.config.lua' -o -name '.DS_Store' -o -name '._*' \) -type f -delete
  if [ -f "$src/tools/analytics_config.py" ] && [ "${AFTERIMAGE_RELEASE:-}" = "1" ]; then
    if [ -n "${RAVENSIGHT_PUBLIC_KEY:-}" ]; then
      python3 "$src/tools/analytics_config.py" --distribution native-release >"$stage/analytics.config.lua"
      echo "release build: analytics config written (native-release)"
    else
      echo "release build without RAVENSIGHT_PUBLIC_KEY: keyless, analytics off" >&2
    fi
  fi

  rm -f "$DIST/$name.love"
  (cd "$stage" && zip -qr -9 -X "$OLDPWD/$DIST/$name.love" .)
  rm -rf "$stage"
  stage=""
  echo "built $DIST/$name.love"

  if [ -d "$LOVE_APP" ]; then
    app="$DIST/$name.app"
    rm -rf "$app"
    cp -R "$LOVE_APP" "$app"
    cp "$DIST/$name.love" "$app/Contents/Resources/$name.love"
    plist="$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName loupe $name" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier dev.loupe.examples.$name" "$plist"
    # LÖVE's app opens .love files from Finder; a fused game shouldn't claim them.
    /usr/libexec/PlistBuddy -c "Delete :UTExportedTypeDeclarations" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :CFBundleDocumentTypes" "$plist" 2>/dev/null || true
    echo "built $app"
  fi
done
