# DeskBoard Privacy Policy

Last updated: September 17, 2026

DeskBoard is a free, local-first macOS dashboard maintained by the [DeskBoard project](https://github.com/HwangSunghoon/DeskBoard). It has no account system, advertising, analytics, telemetry, or developer-operated data server. This policy describes the app itself, not macOS services or applications you open from it.

## Data on your Mac

Todo items, Important items, and Memo text are stored locally using SwiftData. Settings store your appearance, section order, selected calendars, weather city and coordinates, World Clock cities, Focus Timer state, and Quick Open selections. Quick Open stores application names, bundle identifiers, local paths, and security-scoped bookmarks. Application icons are read locally.

With your permission, Today reads events from macOS Calendar. DeskBoard does not upload your events, tasks, notes, app selections, or system statistics. Your calendar account and macOS may independently synchronize or back up data according to your own settings.

System statistics are measured on your Mac. Network throughput shows aggregate byte counts, not browsing history or the contents of network traffic. Quick Open launches other apps; those apps have their own privacy policies.

## Weather and city search

DeskBoard requests forecasts from api.open-meteo.com using the selected city's latitude and longitude. The default city is Seoul. Forecast requests occur at launch and periodically while the app runs, and when you change the city. DeskBoard does not request GPS or device location permission.

When you type into the city search, your search text is sent to geocoding-api.open-meteo.com after a short typing delay. Both services receive the IP address and technical request information needed to process the request. Open-Meteo states that server logs can include coordinates and are deleted after 90 days. See [Open-Meteo's terms and privacy information](https://open-meteo.com/en/terms) for its current practices. The DeskBoard developer does not receive these requests.

The last successful forecast is cached locally for offline display. A forecast for one location is not displayed as the forecast for a different selected location. Weather data is provided by [Open-Meteo](https://open-meteo.com/) under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); city search uses [GeoNames](https://www.geonames.org/) through Open-Meteo.

## Storage, recovery, and retention

Your saved content and preferences remain until you change or remove them. Removing an item from the dashboard does not immediately remove it from older recovery copies or operating-system backups. Hiding a section does not delete its content.

DeskBoard writes local plaintext JSON recovery copies under its Application Support folder, in DeskBoard/Recovery. last-saved.json is replaced after a successful database save. pending.json protects edits that could not be saved normally and is retained while recovery remains unresolved. If a pending file cannot be decoded, its original bytes are archived as unreadable-recovery before replacement; these archives are retained for manual recovery and are not automatically expired. These copies are not encrypted by DeskBoard and are not a backup against device or disk failure.

Readable, app-named before-restore and earlier-recovery archives older than 30 days are eligible for cleanup after a successful database save and recovery-copy update, only when no pending recovery remains. Cleanup runs at most once a day during such saves. Recent archives, unreadable files, and unresolved recovery copies are not expired by this cleanup. Copies you export yourself and macOS backups are outside this retention process.

To find local files, open Help → DeskBoard Help → Support → Show Local Data Folder. Before manually deleting files, export any recovery data you need and quit DeskBoard. Delete only DeskBoard's default.store database and its matching companion files, and DeskBoard/Recovery in the displayed folder; never delete the whole Application Support folder. App preferences are separate in the app's macOS defaults domain, identified by the bundle identifier shown in Support. Uninstalling the app alone may leave local data and preferences. Consult Support if you need help removing them.

## External links and support

Privacy Policy and Support are bundled with the app and can be read offline. Opening external links contacts the linked site using your browser. Support reports submitted on [GitHub Issues](https://github.com/HwangSunghoon/DeskBoard/issues) are public and follow [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). Do not post private events, notes, recovery exports, credentials, or identifying screenshots there.

For questions about this policy or local data removal, use the project's Support page or GitHub Issues without sharing sensitive content. This policy will be updated when DeskBoard's data handling changes.
