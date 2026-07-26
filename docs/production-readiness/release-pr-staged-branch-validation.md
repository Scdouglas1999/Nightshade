# Release PR Staged Branch Validation

- Generated at: `2026-07-21T15:07:29.619743Z`
- Matrix: `docs/production-readiness/release-pr-owner-decision-matrix.json`
- Mode: `index`
- Base: `main`
- Passed: `false`
- Observed paths: `0`
- Issues: `2`
- Warnings: `2`

## Issues

- Missing must_ship paths: `.github/workflows/linux-release-build.yml`, `.github/workflows/release.yml`, `apps/desktop/lib/desktop_app_bootstrap.dart`, `apps/desktop/lib/headless/headless_auto_connect_bootstrap.dart`, `apps/desktop/lib/headless/headless_disk_watchdog_bootstrap.dart`, `apps/desktop/lib/headless/headless_services_bootstrap.dart`, `apps/desktop/lib/headless/headless_shutdown.dart`, `apps/desktop/lib/headless_api/auth/pairing_service.dart`, `apps/desktop/lib/headless_api/auth_policy.dart`, `apps/desktop/lib/headless_api/handlers.dart`, `apps/desktop/lib/headless_api/handlers/analytics_handlers.dart`, `apps/desktop/lib/headless_api/handlers/atlas_handlers.dart`, `apps/desktop/lib/headless_api/handlers/backup_handlers.dart`, `apps/desktop/lib/headless_api/handlers/calibration_handlers/dark_library_handlers.dart`, `apps/desktop/lib/headless_api/handlers/calibration_handlers/defect_map_handlers.dart`, `apps/desktop/lib/headless_api/handlers/calibration_library_handlers.dart`, `apps/desktop/lib/headless_api/handlers/catalog_handlers.dart`, `apps/desktop/lib/headless_api/handlers/coimaging_handlers.dart`, `apps/desktop/lib/headless_api/handlers/collaboration_handlers.dart`, `apps/desktop/lib/headless_api/handlers/db_read_handlers.dart`, ... 1603 more
- No staged or branch-diff paths were observed.

## Warnings

- Generated Only paths are not included in this validation.
- Binary / Evidence paths are not included in this validation.

## Matrix Integrity

- Source split plan: `docs/production-readiness/release-pr-split-plan.json`
- Source split plan exists: `true`
- Source split plan matches matrix: `true`

| Pathspec | Group | Exists | Lines | Matrix paths | Missing | Unexpected | Duplicates |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt` | `must_ship` | `true` | `71` | `71` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/04-headless-remote-api.txt` | `must_ship` | `true` | `87` | `87` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/05-mobile-remote-client.txt` | `must_ship` | `true` | `57` | `57` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt` | `must_ship` | `true` | `48` | `48` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt` | `must_ship` | `true` | `303` | `303` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt` | `must_ship` | `true` | `513` | `513` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt` | `must_ship` | `true` | `544` | `544` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/01-generated-files.txt` | `generated_only` | `true` | `31` | `31` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt` | `binary_evidence` | `true` | `17` | `17` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt` | `defer_exclude` | `true` | `8546` | `8546` | `0` | `0` | `0` |

## Decision Group Coverage

| Group | Rule | Status | Paths | Observed | Missing | Forbidden |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Must Ship | `required_all` | `incomplete` | `1623` | `0` | `1623` | `0` |
| Generated Only | `optional_all_or_none` | `not_included` | `31` | `0` | `31` | `0` |
| Binary / Evidence | `optional_all_or_none` | `not_included` | `17` | `0` | `17` | `0` |
| Defer / Exclude | `forbidden` | `clean` | `8546` | `0` | `8546` | `0` |

## Next Stage Commands

These commands are derived from the owner decision matrix pathspecs. Review the pathspec files before running them; cleanup commands only change the staged index.

### Must Ship

- Status: `incomplete`
- Rule: `required_all`
- Purpose: Required: stage every listed pathspec before the release PR validation can pass.

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/04-headless-remote-api.txt
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/05-mobile-remote-client.txt
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt
```

### Generated Only

- Status: `not_included`
- Rule: `optional_all_or_none`
- Purpose: Optional: leave this group unstaged, or stage every listed pathspec together.

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/01-generated-files.txt
```

### Binary / Evidence

- Status: `not_included`
- Rule: `optional_all_or_none`
- Purpose: Optional: leave this group unstaged, or stage every listed pathspec together.

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt
```

### Defer / Exclude

- Status: `clean`
- Rule: `forbidden`
- Purpose: Cleanup: remove these paths from the index if they appear in a staged release branch.

```powershell
git restore --staged --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt
```

## Observed Paths

None.
