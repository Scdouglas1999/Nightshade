# PR 08: Desktop UI And Workflow Packages

## Summary

Review app UI, shared UI system, planetarium, plugin, updater, WebRTC, and desktop workflow changes together or split by screen if too large.

Recommended staging decision: Use UI consistency audit results and focused screenshot/smoke evidence before moving these paths into a release PR.

## Scope

- Bucket ID: `desktop-ui-workflows`
- Path count: `292`
- Tracked changes: `157`
- Untracked paths: `135`
- Deleted paths: `1`
- Must-ship/release-critical paths: `204`
- Generated-only paths: `0`
- Binary/evidence paths: `0`
- Defer/exclude review paths: `88`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `app-ui`: `204`
- `other`: `4`
- `planetarium`: `29`
- `plugins`: `11`
- `ui-system`: `18`
- `updater`: `10`
- `webrtc`: `16`

## Representative Paths

- ` M` `apps/desktop/lib/main.dart` (other)
- ` M` `apps/desktop/lib/screens/framing/framing_search_provider.dart` (other)
- ` M` `apps/desktop/lib/screens/sequencer/tabs/targets_tab.dart` (other)
- ` M` `apps/desktop/lib/widgets/update_manager.dart` (other)
- ` M` `packages/nightshade_app/lib/app.dart` (app-ui)
- `??` `packages/nightshade_app/lib/localization/nightshade_localizations.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/router/app_router.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/analytics_screen.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/image_thumbnail_strip.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/analytics/widgets/mpc_export_panel.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/analytics/widgets/period_analysis_panel.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/analytics/widgets/photometric_calibration_wizard.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/analytics/widgets/project_tracking_panel.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/analytics/widgets/quick_csv_export.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/science_analytics_tab.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/analytics/widgets/science_export_hub.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/science_insights_panel.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/science_overlay_composer.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/dashboard/dashboard_screen.dart` (app-ui)
- ` D` `packages/nightshade_app/lib/screens/dashboard/dashboard_widgets.dart` (app-ui)
- ... 272 more paths in `docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt`.

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
