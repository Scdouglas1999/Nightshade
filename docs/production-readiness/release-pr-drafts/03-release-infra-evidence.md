# PR 03: Release Infrastructure And Evidence

## Summary

Keep release gates, production audit tools, public readiness docs, and operational docs together.

Recommended staging decision: Stage audit tooling and evidence docs as the release-readiness PR only after confirming each artifact is current and reproducible.

## Scope

- Bucket ID: `release-infra-evidence`
- Path count: `164`
- Tracked changes: `5`
- Untracked paths: `159`
- Deleted paths: `0`
- Must-ship/release-critical paths: `163`
- Generated-only paths: `0`
- Binary/evidence paths: `0`
- Defer/exclude review paths: `1`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `docs`: `5`
- `other`: `1`
- `package-config`: `1`
- `release-evidence-docs`: `98`
- `release-tooling`: `59`

## Representative Paths

- `??` `docs/headless-secure-setup.md` (docs)
- `??` `docs/known-limitations.md` (docs)
- `??` `docs/migration-backup-restore.md` (docs)
- `??` `docs/production-readiness/analyzer-rollup.json` (release-evidence-docs)
- `??` `docs/production-readiness/android-emulator-remote-reconnect-smoke-log.txt` (release-evidence-docs)
- `??` `docs/production-readiness/android-emulator-remote-smoke-log.txt` (release-evidence-docs)
- `??` `docs/production-readiness/dependency-hygiene.json` (release-evidence-docs)
- `??` `docs/production-readiness/dependency-hygiene.md` (release-evidence-docs)
- `??` `docs/production-readiness/developer-quality-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/developer-quality-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/docs-link-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/docs-link-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/external-evidence-templates/final-release-signoff-evidence.template.json` (release-evidence-docs)
- `??` `docs/production-readiness/external-evidence-templates/full-hardware-control-smoke-evidence.template.json` (release-evidence-docs)
- `??` `docs/production-readiness/external-evidence-templates/linux-release-build-evidence.template.json` (release-evidence-docs)
- `??` `docs/production-readiness/external-evidence-templates/real-remote-control-actions-evidence.template.json` (release-evidence-docs)
- `??` `docs/production-readiness/external-evidence-templates/second-device-lan-firewall-smoke-evidence.template.json` (release-evidence-docs)
- `??` `docs/production-readiness/fail-closed-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/fail-closed-audit.md` (release-evidence-docs)
- ` M` `docs/production-readiness/feature-parity-matrix.md` (release-evidence-docs)
- ... 144 more paths in `docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt`.

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
