#!/bin/zsh
# Builds Status Ring without Xcode (swiftc + Command Line Tools) into build/StatusRing.app
# and installs it to /Applications. Info.plist, Assets.car and the icon live in assets/,
# because actool ships only with Xcode.
set -euo pipefail
cd "${0:A:h}"
APP=build/StatusRing.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
find DuoBar -name '*.swift' > build/sources.txt
SDK="${SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"  # 27.x SDK needs SwiftUIMacros (Xcode only)
swiftc -O -sdk "$SDK" -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos13.0" \
  -module-name DuoBar @build/sources.txt -o "$APP/Contents/MacOS/StatusRing"
cp assets/Info.plist assets/PkgInfo "$APP/Contents/"
cp assets/Assets.car assets/AppIcon.icns "$APP/Contents/Resources/"
for d in DuoBar/*.lproj; do cp -R "$d" "$APP/Contents/Resources/"; done
# A stable local identity keeps macOS permissions (Location, Bluetooth,
# Accessibility) across rebuilds; ad-hoc signatures change with every build.
IDENTITY=$(security find-identity -p codesigning | awk '/"DuoBar Local Signing"/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" --entitlements DuoBar/DuoBar.entitlements "$APP"
echo "Built $APP"

# Install: the LaunchAgent ~/Library/LaunchAgents/com.jurek.statusring.plist starts
# /Applications/StatusRing.app at login, so every build replaces that copy and restarts it.
LABEL=com.jurek.statusring
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x StatusRing || true
rm -rf /Applications/StatusRing.app
ditto "$APP" /Applications/StatusRing.app
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed /Applications/StatusRing.app"
