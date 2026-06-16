# PR 02: Release Infrastructure And Evidence

## Summary

Keep release gates, production audit tools, public readiness docs, and operational docs together.

Recommended staging decision: Stage audit tooling and evidence docs as the release-readiness PR only after confirming each artifact is current and reproducible.

## Scope

- Bucket ID: `release-infra-evidence`
- Path count: `67`
- Tracked changes: `67`
- Untracked paths: `0`
- Deleted paths: `1`
- Must-ship/release-critical paths: `67`
- Generated-only paths: `0`
- Binary/evidence paths: `0`
- Defer/exclude review paths: `0`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/02-release-infra-evidence.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `docs`: `3`
- `other`: `15`
- `release-evidence-docs`: `47`
- `release-tooling`: `2`

## Representative Paths

- `M ` `.github/workflows/linux-release-build.yml` (other)
- `M ` `.github/workflows/release.yml` (other)
- `M ` `apps/desktop/linux/CMakeLists.txt` (other)
- `M ` `docs/headless-secure-setup.md` (docs)
- `A ` `docs/production-readiness/analyzer-rollup.json` (release-evidence-docs)
- `A ` `docs/production-readiness/developer-quality-audit.json` (release-evidence-docs)
- `A ` `docs/production-readiness/developer-quality-audit.md` (release-evidence-docs)
- `A ` `docs/production-readiness/external-evidence-templates/final-release-signoff-evidence.template.json` (release-evidence-docs)
- `A ` `docs/production-readiness/external-evidence-templates/full-hardware-control-smoke-evidence.template.json` (release-evidence-docs)
- `A ` `docs/production-readiness/external-evidence-templates/linux-release-build-evidence.template.json` (release-evidence-docs)
- `A ` `docs/production-readiness/external-evidence-templates/real-remote-control-actions-evidence.template.json` (release-evidence-docs)
- `A ` `docs/production-readiness/external-evidence-templates/second-device-lan-firewall-smoke-evidence.template.json` (release-evidence-docs)
- `A ` `docs/production-readiness/fail-closed-audit.json` (release-evidence-docs)
- `A ` `docs/production-readiness/fail-closed-audit.md` (release-evidence-docs)
- `A ` `docs/production-readiness/headless-api-contract-audit.json` (release-evidence-docs)
- `A ` `docs/production-readiness/headless-api-contract-audit.md` (release-evidence-docs)
- `A ` `docs/production-readiness/linux-environment-probe.json` (release-evidence-docs)
- `A ` `docs/production-readiness/linux-environment-probe.md` (release-evidence-docs)
- `A ` `docs/production-readiness/linux-release-build-evidence.json` (release-evidence-docs)
- `A ` `docs/production-readiness/linux-release-package-metadata.json` (release-evidence-docs)
- ... 47 more paths in `docs/production-readiness/release-pr-pathspecs/02-release-infra-evidence.txt`.

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
