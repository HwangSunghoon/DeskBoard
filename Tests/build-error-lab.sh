#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
lab_developer_path="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build
lab_build="$(mktemp -d "$PWD/build/ErrorLab.XXXXXX")"
lab_app="$lab_build/DeskBoard Error Lab.app"
mkdir -p "$lab_app/Contents/MacOS" "$lab_app/Contents/Resources"
cp Tests/ErrorLab/Info.plist "$lab_app/Contents/Info.plist"
lab_sdk="$(env DEVELOPER_DIR="$lab_developer_path" xcrun --sdk macosx --show-sdk-path)"
env DEVELOPER_DIR="$lab_developer_path" xcrun swiftc \
    -D DESKBOARD_ERROR_LAB -sdk "$lab_sdk" -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$lab_build/modules" \
    DeskBoard/Models/*.swift DeskBoard/Services/*.swift DeskBoard/Views/*.swift \
    DeskBoard/Settings/*.swift DeskBoard/Window/*.swift Tests/ErrorLab/*.swift \
    -o "$lab_app/Contents/MacOS/DeskBoardErrorLab"
# A stable Apple Development identity is recommended for real TCC/bookmark testing.
# Ad-hoc signing still isolates storage, but does not validate distribution identity.
codesign --force --options runtime --entitlements DeskBoard/Resources/DeskBoard.entitlements \
    --sign "${DESKBOARD_LAB_SIGN_IDENTITY:--}" "$lab_app"
codesign --verify --strict "$lab_app"
printf '\nBuilt isolated sandbox app: %s\n' "$lab_app"
printf 'Launch with: open "%s"\n' "$lab_app"
