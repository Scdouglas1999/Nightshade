# PR 05: Core Data Model And Services

## Summary

Review database, model, provider, backend, migration, and shared service changes as a data/API compatibility set.

Recommended staging decision: Stage with focused tests and a real older-profile migration artifact; generated DB/model files stay in the generated-files bucket.

## Scope

- Bucket ID: `core-data-model`
- Path count: `25`
- Tracked changes: `25`
- Untracked paths: `0`
- Deleted paths: `0`
- Must-ship/release-critical paths: `25`
- Generated-only paths: `0`
- Binary/evidence paths: `0`
- Defer/exclude review paths: `0`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/05-core-data-model.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `core`: `25`

## Representative Paths

- `M ` `packages/nightshade_core/lib/src/backend/ffi_backend/bridge_model_mappers.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend/connection_lifecycle.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend/http_transport.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend/imaging_profile_operations.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend/planning_accessory_operations.dart` (core)
- `A ` `packages/nightshade_core/lib/src/backend/network_backend/post_session_operations.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend/remote_calibration_catalog_operations.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend/remote_live_view_operations.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend/session_science_operations.dart` (core)
- `A ` `packages/nightshade_core/lib/src/backend/network_backend/stacking_operations.dart` (core)
- `M ` `packages/nightshade_core/lib/src/database/database/connection.dart` (core)
- `M ` `packages/nightshade_core/lib/src/models/calibration/calibration_library_models.dart` (core)
- `M ` `packages/nightshade_core/lib/src/providers/defect_map_provider.dart` (core)
- `M ` `packages/nightshade_core/lib/src/providers/live_stacking_provider.dart` (core)
- `M ` `packages/nightshade_core/lib/src/providers/narrator_provider.dart` (core)
- `M ` `packages/nightshade_core/lib/src/providers/sequence/sequence_executor.dart` (core)
- `M ` `packages/nightshade_core/lib/src/services/calibration/defect_map_service.dart` (core)
- `M ` `packages/nightshade_core/lib/src/services/calibration_library_service.dart` (core)
- `M ` `packages/nightshade_core/lib/src/services/calibration_service.dart` (core)
- ... 5 more paths in `docs/production-readiness/release-pr-pathspecs/05-core-data-model.txt`.

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
