# Release PR Staged Branch Validation

- Generated at: `2026-05-06T10:23:09.445212Z`
- Matrix: `docs/production-readiness/release-pr-owner-decision-matrix.json`
- Mode: `index`
- Base: `main`
- Passed: `false`
- Observed paths: `7`
- Issues: `1`
- Warnings: `2`

## Issues

- Missing must_ship paths: `apps/desktop/lib/headless_api/auth_policy.dart`, `apps/desktop/lib/headless_api/handlers.dart`, `apps/desktop/lib/headless_api/handlers/analytics_handlers.dart`, `apps/desktop/lib/headless_api/handlers/auxiliary_handlers.dart`, `apps/desktop/lib/headless_api/handlers/backup_handlers.dart`, `apps/desktop/lib/headless_api/handlers/device_handlers.dart`, `apps/desktop/lib/headless_api/handlers/equipment_handlers.dart`, `apps/desktop/lib/headless_api/handlers/filesystem_handlers.dart`, `apps/desktop/lib/headless_api/handlers/flat_wizard_handlers.dart`, `apps/desktop/lib/headless_api/handlers/focus_model_handlers.dart`, `apps/desktop/lib/headless_api/handlers/framing_handlers.dart`, `apps/desktop/lib/headless_api/handlers/guiding_handlers.dart`, `apps/desktop/lib/headless_api/handlers/imaging_handlers.dart`, `apps/desktop/lib/headless_api/handlers/mosaic_handlers.dart`, `apps/desktop/lib/headless_api/handlers/planetarium_handlers.dart`, `apps/desktop/lib/headless_api/handlers/profile_handlers.dart`, `apps/desktop/lib/headless_api/handlers/safety_monitor_handlers.dart`, `apps/desktop/lib/headless_api/handlers/scheduler_handlers.dart`, `apps/desktop/lib/headless_api/handlers/science_handlers.dart`, `apps/desktop/lib/headless_api/handlers/sequence_management_handlers.dart`, ... 763 more

## Warnings

- Generated Only paths are not included in this validation.
- Binary / Evidence paths are not included in this validation.

## Matrix Integrity

- Source split plan: `docs/production-readiness/release-pr-split-plan.json`
- Source split plan exists: `true`
- Source split plan matches matrix: `true`

| Pathspec | Group | Exists | Lines | Matrix paths | Missing | Unexpected | Duplicates |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt` | `must_ship` | `true` | `164` | `164` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/04-headless-remote-api.txt` | `must_ship` | `true` | `34` | `34` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/05-mobile-remote-client.txt` | `must_ship` | `true` | `9` | `9` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt` | `must_ship` | `true` | `100` | `100` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt` | `must_ship` | `true` | `127` | `127` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt` | `must_ship` | `true` | `292` | `292` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt` | `must_ship` | `true` | `64` | `64` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/01-generated-files.txt` | `generated_only` | `true` | `35` | `35` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt` | `binary_evidence` | `true` | `31` | `31` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt` | `defer_exclude` | `true` | `57` | `57` | `0` | `0` | `0` |

## Decision Group Coverage

| Group | Rule | Status | Paths | Observed | Missing | Forbidden |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Must Ship | `required_all` | `incomplete` | `790` | `7` | `783` | `0` |
| Generated Only | `optional_all_or_none` | `not_included` | `35` | `0` | `35` | `0` |
| Binary / Evidence | `optional_all_or_none` | `not_included` | `31` | `0` | `31` | `0` |
| Defer / Exclude | `forbidden` | `clean` | `57` | `0` | `57` | `0` |

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

- `apps/desktop/web_dashboard/css/dashboard.css`
- `apps/desktop/web_dashboard/index.html`
- `apps/desktop/web_dashboard/js/api.js`
- `apps/desktop/web_dashboard/js/app.js`
- `packages/nightshade_app/lib/screens/diagnostics/diagnostics_screen.dart`
- `packages/nightshade_app/lib/screens/settings/widgets/remote_access_settings.dart`
- `packages/nightshade_core/lib/src/providers/web_server_provider.dart`
