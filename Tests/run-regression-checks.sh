#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/DeskBoardChecks.XXXXXX")"
check_developer_path="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [[ ! -d "$check_developer_path/Toolchains/XcodeDefault.xctoolchain" ]]; then
    check_developer_path="/Applications/Xcode.app/Contents/Developer"
fi
if [[ ! -d "$check_developer_path/Toolchains/XcodeDefault.xctoolchain" ]]; then
    printf 'Full Xcode is required for SwiftData macros. Set DEVELOPER_DIR to its Contents/Developer directory.\n' >&2
    exit 1
fi
check_sdk="$(env DEVELOPER_DIR="$check_developer_path" xcrun --sdk macosx --show-sdk-path)"
check_arch="$(uname -m)"
run_check() {
    local check_name="$1"
    shift
    env DEVELOPER_DIR="$check_developer_path" xcrun swiftc -sdk "$check_sdk" -target "${check_arch}-apple-macos14.0" \
        -module-cache-path "$check_build_dir/modules" "$@" \
        "Tests/${check_name}RegressionChecks.swift" -o "$check_build_dir/$check_name"
    "$check_build_dir/$check_name"
}
run_check FocusTimer DeskBoard/Services/FocusTimerStore.swift
run_check WorldClock DeskBoard/Services/WorldClockStore.swift
run_check SectionOrder DeskBoard/Services/DashboardPreferences.swift DeskBoard/Views/SidebarLayout.swift
run_check SettingsReorder DeskBoard/Services/DashboardPreferences.swift DeskBoard/Services/WorldClockStore.swift DeskBoard/Services/QuickOpenStore.swift
run_check WeatherLocation DeskBoard/Services/DashboardPreferences.swift DeskBoard/Services/WeatherLocationStore.swift DeskBoard/Services/ExternalDataServices.swift
run_check NetworkResilience DeskBoard/Services/DashboardPreferences.swift DeskBoard/Services/WeatherLocationStore.swift DeskBoard/Services/ExternalDataServices.swift
run_check PersistenceResilience DeskBoard/Models/Persistence.swift
printf 'All regression checks passed. Temporary binaries: %s\n' "$check_build_dir"
