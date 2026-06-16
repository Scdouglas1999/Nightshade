# PR 07: Tests And Support Tooling

## Summary

Review non-release test files, scripts, package config, and developer tooling separately from product behavior.

Recommended staging decision: Stage only support changes needed to verify the release; defer unrelated audit scratch or developer-only helpers.

## Scope

- Bucket ID: `tests-and-support-tooling`
- Path count: `16`
- Tracked changes: `16`
- Untracked paths: `0`
- Deleted paths: `0`
- Must-ship/release-critical paths: `0`
- Generated-only paths: `0`
- Binary/evidence paths: `0`
- Defer/exclude review paths: `16`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/07-tests-and-support-tooling.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `tests`: `14`
- `tooling`: `2`

## Representative Paths

- `M ` `apps/desktop/test/headless_api/auxiliary_handlers_test.dart` (tests)
- `M ` `apps/desktop/test/headless_api/filesystem_handlers_test.dart` (tests)
- `A ` `apps/desktop/test/headless_api/mount_status_serialization_test.dart` (tests)
- `A ` `apps/desktop/test/headless_api/set_location_mirror_test.dart` (tests)
- `A ` `apps/desktop/test/headless_api/stacking_handlers_test.dart` (tests)
- `M ` `apps/desktop/test/headless_api/update_handlers_test.dart` (tests)
- `M ` `packages/nightshade_app/test/screens/imaging/widgets/rotator_panel_angle_range_test.dart` (tests)
- `A ` `packages/nightshade_core/test/backend/network_backend_narrator_test.dart` (tests)
- `A ` `packages/nightshade_core/test/backend/network_backend_switch_test.dart` (tests)
- `M ` `packages/nightshade_core/test/backend/network_backend_websocket_test.dart` (tests)
- `A ` `packages/nightshade_core/test/database/database_connection_test.dart` (tests)
- `A ` `packages/nightshade_core/test/live_appliance_realtime_probe.dart` (tests)
- `M ` `packages/nightshade_core/test/providers/sequence/sequence_executor_live_stacking_autofeed_test.dart` (tests)
- `M ` `packages/nightshade_core/test/utils/device_id_test.dart` (tests)
- `M ` `scripts/dev.sh` (tooling)
- `M ` `scripts/docker_build_linux.sh` (tooling)

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
