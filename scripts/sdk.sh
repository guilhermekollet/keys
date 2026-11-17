#!/bin/bash
# Picks the macOS SDK to build with when only the Command Line Tools are installed.
#
# From the macOS 27 SDK on, SwiftUI's @State is a macro, and its plugin ships only with Xcode: with
# the Command Line Tools alone the app doesn't compile against that SDK. The tools still carry the
# macOS 26 SDK, which is all the app needs (it targets macOS 26), so this points SDKROOT at it.
#
# build.sh and scripts/test.sh source it. Run it to print the SDK for other commands:
#   SDKROOT="$(scripts/sdk.sh)" swift build
# An SDKROOT you set yourself, or Xcode, is left alone.

keys_pick_sdk() {
  [[ -n "${SDKROOT:-}" ]] && return 0
  local developer
  developer="$(xcode-select -p)"
  [[ "$developer" == *CommandLineTools* ]] || return 0
  [[ -e "$developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]] && return 0
  local version
  version="$(xcrun --sdk macosx --show-sdk-version)"
  (( ${version%%.*} >= 27 )) || return 0

  local sdk="$developer/SDKs/MacOSX26.sdk"
  if [[ ! -d "$sdk" ]]; then
    sdk="$(ls -d "$developer"/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -1)"
  fi
  if [[ -z "$sdk" || ! -d "$sdk" ]]; then
    echo "error: the Command Line Tools have the macOS $version SDK, which needs Xcode to build SwiftUI," >&2
    echo "and no macOS 26 SDK to fall back to. Install Xcode, or set SDKROOT to a macOS 26 SDK." >&2
    return 1
  fi
  export SDKROOT="$sdk"
  echo "note: building against $(basename "$sdk") (the macOS $version SDK needs Xcode for SwiftUI)" >&2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  keys_pick_sdk
  echo "${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
fi
