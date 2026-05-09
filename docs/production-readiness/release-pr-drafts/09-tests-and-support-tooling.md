# PR 09: Tests And Support Tooling

## Summary

Review non-release test files, scripts, package config, and developer tooling separately from product behavior.

Recommended staging decision: Stage only support changes needed to verify the release; defer unrelated audit scratch or developer-only helpers.

## Scope

- Bucket ID: `tests-and-support-tooling`
- Path count: `64`
- Tracked changes: `14`
- Untracked paths: `50`
- Deleted paths: `0`
- Must-ship/release-critical paths: `0`
- Generated-only paths: `0`
- Binary/evidence paths: `0`
- Defer/exclude review paths: `64`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `package-config`: `2`
- `tests`: `58`
- `tooling`: `4`

## Representative Paths

- ` M` `apps/desktop/pubspec.yaml` (package-config)
- `??` `apps/desktop/test/headless_api/analytics_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/auth_middleware_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/auth_policy_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/auxiliary_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/backup_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/device_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/equipment_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/filesystem_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/flat_wizard_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/focus_model_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/framing_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/guiding_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/imaging_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/mosaic_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/network_backend_contract_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/planetarium_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/profile_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/response_helpers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/route_metadata_test.dart` (tests)
- ... 44 more paths in `docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt`.

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
