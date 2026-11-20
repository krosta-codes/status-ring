#!/bin/zsh
# Pulls the latest version and rebuilds (build-local.sh restarts the app).
# Called by "Update to vX.Y.Z" in the popover or by hand. Log: ~/Library/Logs/StatusRing-update.log when run from the app.
set -e
cd "$(dirname "$0")"
trap 'osascript -e "display notification \"Update failed, details in ~/Library/Logs/StatusRing-update.log\" with title \"Status Ring\""' ERR
echo "== update $(date '+%F %T') from $(cat VERSION)"
git fetch --tags --quiet
git pull --ff-only --quiet
echo "now $(cat VERSION), building"
./build-local.sh
