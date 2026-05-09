# PR 10: Out Of Release Scope Review

## Summary

Quarantine scratch reports, research files, goal tracking, and broad miscellaneous edits until they are explicitly accepted or excluded.

Recommended staging decision: Do not stage into the public release branch without owner review and an explicit reason.

## Scope

- Bucket ID: `out-of-release-scope-review`
- Path count: `57`
- Tracked changes: `13`
- Untracked paths: `44`
- Deleted paths: `0`
- Must-ship/release-critical paths: `0`
- Generated-only paths: `0`
- Binary/evidence paths: `0`
- Defer/exclude review paths: `57`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `docs`: `25`
- `other`: `32`

## Representative Paths

- `??` `.audit_highrisk.txt` (other)
- `??` `.audit_highrisk_debug.txt` (other)
- `??` `.audit_hits.txt` (other)
- `??` `.audit_hits_debug.txt` (other)
- ` M` `.behavioral_audit_hits.txt` (other)
- `??` `.github/workflows/linux-release-build.yml` (other)
- `??` `.ui_consistency_audit.txt` (other)
- `??` `_fw_research/GXUP0006.DAT` (other)
- `??` `_fw_research/GXUP0007.DAT` (other)
- ` M` `docs/api/README.md` (docs)
- ` M` `docs/api/bridge-api.md` (docs)
- ` M` `docs/api/data-models.md` (docs)
- ` M` `docs/api/plugin-api.md` (docs)
- ` M` `docs/api/web-server-api.md` (docs)
- ` M` `docs/features/imaging.md` (docs)
- ` M` `docs/features/sequencing.md` (docs)
- ` M` `docs/getting-started/first-connection.md` (docs)
- ` M` `docs/getting-started/first-image.md` (docs)
- ` M` `docs/getting-started/installation.md` (docs)
- ` M` `docs/index.md` (docs)
- ... 37 more paths in `docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt`.

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
