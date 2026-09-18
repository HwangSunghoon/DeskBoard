#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_developer_path="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build
check_build_dir="$(mktemp -d "$PWD/build/ErrorUIChecks.XXXXXX")"
check_app="$check_build_dir/DeskBoard Error UI Checks.app"
mkdir -p "$check_app/Contents/MacOS"
cp Tests/ErrorUI-Info.plist "$check_app/Contents/Info.plist"
check_sdk="$(env DEVELOPER_DIR="$check_developer_path" xcrun --sdk macosx --show-sdk-path)"
env DEVELOPER_DIR="$check_developer_path" xcrun swiftc \
    -sdk "$check_sdk" -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$check_build_dir/modules" \
    DeskBoard/Models/Persistence.swift DeskBoard/Services/*.swift \
    DeskBoard/Views/DateWeatherView.swift DeskBoard/Views/StorageStatusView.swift \
    Tests/ErrorUIRenderingChecks.swift -o "$check_app/Contents/MacOS/ErrorUIChecks"
"$check_app/Contents/MacOS/ErrorUIChecks" "$check_build_dir"
printf 'Error UI artifacts: %s\n' "$check_build_dir"
