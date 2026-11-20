#!/bin/zsh
# Builds Status Ring without Xcode (swiftc + Command Line Tools) into build/StatusRing.app,
# installs it to /Applications and (re)starts it. Info.plist, Assets.car and the icon live in
# assets/, because actool ships only with Xcode.
set -euo pipefail
cd "${0:A:h}"
APP=build/StatusRing.app
VERSION="$(cat VERSION)"
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
find DuoBar -name '*.swift' > build/sources.txt

# SDK: macOS 27+ SDKs need SwiftUIMacros, which ships only with Xcode. Use the newest 26.x or older SDK
# from the Command Line Tools, or set SDK=/path/to/MacOSX.sdk.
if [[ -z "${SDK:-}" ]]; then
  SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX2[0-6]*.sdk /Library/Developer/CommandLineTools/SDKs/MacOSX1[0-9]*.sdk 2>/dev/null | sort -V | tail -1 || true)"
  [[ -n "$SDK" ]] || SDK="$(xcrun --show-sdk-path)"
fi
echo "SDK $SDK"

swiftc -O -sdk "$SDK" -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos13.0" \
  -module-name DuoBar @build/sources.txt -o "$APP/Contents/MacOS/StatusRing"
cp assets/Info.plist assets/PkgInfo "$APP/Contents/"
cp assets/Assets.car assets/AppIcon.icns "$APP/Contents/Resources/"
for d in DuoBar/*.lproj; do cp -R "$d" "$APP/Contents/Resources/"; done

# Version and update-check info (UpdateService reads these)
PB=/usr/libexec/PlistBuddy
$PB -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
$PB -c "Add :CSRepo string krosta-codes/status-ring" "$APP/Contents/Info.plist"
$PB -c "Add :CSSourceDir string $PWD" "$APP/Contents/Info.plist"

# A stable local identity keeps macOS permissions (Location, Bluetooth, Accessibility) across
# rebuilds; ad-hoc signatures change with every build. Any certificate whose name ends in
# "Local Signing" or "Local Code Signing" works (README, Install), or set STATUSRING_SIGN_IDENTITY.
IDS="$(security find-identity -p codesigning 2>/dev/null || true)"
pick() { print -r -- "$IDS" | grep -E "\"$1\"" | awk '{print $2; exit}'; }
# Order: explicit name, the identity older builds used (keeps existing grants), any "... Local (Code) Signing".
IDENTITY="$( { [[ -n "${STATUSRING_SIGN_IDENTITY:-}" ]] && pick "$STATUSRING_SIGN_IDENTITY"; } || true)"
[[ -n "$IDENTITY" ]] || IDENTITY="$(pick "DuoBar Local Signing" || true)"
[[ -n "$IDENTITY" ]] || IDENTITY="$(pick ".*Local (Code )?Signing" || true)"
codesign --force --sign "${IDENTITY:--}" --entitlements DuoBar/DuoBar.entitlements "$APP"
echo "Built $APP ($VERSION, signed with $([[ -n $IDENTITY ]] && echo certificate || echo ad-hoc))"

[[ "${1:-}" == "--no-install" ]] && exit 0

# Install to /Applications and restart. If an own LaunchAgent exists (older setups), restart through it;
# otherwise just open the app (Settings > Launch Status Ring at login handles autostart).
LABEL=com.jurek.statusring
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
[[ -f "$PLIST" ]] && launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x StatusRing || true
sleep 0.5
rm -rf /Applications/StatusRing.app
ditto "$APP" /Applications/StatusRing.app
if [[ -f "$PLIST" ]]; then launchctl bootstrap "gui/$(id -u)" "$PLIST"; else open /Applications/StatusRing.app; fi
echo "Installed /Applications/StatusRing.app"
