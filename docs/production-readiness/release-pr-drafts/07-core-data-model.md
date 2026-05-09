# PR 07: Core Data Model And Services

## Summary

Review database, model, provider, backend, migration, and shared service changes as a data/API compatibility set.

Recommended staging decision: Stage with focused tests and a real older-profile migration artifact; generated DB/model files stay in the generated-files bucket.

## Scope

- Bucket ID: `core-data-model`
- Path count: `127`
- Tracked changes: `82`
- Untracked paths: `45`
- Deleted paths: `0`
- Must-ship/release-critical paths: `127`
- Generated-only paths: `0`
- Binary/evidence paths: `0`
- Defer/exclude review paths: `0`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `core`: `127`

## Representative Paths

- ` M` `packages/nightshade_core/lib/nightshade_core.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/disconnected_backend.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/ffi_backend.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/nightshade_backend.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/daos/dark_library_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/equipment_profiles_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/flat_history_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/images_dao.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/daos/observation_logs_dao.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/daos/observing_lists_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/polar_alignment_history_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/science_dao.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/daos/sequence_runs_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/sequences_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/sessions_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/targets_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/weather_settings_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/database.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/tables/captured_images.dart` (core)
- ... 107 more paths in `docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt`.

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
