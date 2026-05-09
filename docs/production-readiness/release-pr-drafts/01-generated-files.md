# PR 01: Generated Files

## Summary

Review regenerated Dart, Drift, Freezed, bridge, and lock files apart from human-authored source.

Recommended staging decision: Regenerate from source, verify generator commands, then stage only outputs that correspond to reviewed model/API changes.

## Scope

- Bucket ID: `generated-files`
- Path count: `35`
- Tracked changes: `31`
- Untracked paths: `4`
- Deleted paths: `0`
- Must-ship/release-critical paths: `22`
- Generated-only paths: `35`
- Binary/evidence paths: `0`
- Defer/exclude review paths: `13`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/01-generated-files.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `generated`: `35`

## Representative Paths

- ` M` `apps/desktop/pubspec.lock` (generated)
- ` M` `apps/mobile/pubspec.lock` (generated)
- ` M` `packages/nightshade_bridge/ios/bridge_generated.h` (generated)
- ` M` `packages/nightshade_bridge/lib/src/error.freezed.dart` (generated)
- ` M` `packages/nightshade_bridge/lib/src/event.freezed.dart` (generated)
- ` M` `packages/nightshade_bridge/lib/src/frb_generated.dart` (generated)
- ` M` `packages/nightshade_bridge/lib/src/frb_generated.io.dart` (generated)
- ` M` `packages/nightshade_bridge/linux/bridge_generated.h` (generated)
- ` M` `packages/nightshade_bridge/macos/bridge_generated.h` (generated)
- `??` `packages/nightshade_core/lib/src/database/daos/dark_library_dao.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/database/daos/flat_history_dao.g.dart` (generated)
- `??` `packages/nightshade_core/lib/src/database/daos/observation_logs_dao.g.dart` (generated)
- `??` `packages/nightshade_core/lib/src/database/daos/observing_lists_dao.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/database/daos/polar_alignment_history_dao.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/database/daos/science_dao.g.dart` (generated)
- `??` `packages/nightshade_core/lib/src/database/daos/sequence_runs_dao.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/database/database.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/annotation_settings.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/annotation_settings.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/equipment_profile.freezed.dart` (generated)
- ... 15 more paths in `docs/production-readiness/release-pr-pathspecs/01-generated-files.txt`.

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
