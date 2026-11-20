#!/bin/zsh
# One-shot setup: checks the Mac, builds Status Ring, installs it to /Applications and starts it. Safe to run again.
set -e
cd "$(dirname "$0")"
ok()   { print -P "%F{green}ok%f    $1"; }
warn() { print -P "%F{yellow}warn%f  $1"; }
fail() { print -P "%F{red}fail%f  $1"; exit 1; }

OSV="$(sw_vers -productVersion)"
autoload is-at-least
is-at-least 13.0 "$OSV" || fail "macOS 13 or newer required, this Mac has $OSV."
ok "macOS $OSV ($(uname -m))"

if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install || true
  fail "Command Line Tools installer opened. Finish it, then run install.sh again."
fi
ok "Command Line Tools"

if security find-identity -p codesigning 2>/dev/null | grep -qE '"'"${STATUSRING_SIGN_IDENTITY:-.*Local (Code )?Signing}"'"'; then
  ok "signing certificate found"
else
  warn "no local signing certificate: macOS asks for Location/Bluetooth again after every rebuild (README, Install, step 3)."
fi

./build-local.sh
ok "Status Ring is in your menu bar. Settings > Launch Status Ring at login to keep it there."
