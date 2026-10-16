#!/usr/bin/env bash
# Runs the CI workflow (.github/workflows/ci.yml) locally in an ubuntu:24.04
# container: the gates under LuaJIT and under PUC Lua 5.1, then the LÖVE smoke
# run of every example under a virtual display.
#
# Usage:
#   tools/ci-docker.sh                           # native arch (arm64 on Apple Silicon)
#   PLATFORM=linux/amd64 tools/ci-docker.sh      # x86_64, like GitHub's runners (emulated)
#
# Needs a running Docker daemon. The repo is mounted read-only and copied into
# the container, so nothing on the host changes. Exits non-zero if any step fails.
set -euo pipefail

if [ "${1:-}" != "--inside" ]; then
  cd "$(dirname "$0")/.."
  exec docker run --rm ${PLATFORM:+--platform "$PLATFORM"} -v "$PWD:/repo:ro" \
    ubuntu:24.04 bash /repo/tools/ci-docker.sh --inside
fi

STYLUA_VERSION=v2.5.2
step() { printf '\n######## %s\n' "$1"; }

step "apt packages"
export DEBIAN_FRONTEND=noninteractive
# The docker image drops man pages, but love's postinst registers its man page
# with update-alternatives and fails without it. GitHub's runners keep them.
rm -f /etc/dpkg/dpkg.cfg.d/excludes
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  ca-certificates curl unzip build-essential \
  luajit libluajit-5.1-dev lua5.1 liblua5.1-0-dev luarocks \
  love xvfb xauth >/dev/null
uname -m
luajit -v
lua5.1 -v
luarocks --version | head -1
dpkg-query -W -f='love ${Version}\n' love

step "rocks (one tree per interpreter)"
# luarocks wants a prefix with bin/ and include/; Ubuntu splits LuaJIT's.
mkdir -p /opt/luajit/bin
ln -sf /usr/bin/luajit /opt/luajit/bin/luajit
ln -sfn /usr/include/luajit-2.1 /opt/luajit/include
for rock in busted luacheck luacov; do
  luarocks --lua-version=5.1 --lua-dir=/opt/luajit --tree=/opt/rocks-luajit install "$rock" >/dev/null
  luarocks --lua-version=5.1 --tree=/opt/rocks-lua51 install "$rock" >/dev/null
done
luarocks --lua-version=5.1 --tree=/opt/rocks-lua51 list --porcelain | cut -f1,2

step "stylua $STYLUA_VERSION"
curl -sSLo /tmp/stylua.zip \
  "https://github.com/JohnnyMorganz/StyLua/releases/download/$STYLUA_VERSION/stylua-linux-$(uname -m).zip"
unzip -oq /tmp/stylua.zip -d /usr/local/bin
stylua --version

# GitHub's runners aren't root; run as a normal user so file-permission specs mean the same.
useradd -m ci
cp -a /repo/. /work/
chown -R ci: /work
cd /work
as_ci() { runuser -u ci -- env HOME=/home/ci "$@"; }

step "gates (luajit)"
as_ci PATH="/opt/rocks-luajit/bin:$PATH" LUA=luajit ./tools/check.sh

step "gates (lua 5.1)"
as_ci PATH="/opt/rocks-lua51/bin:$PATH" LUA=lua5.1 ./tools/check.sh

step "love smoke"
love --version
failed=0
for game in examples/*/; do
  [ -f "$game/main.lua" ] || continue # examples/shared is a library, not a game
  echo "== $game"
  rc=0
  SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null timeout 120 xvfb-run -a love "$game" --smoke 120 || rc=$?
  echo "== $game exit $rc"
  [ "$rc" -eq 0 ] || failed=1
done
exit "$failed"
