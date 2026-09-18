# DeskBoard Support

DeskBoard is a free macOS desktop dashboard. The built-in Help → DeskBoard Help guide explains all sections. Settings is available from the gear button at the bottom of the sidebar. This page is also available offline in Help → DeskBoard Help → Support.

## Customize your dashboard

Time, weather, and Memo are always available. Optional sections start disabled for new installations. Turn them on in Settings → Sections, and use the three-line handles to rearrange them. Hiding a section keeps its saved data. Add up to six local applications to Quick Open and up to four World Clock cities. Quick Open takes no height when its list is empty.

## Weather or calendar is missing

For weather, check the selected city in Settings → Data and your internet connection. Failed requests keep the last successful forecast for that location and retry quietly. A small indicator appears after a prolonged delay; hover to see details. A new location without a cached forecast needs a successful request first. The main clock follows your Mac's time zone, independently of the weather city.

For Today, check calendar access in System Settings → Privacy & Security → Calendars and the calendar selection in DeskBoard Settings. Calendar accounts and their synchronization are managed by macOS, not DeskBoard. Turning Today off stops its polling.

## An application does not open

If a Quick Open application moved, was removed, or lost its access permission, remove it from the list and select its current .app again using Add Application. The file picker grants access to that selection. Launching an app can still depend on macOS permissions and the app itself.

## Saving and recovery

Brief save failures retry without interrupting editing. DeskBoard tries to keep a separate local recovery copy. If neither the database nor that copy can be saved for five minutes, a Save issue control appears. Free disk space and check storage access. Export your current data before quitting if DeskBoard warns that edits are not protected.

If Recovery copy is shown, read its explanation before restoring. An unsaved copy does not silently replace a healthy database. Restoration is an explicit action and archives the previous database content first. Export the recovery copy before attempting manual repair. Do not delete the original database to dismiss an error.

## Local files and deletion

The in-app Support sheet shows the actual Application Support folder for your running build and can open it in Finder. The database uses default.store and its matching companion files; recovery snapshots are in DeskBoard/Recovery. A sandboxed build keeps these inside its app container. Do not remove unrelated files or the entire Application Support folder.

To remove local content manually, export what you need, quit DeskBoard, then remove only those DeskBoard database and recovery files. Preferences and the weather cache are stored separately in macOS UserDefaults, under the bundle identifier shown by in-app Support. Ask for instructions for your specific build before resetting preferences. Exported files and Time Machine or other backups must be managed separately. See Help → DeskBoard Help → Privacy Policy for retention details; it is available offline.

## Report a problem

Use [DeskBoard GitHub Issues](https://github.com/HwangSunghoon/DeskBoard/issues). Include your DeskBoard version, macOS version, expected and actual behavior, and steps to reproduce. For layout issues, include display resolution, scaling, display count, and whether the Mac is in clamshell mode. Redact screenshots before sharing them.

Issues are public. Never attach private calendar events, notes, recovery JSON, passwords, or access tokens. Support is community-based and has no guaranteed response time. For data recovery, describe the visible status first without uploading your data.
