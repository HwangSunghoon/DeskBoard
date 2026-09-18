# Release identity

Repository configuration confirmed on 2026-09-18. These values apply to both Debug and Release for the main app; this document does not confirm App Store registration or submission.

| Field | Value |
| --- | --- |
| App / display name | DeskBoard |
| Bundle identifier | `com.local.DeskBoard` |
| Initial marketing version | `1.0` |
| Initial build number | `1` |
| Development team | `UU9V3Q3PF7` (existing project team) |
| Copyright | Copyright © 2026 HwangSunghoon. All rights reserved. |
| Source license | MIT; see the repository's LICENSE |
| App category | Productivity |
| Minimum deployment target | macOS 14.0 |

## Preserve the existing identity

Keep `com.local.DeskBoard` for this release and subsequent updates. It is the identifier used by the current sandboxed app. Renaming it just to remove `local` would change the sandbox container and preferences domain, and could require users to select Quick Open apps and grant permissions again. No data migration or permission reset is performed by this change. Keeping the identity does not replace update and signed-permission testing.

Do not substitute the Error Lab identifier (`com.local.DeskBoard.ErrorLab`) for the main app. Error Lab is a separate test app and is not a distribution target.

## Before the first upload

- Confirm the existing team is the intended publishing account and its membership and agreements are ready.
- Verify that the exact bundle identifier is registered to that team and can be used for the App Store Connect app record. Repository configuration alone does not prove availability or registration.
- Confirm the desired store name is available. The App Store listing name is separate from the local display name.
- If the identifier cannot be registered, stop before changing it and plan preservation/export of existing local data first.
- Create and validate an App Store distribution archive. The current development build is not the submitted release.
- Test a clean installation and an update with existing data, calendar permission, and Quick Open selections.

## Versioning

`MARKETING_VERSION` is the user-facing version; `CURRENT_PROJECT_VERSION` identifies the build. Start with `1.0 (1)` if no build has been uploaded under this version. Increment the build number for each subsequent uploaded build, including TestFlight fixes; do not reuse an already uploaded build number. Change these values in both main-app configurations and update this document when preparing a new release.

Store registration, distribution signing, TestFlight upload, and release tagging remain separate steps. No public release has been created by confirming these values.
