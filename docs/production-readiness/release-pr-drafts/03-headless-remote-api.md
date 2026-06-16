# PR 03: Headless Remote API And Dashboard

## Summary

Review headless server routes, auth policy, dashboard assets, LAN behavior, and WebSocket changes as one API surface.

Recommended staging decision: Pair this bucket with route contract tests, dashboard smoke logs, auth/LAN evidence, and reconnect evidence.

## Scope

- Bucket ID: `headless-remote-api`
- Path count: `33`
- Tracked changes: `33`
- Untracked paths: `0`
- Deleted paths: `0`
- Must-ship/release-critical paths: `30`
- Generated-only paths: `0`
- Binary/evidence paths: `0`
- Defer/exclude review paths: `3`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/03-headless-remote-api.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `headless-remote`: `33`

## Representative Paths

- `M ` `apps/desktop/lib/headless_api/handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/analytics_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/auxiliary_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/calibration_handlers/dark_library_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/calibration_handlers/defect_map_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/collaboration_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/device_handlers/mount_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/filesystem_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/imaging_handlers.dart` (headless-remote)
- `A ` `apps/desktop/lib/headless_api/handlers/narrator_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/planetarium_handlers.dart` (headless-remote)
- `A ` `apps/desktop/lib/headless_api/handlers/post_session_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/profile_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/run_watch_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/science_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/sequencer_handlers.dart` (headless-remote)
- `A ` `apps/desktop/lib/headless_api/handlers/stacking_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/system_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/update_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/weather_handlers.dart` (headless-remote)
- ... 13 more paths in `docs/production-readiness/release-pr-pathspecs/03-headless-remote-api.txt`.

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
