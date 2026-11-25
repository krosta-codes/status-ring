#!/bin/zsh
# Runs the XCTest suite (DuoBarTests) with Xcode, without changing the system's xcode-select.
# Usage: ./run-tests.sh                      all tests
#        ./run-tests.sh AppAudioTests        one test class (-only-testing)
set -euo pipefail
cd "${0:A:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[[ -d "$DEVELOPER_DIR" ]] || { echo "Xcode not found at $DEVELOPER_DIR"; exit 1; }
ONLY=()
for t in "$@"; do ONLY+=("-only-testing:DuoBarTests/$t"); done
mkdir -p build
set +e
xcodebuild test -project DuoBar.xcodeproj -scheme DuoBar -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= \
  "${ONLY[@]}" > build/xctest.log 2>&1
CODE=$?
set -e
grep -E "\.swift:[0-9]+: error" build/xctest.log | tail -20 || true
grep -E "Executed [0-9]+ tests" build/xctest.log | tail -1
echo "exit $CODE (full log: build/xctest.log)"
exit $CODE
