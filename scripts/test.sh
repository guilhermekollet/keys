#!/bin/bash
# Runs the test suite. With Xcode selected, plain `swift test` works. With only the Command Line
# Tools, Swift needs to be pointed at the Testing framework that ships inside them, and from the
# macOS 27 SDK on, at the macOS 26 SDK as well (see scripts/sdk.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/sdk.sh
keys_pick_sdk

if xcode-select -p | grep -q "CommandLineTools"; then
  FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
  swift test -Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" "$@"
else
  swift test "$@"
fi
