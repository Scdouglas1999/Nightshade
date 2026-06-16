# PR 06: Desktop UI And Workflow Packages

## Summary

Review app UI, shared UI system, planetarium, plugin, updater, WebRTC, and desktop workflow changes together or split by screen if too large.

Recommended staging decision: Use UI consistency audit results and focused screenshot/smoke evidence before moving these paths into a release PR.

## Scope

- Bucket ID: `desktop-ui-workflows`
- Path count: `27`
- Tracked changes: `27`
- Untracked paths: `0`
- Deleted paths: `0`
- Must-ship/release-critical paths: `22`
- Generated-only paths: `0`
- Binary/evidence paths: `0`
- Defer/exclude review paths: `5`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/06-desktop-ui-workflows.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `app-ui`: `22`
- `other`: `1`
- `remote-protocol`: `3`
- `updater`: `1`

## Representative Paths

- `M ` `apps/desktop/lib/desktop_app_bootstrap.dart` (other)
- `M ` `packages/nightshade_app/lib/screens/analytics/widgets/photometric_calibration_wizard/star_matching.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/analytics/widgets/project_tracking_panel.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/equipment/equipment_screen.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/equipment/equipment_screen/progress_dashboard.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/equipment/widgets/connected_device_card/actions_and_telemetry.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/equipment/widgets/connected_device_card/command_handlers.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/equipment/widgets/connected_device_card/dialogs_and_settings.dart` (app-ui)
- `A ` `packages/nightshade_app/lib/screens/equipment/widgets/switch_control_card.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/imaging/imaging_screen/imaging_screen_actions.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/imaging/widgets/calibration_section.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/imaging/widgets/rotator_panel.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/imaging/widgets/stacking_panel.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/sequencer/widgets/smart_night_dialog.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/settings/settings_catalog.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/settings/widgets/calibration_library_settings.dart` (app-ui)
- `A ` `packages/nightshade_app/lib/screens/settings/widgets/captured_images_settings.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/settings/widgets/connection_settings.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/settings/widgets/file_path_settings.dart` (app-ui)
- `A ` `packages/nightshade_app/lib/screens/settings/widgets/focus_model_settings.dart` (app-ui)
- ... 7 more paths in `docs/production-readiness/release-pr-pathspecs/06-desktop-ui-workflows.txt`.

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
