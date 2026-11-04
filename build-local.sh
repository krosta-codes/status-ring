#!/bin/zsh
# Builds DuoBar without Xcode (swiftc + Command Line Tools) into build/DuoBar.app.
# Compiled assets (Assets.car, AppIcon.icns) are reused from the installed release,
# because actool ships only with Xcode.
set -euo pipefail
cd "${0:A:h}"
REF_APP="${REF_APP:-$HOME/Projects/apps/duobar/build/reference/DuoBar.app}"
APP=build/DuoBar.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
find DuoBar -name '*.swift' > build/sources.txt
swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos13.0" \
  -module-name DuoBar @build/sources.txt -o "$APP/Contents/MacOS/DuoBar"
cp "$REF_APP/Contents/Info.plist" "$REF_APP/Contents/PkgInfo" "$APP/Contents/"
cp "$REF_APP/Contents/Resources/Assets.car" "$REF_APP/Contents/Resources/AppIcon.icns" "$APP/Contents/Resources/"
for d in DuoBar/*.lproj; do cp -R "$d" "$APP/Contents/Resources/"; done
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.4.0-hotspot" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 9" "$APP/Contents/Info.plist"
codesign --force --sign - --entitlements DuoBar/DuoBar.entitlements "$APP"
echo "Built $APP"
