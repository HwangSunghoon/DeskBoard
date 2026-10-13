# DeskBoard

DeskBoard is a native macOS productivity sidebar that keeps the information you use throughout the day visible on the desktop. It combines time and weather, today's calendar, system status, todos, important dates, and a free-form memo in one lightweight panel.

## Available on the Mac App Store

[Download DeskBoard: Desktop Sidebar for free](https://apps.apple.com/kr/app/deskboard-desktop-sidebar/id6814308273)

DeskBoard **1.0 (build 2)** has passed App Review and is publicly available on the Mac App Store, verified on **October 13, 2026**. The released app requires **macOS 14.0 or later**, has an **English interface**, and includes no accounts, ads, subscriptions, or in-app purchases.

The App Store edition focuses on everyday productivity and **does not include the Market section or stock/market quotes**. Calendar access is optional; other features remain available without it.

[![DeskBoard's public Mac App Store listing, showing the Get button and app screenshots](docs/app-store-listing.png)](https://apps.apple.com/kr/app/deskboard-desktop-sidebar/id6814308273)

*Public Mac App Store listing captured on October 13, 2026.*

## Branch guide

The repository keeps the market-enabled variant separate from the market-free release line.

| Branch | Market / stock features | Purpose |
| --- | --- | --- |
| [`codex/release-prep`](https://github.com/HwangSunghoon/DeskBoard/tree/codex/release-prep) | **Not included** | Market-free release-preparation line with privacy/support documentation. Start here for the App Store feature set. |
| [`archive/with-market`](https://github.com/HwangSunghoon/DeskBoard/tree/archive/with-market) | **Included** | Preserved pre-release variant with a configurable Market section. It is not the App Store edition. |
| [`main`](https://github.com/HwangSunghoon/DeskBoard/tree/main) | **Included (older implementation)** | Original development baseline and current GitHub default branch. It is not the market-free release line. |

The archived Market variant lets you choose and reorder **2–6 of 15 indicators**: Korean, US, European, and Asian indices; USD/KRW, EUR/KRW, and EUR/USD; gold and WTI futures; and Bitcoin (USD). It displays quotes and percentage changes using a Yahoo Finance chart endpoint; it does not place trades. The archive is a historical snapshot and does not automatically receive later release fixes. Provider availability and redistribution requirements must be reviewed separately before distributing that variant.

For normal use, install the App Store edition. For source builds, choose the branch explicitly rather than assuming `main` matches the published app:

```sh
# Without Market: release-preparation line
git clone --branch codex/release-prep https://github.com/HwangSunghoon/DeskBoard.git DeskBoard-release

# With Market: preserved development variant
git clone --branch archive/with-market https://github.com/HwangSunghoon/DeskBoard.git DeskBoard-market
```

## Features

The features below describe the **market-free release line**.

- Native SwiftUI and AppKit interface with a translucent, floating desktop panel
- Left- or right-side placement on the selected display
- Desktop and Always on Top window modes
- Digital and analog clock styles
- Customizable Quick Open buttons for up to six locally installed macOS applications, using their original color icons
- Current weather, daily high/low, and precipitation probability
- Search and select a weather city with region/country information; coordinates are saved with the selection, without requesting device location permission
- Today's events and locations from selected macOS calendars
- CPU, memory, battery, and network throughput monitoring
- Editable todos, important items with optional dates, and an autosaving memo
- Compact month calendar for Important dates, with one-click date selection
- Adaptive section sizing with independent scrolling for longer lists
- Time, weather, and Memo are always visible; other sections are opt-in on first launch. Existing optional-section selections are preserved, and hidden sections keep their saved data
- Drag rows in Settings to reorder sections, Quick Open applications, and World Clock cities; order is saved across launches. Time, weather, and Quick Open stay at the top, while Memo can move but cannot be hidden
- Built-in English user guide under Help → DeskBoard Help, available offline
- Quick Open takes no vertical space when no applications are selected
- Optional compact Focus Timer with pause/resume, configurable focus and break durations, and session restoration
- Optional World Clock for up to four cities in equal-width horizontal columns, with automatic daylight-saving and date-offset handling
- Light, dark, and system appearances with adjustable background opacity
- Optional Dock and menu bar icons with launch-at-login support

Todos, important items, and the memo are stored locally with SwiftData. The app has no external package dependencies.

## Requirements

- macOS 14.0 or later
- Xcode 15 or later

## Build and Run

1. Clone the repository.
2. Open `DeskBoard.xcodeproj` in Xcode.
3. Select the `DeskBoard` scheme and the `My Mac` destination.
4. If Xcode requests it, select your own development team under **Signing & Capabilities**.
5. Press **Command-R**.

You can also build from Terminal:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project DeskBoard.xcodeproj \
  -scheme DeskBoard \
  -configuration Debug \
  build
```

DeskBoard opens as a sidebar near the edge of the selected display. Use the gear button at the bottom of the panel to change its placement, appearance, clock style, data settings, and startup behavior.

## Data and Permissions

| Feature | Source | Notes |
| --- | --- | --- |
| Weather | [Open-Meteo](https://open-meteo.com/) | City search returns coordinates for the selected city (Seoul by default). No device location permission is requested. The current public endpoints require no API key. |
| Calendar | EventKit | macOS asks for calendar access before events are shown. You can display all calendars or select one calendar. |
| Quick Open | NSWorkspace | Apps are selected with the macOS file picker. Security-scoped bookmarks retain access across launches. |
| System | macOS system APIs | CPU, RAM, battery, and network are measured locally, only while System is enabled. |

Weather refreshes every 15 minutes and when a new city is selected. The last successful weather responses are cached locally so the dashboard can continue showing recent data when a request fails. Weather caches are tied to coordinates; switching cities never displays a different city's cached forecast.

Failures keep the last successful values and retry with a capped backoff. No automatic error popups are shown. A subtle dot appears only after weather is over two hours old; hover for timestamps. Hiding System or Today stops their polling; hiding Focus does not pause an active countdown.

### Local save recovery

Todo, Important and Memo use explicit saves with retry. Short failures are silent. A separate atomic JSON recovery copy protects edits when the database cannot save. A small save-status control appears only when neither storage path has worked for five minutes (or an explicit quit would lose edits). No rollback clears text from the editor.

If the database cannot open, DeskBoard preserves it and tries an in-memory editor using the latest readable recovery snapshot. If the database opens but an unsaved recovery copy also exists, the database is shown unchanged and restoration is offered explicitly. Restoration archives the original content first; recovery content can be exported as JSON. Recovery snapshots are local plaintext files under the app's Application Support `DeskBoard/Recovery` directory (inside its container for sandboxed builds). Readable retired recovery archives older than 30 days are pruned only after both a database save and backup update succeed, with no unresolved pending recovery. Current backups, pending copies, unreadable files, and user exports do not expire through this cleanup. They are crash-recovery copies, not protection against whole-disk failure. A damaged snapshot or a process killed before the next save can still require manual recovery.

### Distribution checklist

The release identity is **DeskBoard**, bundle identifier **`com.local.DeskBoard`**. The published App Store version is **1.0 (build 2)**; build 1 was the initial review submission. The existing identifier is retained to avoid changing the sandbox container and preferences domain. See [Release identity](docs/release-identity.md) for signing, versioning, and registration checks; check the selected source branch's Xcode settings before creating a new archive.

Release enables Hardened Runtime and dSYM generation; a required-reason privacy manifest declares app-owned UserDefaults access and recovery-file timestamp access ([Apple's approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)). Quick Open uses app-scoped bookmarks, and user-selected read/write access supports recovery export. These settings do **not** replace signed-sandbox testing, Developer ID notarization for direct distribution, or App Store validation.

For future releases or forks, review the weather provider's [terms](https://open-meteo.com/en/terms) and attribution requirements, keep policy/support URLs public, verify your signing identity, and test a distribution-signed build. The published app's approval does not extend to a modified fork, and an unsigned local build is not a distributable release.

### Regression checks

With Xcode selected, run `bash Tests/run-regression-checks.sh`. The standalone checks cover timers, preferences, ordering, weather search races, offline results, conservative warning thresholds, failed saves and recovery. Tests use isolated preferences and temporary/in-memory stores, never the user's app data. Signed sandbox permissions, UI interaction, macOS 14/Intel compatibility, and multi-monitor/sleep-wake behavior still require device testing.

## Privacy and Support

Read the [Privacy Policy](docs/privacy.md) and [Support guide](docs/support.md). Both documents ship with the app and open offline from links in Help → DeskBoard Help. Support links to the public [GitHub Issues](https://github.com/HwangSunghoon/DeskBoard/issues) page; do not post private data there.

DeskBoard does not include analytics, telemetry, advertising, or account sign-in. Personal productivity data remains on the Mac. Network requests are limited to the weather provider described above. City search text is sent to Open-Meteo's geocoding service, and the selected coordinates are sent to its forecast service.

## Project Structure

```text
DeskBoard/
├── App/          Application lifecycle and menu commands
├── Models/       SwiftData models
├── Resources/    Entitlements and app icon assets
├── Services/     Calendar, weather, and system data
├── Settings/     Preferences UI
├── Views/        Sidebar sections and adaptive layout
└── Window/       AppKit desktop panel management
```

## License

DeskBoard is available under the [MIT License](LICENSE).
