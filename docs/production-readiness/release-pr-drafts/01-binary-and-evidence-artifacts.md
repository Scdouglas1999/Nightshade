# PR 01: Binary And Evidence Artifacts

## Summary

Review DLLs, APKs, screenshots, databases, and other binary artifacts outside normal source diffs.

Recommended staging decision: Keep release payload binaries and smoke evidence in a deliberate artifact review; exclude scratch screenshots and research blobs from the release PR.

## Scope

- Bucket ID: `binary-and-evidence-artifacts`
- Path count: `1`
- Tracked changes: `1`
- Untracked paths: `0`
- Deleted paths: `0`
- Must-ship/release-critical paths: `0`
- Generated-only paths: `0`
- Binary/evidence paths: `1`
- Defer/exclude review paths: `1`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/01-binary-and-evidence-artifacts.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `binary-native-artifact`: `1`

## Representative Paths

- `M ` `docs/design/goldens/surface-run-session-progress.png` (binary-native-artifact)

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
