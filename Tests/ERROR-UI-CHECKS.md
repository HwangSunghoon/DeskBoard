# Isolated error UI checks

Run from the repository root on macOS with full Xcode installed:

```sh
bash Tests/run-error-ui-checks.sh
bash Tests/run-regression-checks.sh
```

The first command builds a separate test bundle (`com.deskboard.tests.error-ui`)
under an individually named `build/ErrorUIChecks.*` folder. Its executable exits
after producing ten PNGs and `results.txt`; it does not install or replace DeskBoard.

Fixtures use in-memory SwiftData, a UUID-named temporary directory, and a separate
UserDefaults suite. Temporary fixtures are removed on normal exit. Network failures
come from a mock provider; storage failures use thrown errors and a file where a
test directory would be expected. The checks do not fill the disk, change Calendar
permissions, or access the production database. Dashboard services are never started.

Verified cases:

- Primary save fails but the recovery copy succeeds: no warning, content preserved.
- Both save paths fail: silent at 299 seconds, warning at 301 simulated seconds.
- Database open fails: a saved recovery copy loads into an editable temporary store.
- An unresolved recovery copy does not silently replace the existing editor.
- The pre-restore safety archive fails: restore stops and current edits remain intact.
- Weather requests fail: recent cache retained; a small delay dot after two hours;
  unavailable state when there is no cache.
- A subsequent primary save succeeds: the warning clears and contents remain intact.

The PNGs render the actual DateWeatherView and StorageStatusView content in an
off-screen NSHostingView. Native buttons are rendered, but this is **not** a desktop
screenshot or an automated click test. The solid background is only a test backdrop;
wallpaper/material blending, popover placement, confirmation dialogs, export-panel
interaction, termination, Calendar permission transitions, Quick Open app launching,
and signed sandbox behavior still require interactive testing. Never reproduce disk
exhaustion or corrupt the real user database just to test these paths.
