# PR 02: Binary And Evidence Artifacts

## Summary

Review DLLs, APKs, screenshots, databases, and other binary artifacts outside normal source diffs.

Recommended staging decision: Keep release payload binaries and smoke evidence in a deliberate artifact review; exclude scratch screenshots and research blobs from the release PR.

## Scope

- Bucket ID: `binary-and-evidence-artifacts`
- Path count: `31`
- Tracked changes: `2`
- Untracked paths: `29`
- Deleted paths: `0`
- Must-ship/release-critical paths: `4`
- Generated-only paths: `0`
- Binary/evidence paths: `31`
- Defer/exclude review paths: `27`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `binary-native-artifact`: `27`
- `release-evidence-binary`: `4`

## Representative Paths

- ` M` `apps/desktop/nightshade_bridge.dll` (binary-native-artifact)
- ` M` `apps/desktop/windows/nightshade_bridge.dll` (binary-native-artifact)
- `??` `docs/production-readiness/android-emulator-launch-smoke.png` (release-evidence-binary)
- `??` `docs/production-readiness/android-emulator-remote-smoke-latest.png` (release-evidence-binary)
- `??` `docs/production-readiness/android-emulator-remote-smoke-start.png` (release-evidence-binary)
- `??` `docs/production-readiness/android-emulator-remote-smoke.png` (release-evidence-binary)
- `??` `report/gui-after-planner-pass.png` (binary-native-artifact)
- `??` `report/gui-after-skip.png` (binary-native-artifact)
- `??` `report/gui-analytics.png` (binary-native-artifact)
- `??` `report/gui-dashboard-after-action-state.png` (binary-native-artifact)
- `??` `report/gui-dashboard.png` (binary-native-artifact)
- `??` `report/gui-diagnostics-deep.png` (binary-native-artifact)
- `??` `report/gui-diagnostics.png` (binary-native-artifact)
- `??` `report/gui-equipment.png` (binary-native-artifact)
- `??` `report/gui-flat-wizard-after-disable.png` (binary-native-artifact)
- `??` `report/gui-flat-wizard-deep.png` (binary-native-artifact)
- `??` `report/gui-guiding-deep.png` (binary-native-artifact)
- `??` `report/gui-imaging.png` (binary-native-artifact)
- `??` `report/gui-initial.png` (binary-native-artifact)
- `??` `report/gui-planetarium.png` (binary-native-artifact)
- ... 11 more paths in `docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt`.

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
